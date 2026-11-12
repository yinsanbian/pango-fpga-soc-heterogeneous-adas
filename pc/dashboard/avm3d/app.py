"""AVM3D PC 扩展入口：SIM / REPLAY / LIVE(门禁) 三种来源，一个 OpenCV 窗口。

与 2D Dashboard 的关系：
- 完全独立的入口与进程；复用同一份 `dashboard/protocol` 解码与 `dashboard/ui/text` 字体；
- 不修改/不阻塞 `dashboard/app.py`，关闭本程序对 2D 基线没有任何影响；
- 3D 纹理由 OpenGL(hidden glfw context) 渲染，窗口仍用 OpenCV HighGUI 显示合成画布。

诚实性约定（方案 §5/SIM 横幅、§6.3 指标）：
- `--source sim` 常驻 `SIM` 横幅；`--source replay` 常驻 `REPLAY` 横幅；
- `--source live` 永远打印 BLOCKED 原因码并以退出码 3 结束，**不**回退到 SIM；
- 帧率/丢帧/CRC/seq_gap 全部实测；不写死 FPS，不显示跨板总延迟。
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import traceback
from datetime import datetime, timezone
from pathlib import Path

import cv2
import numpy as np

# 允许 `python dashboard\avm3d\app.py` 直接运行（不必先 pip install -e .）
ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from dashboard.avm3d.calib.loader import CalibrationError, load_calibration  # noqa: E402
from dashboard.avm3d.config import (  # noqa: E402
    CANVAS_H, CANVAS_W, DEFAULT_CALIBRATION, DEFAULT_FRAME_CACHE, DEFAULT_MATCH_SEARCH,
    DEFAULT_REPLAY_MANIFEST, RunStats,
)
from dashboard.avm3d.mem import MemoryMonitor  # noqa: E402
from dashboard.avm3d.protocol_bridge import AvmProtocolStore  # noqa: E402
from dashboard.avm3d.sources.base import FaultWindow, SourceError, fault_from_seconds  # noqa: E402
from dashboard.avm3d.sources.board import BoardSource, load_board_config  # noqa: E402
from dashboard.avm3d.sources.hdmi import live_status  # noqa: E402
from dashboard.avm3d.sources.replay import (  # noqa: E402
    ReplaySource, load_manifest, manifest_from_files,
)
from dashboard.avm3d.sources.sim import FAULT_KINDS, SIM_FPS, SimSource  # noqa: E402
from dashboard.avm3d.view3d import View3D  # noqa: E402

WIN_BASE = "AVM 3D"
LIVE_EXIT = 3
FATAL_EXIT = 4
ARG_EXIT = 2


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    ap = argparse.ArgumentParser(
        description="PC 端 AVM 3D 扩展（SIM/REPLAY/BOARD；LIVE 门禁未通过）",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    ap.add_argument("--source", choices=("sim", "replay", "board", "live"), default="sim")
    ap.add_argument("--sim-fps", type=float, default=SIM_FPS,
                    help="SIM 合成源帧率（30=设计值；长跑可用 20 给 HUD 留余量，如实显示 input_fps）")
    ap.add_argument("--view", type=int, default=2, choices=(1, 2, 3),
                    help="视图模式：1 相机+车道，2 +目标，3 +运动/深度状态")
    ap.add_argument("--camera-view", choices=("reset", "top", "aerial", "oblique", "front", "rear"),
                    default=None,
                    help="虚拟相机初始视角；top=垂直俯瞰，aerial=高俯视。默认沿用 oblique")
    ap.add_argument("--detect-camera", choices=("front", "right", "rear", "left"),
                    default="front",
                    help="YOLO/单路模式选用的相机通道（手动选前向）；运行中按 c 循环切换")
    ap.add_argument("--layout", choices=("3d", "single"), default="3d",
                    help="3d=四路碗面；single=只展示选中单路的识别画面；运行中按 v 切换")
    ap.add_argument("--calib", default=str(DEFAULT_CALIBRATION))
    ap.add_argument("--alt-calib", default=None,
                    help="窗口内按钮切换到的第二份标定（仅 replay；用于 SENSOR GEOM / SYNTH FILL 对比）")
    ap.add_argument("--video-source", choices=("hdmi",), default=None,
                    help="LIVE 视频来源（仅 --source live；G0-03 未冻结，当前必为 BLOCKED）")
    ap.add_argument("--board-config", default=None,
                    help="板端视频配置 JSON（仅 --source board）")
    ap.add_argument("--lane-onnx", default=None,
                    help="PC 本地车道模型；单路模式默认用 tools/_lane_runs/v9/lanenet.onnx")
    ap.add_argument("--no-lane", action="store_true",
                    help="关闭 PC 本地车道/弯向（板端仍然只发 OBJECT）")
    # 回放输入：三选一，优先级 manifest > replay 目录 > video+log
    ap.add_argument("--manifest", default=None, help="回放清单 JSON（推荐）")
    ap.add_argument("--replay", default=None, metavar="DIR",
                    help="夹具目录（自动找 avm_sim_manifest.json）；仅 replay 源使用")
    ap.add_argument("--video", default=None, help="四宫格 MP4（无清单时的快捷入口）")
    ap.add_argument("--log", default=None, help="协议 ndjson（无清单时的快捷入口）")
    ap.add_argument("--no-verify-sha", action="store_true",
                    help="跳过回放 sha256 校验（不推荐，报告里会注明）")
    ap.add_argument("--loop", action="store_true", help="回放循环（帧号回到起点会重同步）")
    # 时长
    ap.add_argument("--frames", type=int, default=0, help="最多处理 N 帧（0=不限制）")
    ap.add_argument("--seconds", type=float, default=0.0,
                    help="按源时间限制（换算为 round(seconds*fps) 帧）")
    ap.add_argument("--realtime", action=argparse.BooleanOptionalAction, default=True,
                    help="按源 fps 节拍（关闭=尽快跑，性能测量用，报告中注明）")
    # 故障注入（SIM）
    ap.add_argument("--faults", nargs="*", default=[], metavar="KIND:START:END[:PARAM]",
                    help=f"SIM 故障窗口，kind ∈ {', '.join(FAULT_KINDS)}")
    # 输出
    ap.add_argument("--headless", action="store_true", help="不创建窗口（仍渲染画布）")
    ap.add_argument("--shots", type=int, default=0, help="保存 N 张 1600x900 截图")
    ap.add_argument("--out-dir", default=str(ROOT / "reports" / "avm3d_shots"))
    ap.add_argument("--stats-out", default=None, help="运行统计 JSON 路径")
    ap.add_argument("--metrics-out", default=None, help="逐帧指标 CSV 路径")
    ap.add_argument("--force-no-gl", action="store_true",
                    help="强制走 OPENGL_UNAVAILABLE 降级路径（验收演示）")
    ap.add_argument("--wait-ms", type=float, default=12.0,
                    help="同帧 bundle 的有限等待上限（ms）")
    ap.add_argument("--frame-cache", type=int, default=DEFAULT_FRAME_CACHE,
                    help="协议 bundle 缓存帧数；板端实时演示建议 120，避免帧号错位被挤掉")
    return ap.parse_args(argv)


def parse_fault(text: str, fps: float) -> FaultWindow:
    """kind:start_s:end_s[:param] -> FaultWindow（含节奏类故障，长跑用）。"""
    parts = text.split(":")
    if len(parts) < 3:
        raise SourceError("FAULT_SPEC_INVALID", f"应为 kind:start:end[:param]：{text!r}")
    kind = parts[0].strip()
    if kind not in FAULT_KINDS:
        raise SourceError("FAULT_SPEC_INVALID",
                          f"未知故障 {kind!r}，可用：{', '.join(FAULT_KINDS)}")
    try:
        start, end = float(parts[1]), float(parts[2])
        param = int(parts[3]) if len(parts) > 3 and parts[3] else 0
    except ValueError as exc:
        raise SourceError("FAULT_SPEC_INVALID", f"时间/参数不是数字：{text!r}") from exc
    if end <= start:
        raise SourceError("FAULT_SPEC_INVALID", f"故障窗口为空：{text!r}")
    return fault_from_seconds(start, end, kind, fps, param=param)


def find_manifest(fixture_dir: str | Path) -> Path:
    d = Path(fixture_dir).resolve()
    if d.is_file():
        return d
    if not d.exists():
        raise SourceError("REPLAY_MANIFEST_MISSING", f"夹具目录不存在：{d}")
    for name in ("avm_sim_manifest.json", "manifest.json"):
        p = d / name
        if p.exists():
            return p
    for p in sorted(d.glob("*.json")):
        try:
            raw = json.loads(p.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(raw, dict) and str(raw.get("format", "")).startswith("avm3d_replay"):
            return p
    raise SourceError("REPLAY_MANIFEST_MISSING", f"{d} 下没有 avm3d 回放清单")


def _source_status_dict(status) -> dict:
    return {
        "label": status.label, "video_source": status.video_source,
        "data_source": status.data_source, "detail": status.detail,
        "live": status.live, "mixed": status.mixed,
        "blocked_reason": status.blocked_reason, "banner": status.banner(),
    }


def _pct(values: list[float], p: float) -> float:
    if not values:
        return 0.0
    return float(np.percentile(np.asarray(values, dtype=np.float64), p))


def _shot_frames(shots: int, limit: int | None) -> set[int]:
    """截图帧号（1-based，与 frames_in 对齐）：有上限时均匀分布；无上限时第 11 帧起每 60 帧。"""
    if shots <= 0:
        return set()
    if limit and limit > 0:
        if shots == 1:
            return {1}
        span = max(limit - 1, 1)
        return {1 + int(round(span * i / (shots - 1))) for i in range(shots)}
    return {11 + 60 * i for i in range(shots)}


class MetricsWriter:
    COLS = ("t_s", "frame_id", "match_state", "waited_ms", "render_ms",
            "lane_status", "lane_offset_px", "lane_width_px", "object_count",
            "track_count", "motion_roi", "depth_status", "depth_reason",
            "crc_err", "drop", "seq_gap", "frame_mismatch_cnt")

    def __init__(self, path: str | Path | None, spec):
        self.fh = None
        self.spec = spec
        if path:
            p = Path(path)
            p.parent.mkdir(parents=True, exist_ok=True)
            self.fh = open(p, "w", encoding="utf-8", newline="\n")
            self.fh.write(",".join(self.COLS) + "\n")

    def write(self, t_s: float, view, store: AvmProtocolStore) -> None:
        if self.fh is None:
            return
        b = view.match.bundle
        spec = self.spec
        lane = b.first("LANE") if b else None
        lane_status = "NOT_PROVIDED"
        if lane is not None:
            lane_status = lane.status_name(spec)
        obj = b.first("OBJECT") if b else None
        n_obj = 0
        if obj is not None and obj.usable and obj.payload:
            n_obj = len(obj.payload.get("objects") or [])
        tr = b.first("TRACK_V1") if b else None
        n_tr = 0
        if tr is not None and tr.usable and tr.payload:
            n_tr = len(tr.payload.get("tracks") or [])
        depth = b.first("DEPTH") if b else None
        d_status = "NOT_PROVIDED" if depth is None else depth.status_name(spec)
        d_reason = "NOT_PROVIDED" if depth is None else depth.reason_name(spec)
        motion_roi = store.value(b, "MOTION", "roi_motion_ratio")

        def num(v, scale=1.0, fmt="{:.4f}"):
            return "" if v is None else fmt.format(float(v) / scale)

        row = [
            f"{t_s:.3f}", str(view.video.frame_id if view.video else ""),
            view.match.state, f"{view.match.waited_ms:.3f}",
            f"{view.render_ms:.3f}",
        ]
        row += [
            lane_status,
            num(store.value(b, "LANE", "center_offset_px"), fmt="{:.2f}"),
            num(store.value(b, "LANE", "lane_width_px"), fmt="{:.2f}"),
            str(n_obj), str(n_tr),
            "" if motion_roi is None else f"{motion_roi:.4f}",
            d_status, d_reason,
            str(store.stats()["crc_err"]), str(store.stats()["dropped"]),
            str(store.stats()["seq_gap"]), str(store.frame_mismatch_cnt),
        ]
        self.fh.write(",".join(row) + "\n")

    def close(self) -> None:
        if self.fh is not None:
            self.fh.close()
            self.fh = None


def _build_source(args, store, calib):
    """返回 (source, fps, manifest_or_None, notes)。"""
    notes: list[str] = []
    if args.video_source and args.source != "live":
        raise SourceError("ARGS_CONFLICT", "--video-source 只对 --source live 有效")
    source = args.source
    if source == "sim" and (args.replay or args.manifest or args.video or args.log):
        # 方案里的目标 CLI `--source sim --replay DIR`：语义等价于回放 SIM 夹具。
        notes.append("--source sim 携带回放输入，按等价处理为 --source replay")
        source = "replay"
    if source == "sim":
        if not (5.0 <= args.sim_fps <= 60.0):
            raise SourceError("ARGS_INVALID", f"--sim-fps 必须在 [5,60]，当前 {args.sim_fps}")
        faults = [parse_fault(s, args.sim_fps) for s in args.faults]
        limit = _limit_frames(args, args.sim_fps)
        src = SimSource(store, calib, fps=args.sim_fps, realtime=args.realtime,
                        max_frames=limit, faults=faults)
        return src, args.sim_fps, None, notes
    if source == "replay":
        if args.faults:
            notes.append("REPLAY 的故障在夹具生成时固化，--faults 已忽略")
        if args.manifest:
            man = load_manifest(args.manifest)
        elif args.replay:
            man = load_manifest(find_manifest(args.replay))
        elif args.video and args.log:
            man = manifest_from_files(args.video, args.log, calib)
            notes.append("使用 --video/--log 运行时清单（sha256 现算，不落盘）")
        elif DEFAULT_REPLAY_MANIFEST.exists():
            man = load_manifest(DEFAULT_REPLAY_MANIFEST)
            notes.append(f"使用默认夹具 {DEFAULT_REPLAY_MANIFEST}")
        else:
            raise SourceError("REPLAY_MANIFEST_MISSING",
                              "需要 --manifest、--replay DIR 或 --video+--log")
        limit = _limit_frames(args, man.fps)
        src = ReplaySource(store, calib, man, realtime=args.realtime, loop=args.loop,
                           verify_sha256=not args.no_verify_sha, max_frames=limit)
        return src, man.fps, man, notes
    if source == "board":
        if not args.board_config:
            raise SourceError("BOARD_CONFIG_MISSING",
                              "需要 --board-config（见 dashboard/avm3d/data/board/"
                              "board_config.example.json）")
        if args.replay or args.manifest or args.video or args.log:
            raise SourceError("ARGS_CONFLICT",
                              "--source board 使用 --board-config，不支持回放参数")
        if args.faults:
            notes.append("BOARD 源的故障注入未实现，--faults 已忽略")
        cfg = load_board_config(args.board_config)
        lane_onnx = args.lane_onnx
        if (lane_onnx is None and not args.no_lane
                and (args.layout == "single" or args.detect_camera == "front")):
            candidate = ROOT / "tools" / "_lane_runs" / "v9" / "lanenet.onnx"
            if candidate.exists():
                lane_onnx = str(candidate)
        if lane_onnx and not Path(lane_onnx).exists():
            raise SourceError("LANE_MODEL_MISSING", f"车道模型不存在：{lane_onnx}")
        limit = _limit_frames(args, cfg.video.fps)
        src = BoardSource(store, calib, cfg, realtime=args.realtime, max_frames=limit,
                          lane_onnx=lane_onnx, lane_camera=args.detect_camera)
        notes.append(f"board config={cfg.path}")
        if lane_onnx:
            notes.append(f"PC lane on: {lane_onnx}")
        return src, cfg.video.fps, None, notes
    raise SourceError("SOURCE_INVALID", args.source)


def _limit_frames(args, fps: float) -> int | None:
    if args.frames and args.seconds:
        raise SourceError("ARGS_CONFLICT", "--frames 与 --seconds 不能同时使用")
    if args.frames:
        return int(args.frames)
    if args.seconds:
        return max(int(round(args.seconds * fps)), 1)
    if args.headless:
        return max(int(round(10.0 * fps)), 1)
    return None


def run_live(args, calib, store) -> int:
    status = live_status()
    print("[avm3d] LIVE BLOCKED —— 不会回退到 SIM/REPLAY", file=sys.stderr)
    if args.video_source:
        print(f"[avm3d] 请求 --video-source {args.video_source}：门禁（G0-03/G0-05）未通过，"
              f"不予启用，也不降级成其它来源", file=sys.stderr)
    print(f"[avm3d] {status.banner()}", file=sys.stderr)
    for line in status.detail.split("；"):
        if line:
            print(f"  - {line}", file=sys.stderr)
    print(f"[avm3d] video_source={status.video_source} data_source={status.data_source}",
          file=sys.stderr)
    shot_path = ""
    if args.shots:
        from dashboard.avm3d.render.overlays import FrameView, MatchInfo, OverlayRenderer
        renderer = OverlayRenderer(calib, store.spec)
        view = FrameView(status=status, mode=args.view, video=None,
                         match=MatchInfo(state="NO_BUNDLE", missing=()),
                         gl_available=False, gl_reason=status.blocked_reason,
                         gl_detail=status.detail, fps={}, counters={}, source_stats={})
        canvas = renderer.canvas()
        renderer.draw(view, canvas)
        out = Path(args.out_dir)
        out.mkdir(parents=True, exist_ok=True)
        shot_path = str(out / "live_blocked.png")
        cv2.imwrite(shot_path, canvas)
        print(f"[avm3d] BLOCKED 截图：{shot_path}")
    if args.stats_out:
        doc = {
            "schema": "avm3d_run_stats_v1",
            "created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "argv": sys.argv[1:],
            "source": {"kind": "live", "status": _source_status_dict(status)},
            "result": "BLOCKED",
            "requested_video_source": args.video_source or "",
            "shot": shot_path,
        }
        p = Path(args.stats_out)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return LIVE_EXIT


def _enable_dpi_awareness() -> None:
    """让 1600x900 画布按物理像素显示，避免 150% DPI 下窗口被裁成半屏。"""
    if sys.platform != "win32":
        return
    try:
        import ctypes

        try:
            ctypes.windll.shcore.SetProcessDpiAwareness(2)  # PER_MONITOR_AWARE_V2
        except Exception:
            ctypes.windll.user32.SetProcessDPIAware()
    except Exception:
        pass


def main(argv: list[str] | None = None) -> int:
    _enable_dpi_awareness()
    args = parse_args(argv)
    try:
        calib = load_calibration(args.calib)
    except CalibrationError as exc:
        print(f"[avm3d] 标定不可用 {exc.code}: {exc.detail}", file=sys.stderr)
        return ARG_EXIT
    alt_calib = None
    if args.alt_calib:
        try:
            alt_calib = load_calibration(args.alt_calib)
        except CalibrationError as exc:
            print(f"[avm3d] 切换标定不可用 {exc.code}: {exc.detail}（按钮禁用）",
                  file=sys.stderr)
        else:
            reason = ""
            if args.source != "replay":
                reason = "--alt-calib 仅支持 --source replay"
            elif (alt_calib.atlas_width, alt_calib.atlas_height) != (
                    calib.atlas_width, calib.atlas_height):
                reason = "两份标定的 atlas 尺寸不一致"
            elif alt_calib.camera_layout != calib.camera_layout:
                reason = "两份标定的 camera_layout 不一致"
            elif alt_calib.calibration_id == calib.calibration_id:
                reason = "两份标定的 calibration_id 相同"
            if reason:
                print(f"[avm3d] --alt-calib 已忽略：{reason}", file=sys.stderr)
                alt_calib = None
    store = AvmProtocolStore(max_frames=max(4, int(args.frame_cache)),
                             match_search=DEFAULT_MATCH_SEARCH)
    if args.source == "live":
        return run_live(args, calib, store)

    try:
        source, fps, manifest, notes = _build_source(args, store, calib)
    except SourceError as exc:
        print(f"[avm3d] 启动失败 {exc.code}: {exc.detail}", file=sys.stderr)
        return ARG_EXIT

    view = View3D(store, calib, mode=args.view, use_gl=not args.force_no_gl,
                  force_no_gl_reason="--force-no-gl（验收降级演示）" if args.force_no_gl else "",
                  wait_ms=args.wait_ms, alt_calib=alt_calib)
    if args.camera_view:
        view.camera.set_view(args.camera_view)
    view.set_detect_camera(args.detect_camera)
    view.set_layout_mode(args.layout)
    if getattr(source, "single_video", False):
        view.set_single_video(True)
        notes.append("single video source -> layout=single, detect/view=front")
    print(f"[avm3d] source={args.source} {source.status.banner()}")
    print(f"[avm3d] {source.describe()}")
    print(f"[avm3d] detect_camera={view.detect_camera} layout={view.layout_mode}")
    print(f"[avm3d] calib id={calib.calibration_id} sha={calib.sha256[:12]}… "
          f"atlas={calib.atlas_width}x{calib.atlas_height}")
    if alt_calib is not None:
        tag = (alt_calib.provenance or {}).get("ui_tag", "") or "ALT"
        print(f"[avm3d] toggle calib id={alt_calib.calibration_id} tag={tag}"
              f"（窗口顶部按钮或 m 切换）")
    if view.gl_available:
        info = view.gl_info
        print(f"[avm3d] GL {info.get('version')} · {info.get('renderer')}")
    else:
        print(f"[avm3d] {view.gl_reason}: {view.gl_detail} —— 3D 不可用，2D HUD 继续",
              file=sys.stderr)
    for n in notes:
        print(f"[avm3d] note: {n}")

    out_dir = Path(args.out_dir)
    shot_frames = _shot_frames(args.shots, source.max_frames if hasattr(source, "max_frames") else None)
    metrics = MetricsWriter(args.metrics_out, store.spec)
    run = RunStats()
    mem = MemoryMonitor(interval_s=5.0)
    mem.maybe_sample()
    frame_times: list[float] = []
    shots_saved: list[str] = []
    win = f"{WIN_BASE} | {source.status.label}"
    t_start = time.monotonic()

    window_place_until = 0.0
    if not args.headless:
        # WINDOW_AUTOSIZE 让 HighGUI 按 1600x900 画布创建客户区；DPI 感知后
        # 窗口本身是 1622x956 物理像素，但上次保存的位置可能在屏幕外。
        cv2.namedWindow(win, cv2.WINDOW_AUTOSIZE)
        cv2.setMouseCallback(win, lambda e, x, y, f, _p: view.handle_mouse(e, x, y, f))
        window_place_until = time.monotonic() + 1.5

    source.start()
    exit_code = 0
    last_canvas = None

    gl_snapshot = {"available": view.gl_available, "reason": view.gl_reason,
                   "detail": view.gl_detail, "info": view.gl_info}
    try:
        while True:
            if source.fatal is not None:
                exit_code = FATAL_EXIT
                break
            video = source.poll(0.05)
            now = time.monotonic()
            elapsed = max(now - t_start, 1e-9)
            if video is None:
                if source.ended.is_set():
                    break
                if not args.headless:
                    key = cv2.waitKey(1) & 0xFF
                    if key in (27, ord("q")):
                        break
                    _handle_key(view, key)
                continue
            run.frames_in += 1
            fps_now = {
                "input_fps": run.frames_in / elapsed,
                "matched_fps": run.matched / elapsed,
                "render_fps": run.frames_rendered / elapsed,
            }
            counters = _counters(store, source, run)
            run.cached_frames_max = max(run.cached_frames_max, counters["cached_frames"])
            mem.maybe_sample(now)
            t_render = time.perf_counter()
            canvas, fv = view.compose(
                video, source.status, fps_now, counters, source.stats(),
                note=f"wait≤{args.wait_ms:.0f} ms · {'realtime' if args.realtime else '无节拍'}",
                uptime_s=elapsed)
            render_ms = (time.perf_counter() - t_render) * 1000.0
            fv.render_ms = render_ms
            last_canvas = canvas
            run.frames_rendered += 1
            frame_times.append(render_ms)
            if fv.match.state == "MATCHED":
                run.matched += 1
            else:
                run.unmatched += 1
            run.frame_mismatch_cnt = store.frame_mismatch_cnt
            metrics.write(elapsed, fv, store)

            if run.frames_in in shot_frames:
                out_dir.mkdir(parents=True, exist_ok=True)
                path = out_dir / f"avm3d_{args.source}_f{run.frames_in:05d}_{video.frame_id:06d}.png"
                cv2.imwrite(str(path), canvas)
                shots_saved.append(str(path))
                print(f"[avm3d] shot {path}")

            if not args.headless:
                cv2.imshow(win, canvas)
                if time.monotonic() < window_place_until:
                    _place_window_at_origin(win)
                key = cv2.waitKey(1) & 0xFF
                if key in (27, ord("q")):
                    break
                _handle_key(view, key)
    except KeyboardInterrupt:
        print("[avm3d] 收到中断，写入统计后退出", file=sys.stderr)
    except Exception as exc:  # noqa: BLE001 - 顶层兜底，保证统计落盘
        exit_code = FATAL_EXIT
        print(f"[avm3d] 运行失败：{exc!r}", file=sys.stderr)
        traceback.print_exc()
    finally:
        mem.maybe_sample(force=True)
        if (last_canvas is not None and args.shots
                and len(shots_saved) < args.shots):
            out_dir.mkdir(parents=True, exist_ok=True)
            path = out_dir / f"avm3d_{args.source}_final.png"
            cv2.imwrite(str(path), last_canvas)
            shots_saved.append(str(path))
            print(f"[avm3d] shot(尾帧补足) {path}")
        source.stop()
        view.close()
        metrics.close()
        run.ended_ns = time.monotonic_ns()
        run.source_drops = source.queue.put_drops
        run.queue_drops = source.queue.put_drops
        run.queue_size_max = source.queue.max_size
        run.gl_errors = view.gl_errors
        elapsed = max(time.monotonic() - t_start, 1e-9)
        doc = {
            "schema": "avm3d_run_stats_v1",
            "created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "argv": sys.argv[1:],
            "source": {
                "kind": args.source,
                "status": _source_status_dict(source.status),
                "stats": source.stats(),
                "fatal": f"{source.fatal.code}: {source.fatal.detail}" if source.fatal else "",
            },
            "calibration": {
                "path": str(calib.path), "sha256": calib.sha256,
                "id": calib.calibration_id,
                "atlas": [calib.atlas_width, calib.atlas_height],
                "cameras": list(calib.camera_order),
            },
            "replay_manifest": (manifest.summary() if manifest else None),
            "gl": {
                "available": gl_snapshot["available"], "reason": gl_snapshot["reason"],
                "detail": gl_snapshot["detail"], "info": gl_snapshot["info"],
                "errors": view.gl_errors,
            },
            "view": {"mode": view.mode, "headless": args.headless,
                     "canvas": [CANVAS_W, CANVAS_H], "window": "" if args.headless else win},
            "run": {
                "frames_in": run.frames_in, "frames_rendered": run.frames_rendered,
                "matched": run.matched, "unmatched": run.unmatched,
                "frame_mismatch_cnt": run.frame_mismatch_cnt,
                "source_drops": run.source_drops, "queue_drops": run.queue_drops,
                "gl_errors": run.gl_errors, "elapsed_s": elapsed,
                "queue_size_max": run.queue_size_max,
                "cached_frames_max": run.cached_frames_max,
                "memory_rss_kb": mem.summary(),
                "fps": {
                    "render_fps": run.frames_rendered / max(elapsed, 1e-9),
                    "input_fps": run.frames_in / max(elapsed, 1e-9),
                    "matched_fps": run.matched / max(elapsed, 1e-9),
                },
                "frame_time_ms": {
                    "p50": _pct(frame_times, 50), "p95": _pct(frame_times, 95),
                    "max": max(frame_times) if frame_times else 0.0,
                    "samples": len(frame_times),
                },
            },
            "counters": store.stats(),
            "shots": shots_saved,
            "notes": notes + ([f"source fatal: {source.fatal}"] if source.fatal else []) +
                     (["--no-verify-sha：回放未校验 sha256"] if args.no_verify_sha else []),
        }
        if args.stats_out:
            p = Path(args.stats_out)
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n",
                         encoding="utf-8")
            print(f"[avm3d] stats -> {p}")
        ss = source.stats()
        print(f"[avm3d] frames in {run.frames_in} / produced {ss.get('frames_produced', 0)} · "
              f"rendered {run.frames_rendered} · matched {run.matched} · "
              f"mismatch {run.frame_mismatch_cnt} · "
              f"video skipped {ss.get('queue_stale_skipped', 0)} · "
              f"put_drops {ss.get('queue_put_drops', 0)} · "
              f"protocol crc_err {store.stats()['crc_err']} · drop {store.stats()['dropped']} · "
              f"seq_gap {store.stats()['seq_gap']} · "
              f"queue_max {run.queue_size_max} · cache_max {run.cached_frames_max} · "
              f"rss max {(mem.max_kb or 0) / 1024:.0f} MB · "
              f"render_fps {run.frames_rendered / max(elapsed, 1e-9):.1f} · "
              f"input_fps {run.frames_in / max(elapsed, 1e-9):.1f} · "
              f"matched_fps {run.matched / max(elapsed, 1e-9):.1f}")
        if source.fatal is not None:
            print(f"[avm3d] source fatal {source.fatal.code}: {source.fatal.detail}",
                  file=sys.stderr)
    return exit_code


def _place_window_at_origin(win: str) -> bool:
    """把 HighGUI 窗口移到 (0,0)，避免上次保存的位置把右侧/底部推出屏幕。"""
    if sys.platform != "win32":
        return False
    try:
        import ctypes
        from ctypes import wintypes

        user32 = ctypes.windll.user32
        user32.FindWindowW.restype = wintypes.HWND
        user32.FindWindowW.argtypes = [wintypes.LPCWSTR, wintypes.LPCWSTR]
        user32.SetWindowPos.argtypes = [wintypes.HWND, wintypes.HWND,
                                        ctypes.c_int, ctypes.c_int, ctypes.c_int,
                                        ctypes.c_int, ctypes.c_uint]
        user32.SetWindowPos.restype = wintypes.BOOL
        hwnd = user32.FindWindowW(None, win)
        if not hwnd:
            return False
        # 只移动，不改尺寸：客户区已经由 WINDOW_AUTOSIZE 保持 1600x900。
        return bool(user32.SetWindowPos(hwnd, None, 0, 0, 0, 0,
                                        0x0001 | 0x0004 | 0x0010))
    except Exception:
        return False


def _handle_key(view: View3D, key: int) -> None:
    if key in (ord("1"), ord("2"), ord("3")):
        view.set_mode(key - ord("0"))
    elif key == ord("r"):
        view.camera.set_view("reset")
    elif key == ord("t"):
        view.camera.set_view("top")
    elif key == ord("a"):
        view.camera.set_view("aerial")
    elif key == ord("o"):
        view.camera.set_view("oblique")
    elif key == ord("f"):
        view.camera.set_view("front")
    elif key == ord("b"):
        view.camera.set_view("rear")
    elif key in (ord("m"), ord("M")):
        view.toggle_display_mode()
    elif key in (ord("c"), ord("C")):
        view.cycle_view_camera()
    elif key in (ord("v"), ord("V")):
        view.toggle_layout_mode()


def _counters(store: AvmProtocolStore, source, run: RunStats) -> dict:
    st = store.stats()
    q = source.queue
    return {
        "frames": run.frames_in,
        "matched": run.matched,
        "rendered": run.frames_rendered,
        "frame_mismatch_cnt": store.frame_mismatch_cnt,
        "drop": st["dropped"],
        "crc_err": st["crc_err"],
        "seq_gap": st["seq_gap"],
        "cached_frames": st["cached_frames"],
        "evicted": st["evicted"],
        "queue_put_drops": q.put_drops,
        "queue_stale_skipped": q.stale_skipped,
    }


if __name__ == "__main__":
    raise SystemExit(main())
