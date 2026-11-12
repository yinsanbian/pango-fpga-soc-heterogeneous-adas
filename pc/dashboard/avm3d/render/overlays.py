"""1600x900 合成画布：来源诚实性横幅 + 同帧状态 + 数据面板 + 底部条。

原则：
- 这里只**展示**已经按 frame_id 匹配好的同帧 bundle，不从邻帧补值；
- 没有 status=OK 的字段一律显示原因码（NOT_PROVIDED / LANE_LOST / DEPTH_GATE …），
  不显示“上一帧的值”或任何推算值；
- 3D 视图区由 OpenGL 负责渲染，本模块只做粘贴后的 2D 叠加（车道线、自车轮廓）与
  边框/文字；GL 不可用时在这里画 `OPENGL_UNAVAILABLE` 占位，**不做 CPU 3D 光栅化**；
- 所有计数（drop/crc/seq_gap/mismatch/FPS）由 app 实测传入，绝不写死。
"""
from __future__ import annotations

from dataclasses import dataclass, field

import cv2
import numpy as np

from dashboard.avm3d.calib.loader import Calibration
from dashboard.avm3d.config import (
    BOTTOM_RECT, CANVAS_H, CANVAS_W, INSET_RECT, LINK_RECT, PANEL_RECT,
    SYNC_RECT, VIEW_MODES, VIEW_RECT, normalize_mode,
)
from dashboard.avm3d.protocol_bridge import FrameBundle
from dashboard.avm3d.render.camera import VirtualCamera, project_lane_to_ground
from dashboard.vision.lane_types import TURN_ZH
from dashboard.avm3d.sources.base import VideoFrame
from dashboard.ui import text as ui_text

# ------------------------------------------------------------------ 调色板（BGR）
BG = (14, 11, 9)              # #090b0e
PANEL = (26, 22, 19)
PANEL_2 = (34, 29, 24)
LINE = (62, 54, 46)
TEXT = (234, 234, 236)
DIM = (152, 152, 158)
FAINT = (104, 104, 110)
AMBER = (60, 170, 245)        # RGB #f5aa3c 警告/来源
BLUE = (235, 150, 60)         # RGB #3c96eb 回放
GREEN = (110, 205, 120)
RED = (82, 82, 235)
CYAN = (220, 190, 70)
WHITE = (245, 245, 245)


@dataclass
class MatchInfo:
    """一次“视频帧 -> 同帧协议 bundle”的匹配结果；不携带任何邻帧数据。"""

    state: str = "NO_BUNDLE"          # MATCHED | FRAME_MISMATCH | NO_BUNDLE
    waited_ms: float = 0.0
    bundle: FrameBundle | None = None
    missing: tuple[str, ...] = ()
    neighbor: int | None = None


@dataclass
class FrameView:
    status: object                     # SourceStatus
    mode: int
    video: VideoFrame | None
    match: MatchInfo
    gl_available: bool
    gl_reason: str = ""
    gl_detail: str = ""
    gl_info: dict = field(default_factory=dict)
    fps: dict = field(default_factory=dict)          # render_fps/input_fps/matched_fps
    counters: dict = field(default_factory=dict)     # drop/crc_err/seq_gap/frame_mismatch_cnt…
    source_stats: dict = field(default_factory=dict)
    note: str = ""
    uptime_s: float = 0.0
    render_ms: float = 0.0
    single: bool = False


def _trunc(img: np.ndarray, text: str, x: int, y: int, width: int, size: int = 15,
           color: tuple[int, int, int] = TEXT, bold: bool = False) -> None:
    """超宽则截断加省略号。

    性能要点：动态值（帧号/FPS/偏移）每帧都是新字符串，Pillow 只能渲染一次并缓存。
    因此这里只做**一次**整串测量 + 一次截断测量，绝不做逐字符二分（那会每帧多渲染
    5 倍唯一字符串，30 fps 下直接吃掉 10 ms）。
    """
    if not text:
        return
    w, _ = ui_text.size_of(text, size, bold)
    if w <= width:
        ui_text.put(img, text, x, y, size=size, color=color, bold=bold)
        return
    keep = max(int(len(text) * width / max(w, 1)) - 1, 1)
    s = text[:keep].rstrip() + "…"
    ui_text.put(img, s, x, y, size=size, color=color, bold=bold)


def _box(img: np.ndarray, rect: tuple[int, int, int, int],
         fill: tuple[int, int, int] | None = None,
         border: tuple[int, int, int] | None = None, thickness: int = 1) -> None:
    x, y, w, h = rect
    if fill is not None:
        cv2.rectangle(img, (x, y), (x + w - 1, y + h - 1), fill, -1)
    if border is not None:
        cv2.rectangle(img, (x, y), (x + w - 1, y + h - 1), border, thickness)


def _section(img: np.ndarray, x: int, y: int, width: int, title: str) -> int:
    """画分组标题，返回下一行 y。"""
    cv2.line(img, (x, y - 8), (x + width, y - 8), LINE, 1)
    ui_text.put(img, title, x, y + 2, size=13, color=FAINT, bold=True)
    return y + 24


def _kv(img: np.ndarray, x: int, y: int, label: str, value: str,
        width: int = 392, ok: bool | None = None, value_size: int = 15) -> int:
    ui_text.put(img, label, x, y, size=13, color=DIM)
    col = TEXT if ok is None else (GREEN if ok else AMBER)
    _trunc(img, value, x + 116, y - 1, width - 116, size=value_size, color=col)
    return y + 21


def _source_color(label: str) -> tuple[int, int, int]:
    return {"SIM": AMBER, "REPLAY": BLUE, "LIVE": RED, "MIXED": (190, 120, 220)}.get(
        label.upper(), RED)


def _calib_tag(calib: Calibration) -> str:
    """显式 provenance 标签；未知/未声明时不显示，避免把 SIM 说成校准结果。"""
    prov = calib.provenance or {}
    explicit = str(prov.get("ui_tag", "")).strip()
    if explicit:
        return explicit
    source = str(prov.get("source", "")).upper()
    return "UNCALIBRATED" if "UNCALIBRATED" in source else ""


class OverlayRenderer:
    """静态底图只画一次；每帧 copy 后在动态区域作画。"""

    def __init__(self, calib: Calibration, spec, toggle_label: str = ""):
        self.calib = calib
        self.spec = spec
        self.toggle_label = toggle_label
        self.detect_camera = "front"     # sender 实际推理的通道（启动时定）
        self.view_camera = "front"       # 窗口当前查看的通道（可循环）
        self.layout_mode = "3d"          # 3d | single
        self.mode_button_rect: tuple[int, int, int, int] | None = None
        self.view_button_rect: tuple[int, int, int, int] | None = None
        self.channel_button_rect: tuple[int, int, int, int] | None = None
        self.layout_button_rect: tuple[int, int, int, int] | None = None
        self._bg = self._build_bg()

    def _check_camera(self, name: str) -> str:
        name = str(name).lower()
        if name not in self.calib.cameras:
            raise ValueError(f"未知相机通道 {name!r}，可用 {tuple(self.calib.cameras)}")
        return name

    def set_detect_camera(self, name: str) -> None:
        name = self._check_camera(name)
        self.detect_camera = name
        self.view_camera = name

    def set_view_camera(self, name: str) -> None:
        self.view_camera = self._check_camera(name)

    def cycle_view_camera(self) -> str:
        names = list(self.calib.camera_order) or ["front", "right", "rear", "left"]
        try:
            i = names.index(self.view_camera)
        except ValueError:
            i = -1
        self.view_camera = names[(i + 1) % len(names)]
        return self.view_camera

    # ---------------------------------------------------------------- 静态底图
    def _build_bg(self) -> np.ndarray:
        img = np.empty((CANVAS_H, CANVAS_W, 3), np.uint8)
        img[:] = BG
        # 顶部栏
        cv2.line(img, (0, 84), (CANVAS_W, 84), LINE, 1)
        cv2.line(img, (0, 729), (CANVAS_W, 729), LINE, 1)
        ui_text.put(img, "AVM 3D 环视扩展", 24, 16, size=25, color=WHITE, bold=True)
        ui_text.put(img, "PC 端 · 四路相机碗面投影 · 数据来自冻结协议字段", 25, 50,
                    size=13, color=FAINT)
        # 视频区 / 右侧面板 / 底部三块
        _box(img, VIEW_RECT, fill=(10, 10, 11), border=LINE)
        _box(img, PANEL_RECT, fill=PANEL, border=LINE)
        _box(img, INSET_RECT, fill=(10, 10, 11), border=LINE)
        _box(img, SYNC_RECT, fill=PANEL, border=LINE)
        _box(img, LINK_RECT, fill=PANEL, border=LINE)
        ui_text.put(img, "检测通道 · 2D 框（仅相机映射）", 30, 746, size=11, color=FAINT)
        ui_text.put(img, "同帧同步 / 计数", 344, 748, size=11, color=FAINT, bold=True)
        ui_text.put(img, "渲染与链路", 1114, 748, size=11, color=FAINT, bold=True)
        ui_text.put(img, "SIM / REPLAY 数据不是在线测量 · DEPTH 门禁关闭（无米制距离/TTC）"
                         " · 3D 视图只做相机纹理投影，不做目标 3D 摆放（G0-02）",
                    24, 884, size=10, color=FAINT)
        return img

    def canvas(self) -> np.ndarray:
        return self._bg.copy()

    # ---------------------------------------------------------------- 主入口
    def draw(self, view: FrameView, canvas: np.ndarray,
             camera: VirtualCamera | None = None, single: bool = False) -> np.ndarray:
        self.mode_button_rect = None
        self.view_button_rect = None
        self.channel_button_rect = None
        self.layout_button_rect = None
        self._top_bar(view, canvas)
        self._panel(view, canvas)
        self._sync_bar(view, canvas)
        self._link_box(view, canvas)
        if single:
            self._single_hint(view, canvas)
            self._single_lane(view, canvas)
            self._single_boxes(view, canvas)
            self._view_tag(view, canvas, None, single=True)
            return canvas
        self._inset(view, canvas)
        if view.gl_available:
            if camera is not None:
                self._annotations(view, canvas, camera)
            self._view_tag(view, canvas, camera)
        else:
            self._gl_placeholder(view, canvas)
        return canvas

    # ---------------------------------------------------------------- 顶部
    def _top_bar(self, view: FrameView, img: np.ndarray) -> None:
        status = view.status
        label = getattr(status, "label", "UNKNOWN")
        banner = status.banner()
        color = _source_color(label)
        w = 760
        _box(img, (532, 12, w, 58), fill=PANEL_2, border=color, thickness=2)
        ui_text.put(img, banner, 548, 20, size=22, color=color, bold=True)
        detail = getattr(status, "detail", "") or "—"
        _trunc(img, detail, 548, 49, w - 34, size=12, color=DIM)
        # 右侧：视图模式 + 所需字段
        # 右侧：视图模式 + 所需字段
        mode = normalize_mode(view.mode)
        name, desc, _types = VIEW_MODES[mode]
        ui_text.put(img, name, CANVAS_W - 24, 18, size=17, color=TEXT, bold=True, anchor="ra")
        ui_text.put(img, desc, CANVAS_W - 24, 42, size=12, color=FAINT, anchor="ra")
        ui_text.put(img, f"M{mode}  [1/2/3 切换]", CANVAS_W - 24, 58, size=11,
                    color=FAINT, anchor="ra")

    # ---------------------------------------------------------------- 右侧面板
    def _panel(self, view: FrameView, img: np.ndarray) -> None:
        x, y, w, h = PANEL_RECT
        x += 18
        y += 20
        width = w - 36
        status = view.status
        match = view.match
        bundle = match.bundle

        ui_text.put(img, "来源诚实性", x, y, size=15, color=AMBER, bold=True)
        y += 24
        y = _kv(img, x, y, "视频", str(getattr(status, "video_source", "UNKNOWN")), width)
        y = _kv(img, x, y, "协议", str(getattr(status, "data_source", "UNKNOWN")), width)
        if getattr(status, "mixed", False):
            y = _kv(img, x, y, "混合", "是（不是 LIVE）", width, ok=False)
        y = _kv(img, x, y, "通道",
                f"检测 {self.detect_camera.upper()} / 查看 {self.view_camera.upper()}",
                width, ok=(self.view_camera == self.detect_camera))
        lane = getattr(view.video, "lane", None) if view.video is not None else None
        if lane is not None:
            if lane.valid:
                txt = (f"{TURN_ZH.get(lane.turn, '不确定')} · "
                       f"{lane.offset_px:+.0f}px · a*w={lane.curvature_norm:+.2f}")
            else:
                txt = "unavailable"
            y = _kv(img, x, y, "PC 车道", txt, width,
                    ok=bool(lane.valid and lane.turn != "UNCERTAIN"))
        detail = getattr(status, "detail", "") or "—"
        for i, line in enumerate(_wrap(detail, 34)[:2]):
            ui_text.put(img, line, x, y + i * 17, size=11, color=FAINT)

        # ---- 同帧匹配
        y = _section(img, x, y + 42, width, "同帧匹配（严格 frame_id）")
        vid = view.video.frame_id if view.video is not None else None
        pid = bundle.frame_id if bundle is not None else None
        ok = match.state == "MATCHED"
        state_text = {
            "MATCHED": f"MATCHED · {match.waited_ms:.1f} ms",
            "FRAME_MISMATCH": f"FRAME_MISMATCH (邻帧 {match.neighbor})",
            "NO_BUNDLE": "NO_BUNDLE (同帧未到达)",
        }.get(match.state, match.state)
        y = _kv(img, x, y, "视频帧", f"#{vid}" if vid is not None else "—", width)
        y = _kv(img, x, y, "协议帧", f"#{pid}" if pid is not None else "—", width, ok=ok)
        y = _kv(img, x, y, "状态", state_text, width, ok=ok)
        if match.missing:
            y = _kv(img, x, y, "缺失字段", " / ".join(match.missing), width, ok=False)

        # ---- 车道
        y = _section(img, x, y + 6, width, "车道（LANE / LANE_TRACK）")
        y = self._lane_rows(img, x, y, width, bundle, view)

        # ---- 目标（Mode>=2）
        if "OBJECT" in VIEW_MODES[normalize_mode(view.mode)][2]:
            y = _section(img, x, y + 4, width, "目标（仅 2D 相机框）")
            y = self._object_rows(img, x, y, width, bundle)
        else:
            y = _section(img, x, y + 4, width, "目标")
            y = _kv(img, x, y, "Mode 1", "未启用（按 2 键显示 2D 框）", width)

        # ---- 运动/深度（Mode 3）
        if "MOTION" in VIEW_MODES[normalize_mode(view.mode)][2]:
            y = _section(img, x, y + 4, width, "运动 / 深度")
            y = self._motion_rows(img, x, y, width, bundle)
            y = self._depth_rows(img, x, y, width, bundle)
        else:
            y = _section(img, x, y + 4, width, "运动 / 深度")
            y = _kv(img, x, y, "Mode", "未启用（按 3 键显示状态）", width)

        # ---- 健康 / 耗时
        y = _section(img, x, min(y + 4, 700), width, "板端健康 / 耗时（同帧）")
        y = self._health_row(img, x, y, width, bundle)
        y = self._timing_row(img, x, y, width, bundle)

    def _lane_rows(self, img, x, y, width, bundle: FrameBundle | None,
                   view: FrameView) -> int:
        spec = self.spec
        rec = bundle.first("LANE") if bundle else None
        if rec is None:
            return _kv(img, x, y, "LANE", "NOT_PROVIDED", width, ok=False)
        status = rec.status_name(spec)
        if not rec.usable or rec.payload is None:
            return _kv(img, x, y, "LANE", f"{status} ({rec.reason_name(spec)})",
                       width, ok=False)
        p = rec.payload
        valid = int(p.get("lane_valid", 0)) == 1
        y = _kv(img, x, y, "有效", "lane_valid=1" if valid else "lane_valid=0",
                width, ok=valid)
        qb = spec.q_scale("Q16.16")
        qa = spec.q_scale("Q1.30")
        offset = float(p["center_offset_px"]) * qb
        lane_w = float(p["lane_width_px"]) * qb
        curv = float(p["curvature_px_inv"]) * qa
        conf = float(p["confidence_score"]) / 65535.0
        y = _kv(img, x, y, "偏移/宽度", f"{offset:+.1f} px / {lane_w:.1f} px", width)
        y = _kv(img, x, y, "曲率/置信", f"a={curv:+.2e} /px · {conf:.2f}", width)
        lt = bundle.first("LANE_TRACK")
        if lt is not None and lt.usable and lt.payload is not None:
            fo = float(lt.payload["filtered_offset_px"]) * qb
            st = spec.enum_name("lane_state", int(lt.payload["lane_state"]))
            y = _kv(img, x, y, "跟踪", f"{st} · filtered {fo:+.1f} px", width, ok=(st == "TRACKING"))
        else:
            y = _kv(img, x, y, "跟踪", "NOT_PROVIDED", width, ok=False)
        return y

    def _object_rows(self, img, x, y, width, bundle: FrameBundle | None) -> int:
        spec = self.spec
        obj = bundle.first("OBJECT") if bundle else None
        if obj is None:
            y = _kv(img, x, y, "OBJECT", "NOT_PROVIDED", width, ok=False)
        elif not obj.usable or obj.payload is None:
            y = _kv(img, x, y, "OBJECT", f"{obj.status_name(spec)} ({obj.reason_name(spec)})",
                    width, ok=False)
        else:
            objs = obj.payload.get("objects") or []
            classes = sorted({int(o.get("class_id", -1)) for o in objs})
            y = _kv(img, x, y, "OBJECT", f"{len(objs)} 个框 · class {classes or '—'}",
                    width, ok=bool(objs))
            ds = sorted({int(o.get("distance_status", 1)) for o in objs})
            dist_label = " / ".join(self.spec.enum_name("distance_status", d) for d in ds) or "—"
            dist_ok = ds == [1] or not objs
            y = _kv(img, x, y, "距离", f"{dist_label}（不显示米制）", width, ok=dist_ok)
        tr = bundle.first("TRACK_V1") if bundle else None
        if tr is None:
            y = _kv(img, x, y, "TRACK_V1", "NOT_PROVIDED", width, ok=False)
        elif not tr.usable or tr.payload is None:
            y = _kv(img, x, y, "TRACK_V1", f"{tr.status_name(spec)} ({tr.reason_name(spec)})",
                    width, ok=False)
        else:
            tracks = tr.payload.get("tracks") or []
            rel = "—"
            if tracks:
                rel = spec.enum_name("roi_relation", int(tracks[0].get("roi_relation", 0)))
            y = _kv(img, x, y, "TRACK_V1", f"{len(tracks)} 条 · {rel}", width, ok=bool(tracks))
        ui_text.put(img, "G0-02：OBJECT 无相机通道映射，只画 2D 框", x, y, size=10,
                    color=FAINT)
        return y + 18

    def _motion_rows(self, img, x, y, width, bundle: FrameBundle | None) -> int:
        spec = self.spec
        rec = bundle.first("MOTION") if bundle else None
        if rec is None:
            return _kv(img, x, y, "MOTION", "NOT_PROVIDED", width, ok=False)
        if not rec.usable or rec.payload is None:
            return _kv(img, x, y, "MOTION", f"{rec.status_name(spec)} ({rec.reason_name(spec)})",
                       width, ok=False)
        p = rec.payload
        q16 = 65535.0
        roi = float(p["roi_motion_ratio"]) / q16
        near = float(p["near_motion_ratio"]) / q16
        far = float(p["far_motion_ratio"]) / q16
        low = float(p["low_texture_ratio"]) / q16
        y = _kv(img, x, y, "运动占比", f"ROI {roi:.1%} · 近 {near:.1%} · 远 {far:.1%}", width)
        y = _kv(img, x, y, "低纹理", f"{low:.1%}", width, ok=low < 0.5)
        return y

    def _depth_rows(self, img, x, y, width, bundle: FrameBundle | None) -> int:
        spec = self.spec
        rec = bundle.first("DEPTH") if bundle else None
        if rec is None:
            return _kv(img, x, y, "DEPTH", "NOT_PROVIDED", width, ok=False)
        st = rec.status_name(spec)
        rs = rec.reason_name(spec)
        ok = st == "OK"
        y = _kv(img, x, y, "DEPTH", f"{st} ({rs})", width, ok=ok)
        y = _kv(img, x, y, "门禁", "DEPTH_BRANCH_DISABLED · 无米制距离/TTC", width, ok=False)
        return y

    def _health_row(self, img, x, y, width, bundle: FrameBundle | None) -> int:
        if bundle is None:
            return _kv(img, x, y, "HEALTH", "NOT_PROVIDED", width, ok=False)
        recs = bundle.all("HEALTH")
        if not recs:
            return _kv(img, x, y, "HEALTH", "—（1 Hz 心跳，本帧无）", width)
        parts = []
        for r in recs:
            if not r.usable:
                parts.append(f"{self._source_name(r)} {r.status_name(self.spec)}")
            else:
                parts.append(f"{self._source_name(r)} OK")
        return _kv(img, x, y, "HEALTH", " · ".join(parts), width,
                   ok=all(r.usable for r in recs))

    def _timing_row(self, img, x, y, width, bundle: FrameBundle | None) -> int:
        if bundle is None:
            return _kv(img, x, y, "TIMING", "NOT_PROVIDED", width, ok=False)
        recs = [r for r in bundle.all("TIMING") if r.usable and r.payload]
        if not recs:
            return _kv(img, x, y, "TIMING", "NOT_PROVIDED", width, ok=False)
        p95 = max(float(r.payload.get("p95_us", 0)) for r in recs) / 1000.0
        p50 = max(float(r.payload.get("p50_us", 0)) for r in recs) / 1000.0
        return _kv(img, x, y, "耗时 p50/p95", f"{p50:.1f} / {p95:.1f} ms", width,
                   value_size=13)

    def _source_name(self, rec) -> str:
        return self.spec.enum_name("source_id", int(rec.header["source_id"]))

    # ---------------------------------------------------------------- 单路模式
    def _single_hint(self, view: FrameView, img: np.ndarray) -> None:
        x, y, w, h = INSET_RECT
        cv2.rectangle(img, (x + 6, y + 18), (x + w - 7, y + h - 7), (10, 10, 11), -1)
        ui_text.put(img, "SINGLE 2D", x + 16, y + 28, size=15, color=CYAN, bold=True)
        _trunc(img, "仅显示一路检测画面；不渲染 3D 碗面", x + 16, y + 50, w - 32,
               size=11, color=DIM)
        _trunc(img, f"检测: {self.detect_camera.upper()} · 查看: {self.view_camera.upper()}"
                    f" · C 换查看 / V 回 3D",
               x + 16, y + 70, w - 32, size=11, color=AMBER)

    def _lane_overlay(self, view: FrameView, img: np.ndarray,
                      rect: tuple[int, int, int, int], camera_name: str,
                      label: bool = True) -> bool:
        """在指定矩形上画前向车道中心线；只画 lane.camera 对应的画幅。"""
        rx, ry, rw, rh = rect
        lane = getattr(view.video, "lane", None) if view.video is not None else None
        if lane is None or lane.camera != camera_name:
            return False
        cam = self.calib.cameras[camera_name]
        sx, sy = rw / cam.width, rh / cam.height
        if not (lane.valid and len(lane.points) >= 2):
            if label:
                ui_text.put(img, "PC 车道: unavailable", rx + 14, ry + 66,
                            size=11, color=AMBER)
            return False
        us = np.array([p[0] for p in lane.points], dtype=np.float64)
        vs = np.array([p[1] for p in lane.points], dtype=np.float64)
        pts = np.array([(rx + u * sx, ry + v * sy) for u, v in zip(us, vs)],
                       dtype=np.int32)
        cv2.polylines(img, [pts], False, CYAN, 3, cv2.LINE_AA)
        for p in (pts[0], pts[-1]):
            cv2.circle(img, tuple(int(x) for x in p), 4, CYAN, -1, cv2.LINE_AA)
        # 近场 7 点只在画面底部 ~50px；用拟合曲线向远端画虚线外推，并明确标注。
        if len(lane.points) >= 4:
            try:
                abc = np.polyfit(vs, us, 2)
                v_far = float(vs.min())
                v_look = max(0.42 * cam.height, v_far - 0.55 * cam.height)
                if v_look < v_far:
                    v_ext = np.linspace(v_far, v_look, 22)
                    u_ext = np.polyval(abc, v_ext)
                    prev = None
                    for i, (u, v) in enumerate(zip(u_ext, v_ext)):
                        cur = (int(rx + float(u) * sx), int(ry + float(v) * sy))
                        if prev is not None and i % 2 == 1:
                            cv2.line(img, prev, cur, CYAN, 1, cv2.LINE_AA)
                        prev = cur
                    if label:
                        end = (int(rx + float(u_ext[-1]) * sx),
                               int(ry + float(v_ext[-1]) * sy))
                        ui_text.put(img, "外推", end[0] + 4, end[1], size=10,
                                    color=AMBER)
            except Exception:
                pass
        if label:
            ui_text.put(img, "PC 车道中心线（实线近场 / 虚线外推）",
                        rx + 14, ry + 66, size=11, color=CYAN)
        return True

    def _single_lane(self, view: FrameView, img: np.ndarray) -> None:
        """PC 本地车道中心线 + 道路弯向；不是驾驶员转向/控制指令。"""
        rx, ry, rw, rh = VIEW_RECT
        lane = getattr(view.video, "lane", None) if view.video is not None else None
        if lane is None:
            ui_text.put(img, "PC 车道: unavailable", rx + 14, ry + 66,
                        size=11, color=AMBER)
            return
        if lane.camera != self.view_camera:
            ui_text.put(img, "PC 车道: 通道不匹配，已隐藏", rx + 14, ry + 66,
                        size=11, color=AMBER)
            return
        self._lane_overlay(view, img, VIEW_RECT, self.view_camera, label=True)
        state = TURN_ZH.get(lane.turn, "不确定")
        color = GREEN if lane.turn == "STRAIGHT" else (
            AMBER if lane.turn == "UNCERTAIN" else CYAN)
        bw, bh = 330, 42
        bx, by = rx + rw - bw - 12, ry + rh - bh - 12
        _box(img, (bx, by, bw, bh), fill=(18, 16, 14), border=color, thickness=1)
        curv = ("—" if lane.curvature_norm is None
                else f"{lane.curvature_norm:+.2f}")
        ui_text.put(img, f"道路弯向: {state}  a*w={curv}", bx + 10, by + 6,
                    size=13, color=color, bold=True)
        ui_text.put(img, "PC 图像估计 · 非驾驶转向/无轮速IMU", bx + 10, by + 24,
                    size=10, color=FAINT)

    def _single_boxes(self, view: FrameView, img: np.ndarray) -> None:
        rx, ry, rw, rh = VIEW_RECT
        cam = self.calib.cameras[self.view_camera]
        sx, sy = rw / cam.width, rh / cam.height
        bundle = view.match.bundle
        mismatch = self.view_camera != self.detect_camera
        if mismatch:
            ui_text.put(img, f"检测 {self.detect_camera.upper()} ≠ 查看 "
                             f"{self.view_camera.upper()} · 框已隐藏",
                        rx + 14, ry + rh - 18, size=12, color=AMBER)
            _box(img, (rx + 8, ry + 40, 300, 22), fill=(18, 16, 14),
                 border=AMBER, thickness=1)
            ui_text.put(img, f"VIEW {cam.name.upper()} · 检测 {self.detect_camera.upper()}",
                        rx + 14, ry + 44, size=12, color=AMBER, bold=True)
            return
        drew = False
        if "OBJECT" in VIEW_MODES[normalize_mode(view.mode)][2] and bundle is not None:
            rec = bundle.first("OBJECT")
            if rec is not None and rec.usable and rec.payload is not None:
                for o in rec.payload.get("objects") or []:
                    b = o.get("bbox_xyxy") or [0, 0, 0, 0]
                    x0, y0 = rx + int(b[0] * sx), ry + int(b[1] * sy)
                    x1, y1 = rx + int(b[2] * sx), ry + int(b[3] * sy)
                    cv2.rectangle(img, (x0, y0), (x1, y1), GREEN, 2)
                    ui_text.put(img, f"c{int(o.get('class_id', 0))}", x0 + 2,
                                max(y0 - 15, ry + 2), size=11, color=GREEN)
                    drew = True
                tr = bundle.first("TRACK_V1")
                if tr is not None and tr.usable and tr.payload is not None:
                    for t in (tr.payload.get("tracks") or [])[:8]:
                        b = t.get("bbox_xyxy") or [0, 0, 0, 0]
                        x0, y0 = rx + int(b[0] * sx), ry + int(b[1] * sy)
                        x1, y1 = rx + int(b[2] * sx), ry + int(b[3] * sy)
                        ui_text.put(img, f"#{int(t.get('track_id', 0))}", max(x0 + 2, rx + 2),
                                    min(y1 + 2, ry + rh - 14), size=10, color=CYAN)
                        drew = True
        if not drew:
            reason = "NO SAME-FRAME BOXES" if view.match.state != "MATCHED" else "OBJECT NOT_PROVIDED"
            ui_text.put(img, reason, rx + 14, ry + rh - 18, size=12, color=AMBER)
        _box(img, (rx + 8, ry + 40, 280, 22), fill=(18, 16, 14), border=CYAN, thickness=1)
        ui_text.put(img, f"DETECT {self.detect_camera.upper()} · 查看 {cam.name.upper()}",
                    rx + 14, ry + 44, size=12, color=CYAN, bold=True)

    # ---------------------------------------------------------------- 底部：围视
    def _inset(self, view: FrameView, img: np.ndarray) -> None:
        x, y, w, h = INSET_RECT
        ix, iy, iw, ih = x + 6, y + 18, w - 12, h - 24
        video = view.video
        if video is None:
            ui_text.put(img, "NO_VIDEO", ix + iw // 2, iy + ih // 2, size=16, color=RED,
                        anchor="cm")
            return
        cam = self.calib.cameras[self.view_camera]
        cell = video.cell(cam.cell, self.calib.cell_area)
        scaled = cv2.resize(cell, (iw, ih), interpolation=cv2.INTER_AREA)
        img[iy:iy + ih, ix:ix + iw] = scaled
        ui_text.put(img, cam.name.upper(), ix + iw - 3, iy + 2, size=10,
                    color=AMBER, anchor="ra")
        if self.view_camera != self.detect_camera:
            ui_text.put(img, f"检测 {self.detect_camera.upper()} ≠ 查看 "
                             f"{self.view_camera.upper()} · 框已隐藏",
                        ix + 4, iy + ih - 16, size=10, color=AMBER)
            return
        # 同帧 OBJECT/TRACK 2D 框（只在 Mode>=2 且同帧 bundle 可用时）
        if "OBJECT" in VIEW_MODES[normalize_mode(view.mode)][2] and view.match.bundle:
            sx, sy = iw / cam.width, ih / cam.height
            spec = self.spec
            rec = view.match.bundle.first("OBJECT")
            if rec is not None and rec.usable and rec.payload is not None:
                for o in rec.payload.get("objects") or []:
                    b = o.get("bbox_xyxy") or [0, 0, 0, 0]
                    x0, y0, x1, y1 = (int(b[0] * sx) + ix, int(b[1] * sy) + iy,
                                      int(b[2] * sx) + ix, int(b[3] * sy) + iy)
                    cv2.rectangle(img, (x0, y0), (x1, y1), GREEN, 1)
                    cls_id = int(o.get("class_id", 0))
                    ui_text.put(img, f"c{cls_id}", x0 + 2, max(y0 - 14, iy + 1),
                                size=10, color=GREEN)
            tr = view.match.bundle.first("TRACK_V1")
            if tr is not None and tr.usable and tr.payload is not None:
                for t in (tr.payload.get("tracks") or [])[:4]:
                    b = t.get("bbox_xyxy") or [0, 0, 0, 0]
                    x0, y0, x1, y1 = (int(b[0] * sx) + ix, int(b[1] * sy) + iy,
                                      int(b[2] * sx) + ix, int(b[3] * sy) + iy)
                    ui_text.put(img, f"#{int(t.get('track_id', 0))}", max(x0 + 2, ix + 1),
                                min(y1 + 2, iy + ih - 14), size=9, color=CYAN)
        elif view.match.state != "MATCHED":
            ui_text.put(img, "NO SAME-FRAME BOXES", ix + 6, iy + ih - 16, size=11,
                        color=AMBER)
        if self.view_camera == "front":
            self._lane_overlay(view, img, (ix, iy, iw, ih), "front", label=False)

    # ---------------------------------------------------------------- 底部：同步
    def _sync_bar(self, view: FrameView, img: np.ndarray) -> None:
        x, y, w, h = SYNC_RECT
        x += 16
        y += 22
        match = view.match
        video = view.video
        vid = video.frame_id if video is not None else None
        pid = match.bundle.frame_id if match.bundle is not None else None
        col = GREEN if match.state == "MATCHED" else (AMBER if match.state == "FRAME_MISMATCH" else RED)
        _trunc(img, f"video #{vid}   proto #{pid}   {match.state}   wait {match.waited_ms:.1f} ms",
               x, y, w - 32, size=19, color=col, bold=True)
        c = view.counters
        matched = c.get("matched", 0)
        total = max(c.get("frames", 0), 1)
        line2 = (f"matched {matched}/{total} ({matched / total:.1%}) · "
                 f"mismatch {c.get('frame_mismatch_cnt', 0)} · "
                 f"drop {c.get('drop', 0)} · crc_err {c.get('crc_err', 0)} · "
                 f"seq_gap {c.get('seq_gap', 0)}")
        ui_text.put(img, line2, x, y + 26, size=14, color=TEXT)
        line3 = (f"input {view.fps.get('input_fps', 0):.1f} fps · "
                 f"matched {view.fps.get('matched_fps', 0):.1f} fps · "
                 f"render {view.fps.get('render_fps', 0):.1f} fps · "
                 f"queue drop {c.get('queue_put_drops', 0)} / stale {c.get('queue_stale_skipped', 0)}")
        ui_text.put(img, line3, x, y + 47, size=12, color=DIM)

    # ---------------------------------------------------------------- 底部：链路
    def _link_box(self, view: FrameView, img: np.ndarray) -> None:
        x, y, w, h = LINK_RECT
        x += 14
        y += 22
        width = w - 28
        gl = "SINGLE 2D" if view.single else (
            "GL OK" if view.gl_available else f"GL {view.gl_reason or 'UNAVAILABLE'}")
        gl_col = CYAN if view.single else (GREEN if view.gl_available else RED)
        ui_text.put(img, gl, x, y, size=13, color=gl_col, bold=True)
        info = view.gl_info or {}
        if view.gl_available and not view.single and info.get("renderer"):
            _trunc(img, f"{info.get('renderer', '')} · {info.get('version', '')}",
                   x + 120, y, width - 120, size=11, color=DIM)
        if view.single:
            _trunc(img, f"检测 {self.detect_camera.upper()} / 查看 {self.view_camera.upper()}"
                        f" · V 切回 3D", x + 110, y, width - 110, size=11, color=DIM)
        c = view.counters
        stats = view.source_stats
        lines = [
            f"frames in {stats.get('frames_produced', 0)} · rendered {c.get('rendered', 0)} · uptime {view.uptime_s:.0f}s",
            f"protocol msgs {stats.get('protocol_msgs', 0)} · store cached {c.get('cached_frames', 0)} · evicted {c.get('evicted', 0)}",
            f"source fatal: {stats.get('fatal') or '无'}",
        ]
        for i, line in enumerate(lines):
            _trunc(img, line, x, y + 22 + i * 19, width, size=12, color=DIM)
        if view.note:
            _trunc(img, view.note, x, y + 22 + len(lines) * 19, width, size=11, color=AMBER)

    # ---------------------------------------------------------------- 3D 标注
    def _annotations(self, view: FrameView, img: np.ndarray,
                     camera: VirtualCamera) -> None:
        """在已经粘贴好的 GL 视图上画车道线与自车轮廓（CPU 只投影几十个点）。"""
        rx, ry, rw, rh = VIEW_RECT
        bundle = view.match.bundle
        if bundle is not None and "LANE" in VIEW_MODES[normalize_mode(view.mode)][2]:
            rec = bundle.first("LANE")
            if rec is not None and rec.usable and rec.payload is not None:
                pts, _valid, reason = project_lane_to_ground(
                    self.calib, rec.payload, self.spec, samples=48)
                if reason == "NONE" and len(pts) >= 4:
                    uv, ok = camera.project_points(pts, rw, rh)
                    sel = uv[ok]
                    if len(sel) >= 4:
                        poly = np.round(sel + (rx, ry)).astype(np.int32)
                        cv2.polylines(img, [poly], False, CYAN, 2, cv2.LINE_AA)
                        ui_text.put(img, "LANE 3D（协议中心线反投影）", rx + 12, ry + rh - 14,
                                    size=11, color=CYAN, anchor="lb")
                elif reason not in ("NONE", "LANE_LOST"):
                    ui_text.put(img, f"LANE: {reason}", rx + 12, ry + 22, size=11,
                                color=AMBER)
            else:
                ui_text.put(img, "LANE: NOT_PROVIDED（不跨帧补线）", rx + 12, ry + 22,
                            size=11, color=AMBER)
        # 自车轮廓（不是测量值；尺寸来自标定车辆参数）
        veh = self.calib.vehicle
        half_l = max(float(getattr(veh, "length_m", 4.6)) / 2.0, 0.5)
        half_w = max(float(getattr(veh, "width_m", 1.86)) / 2.0, 0.5)
        corners = np.array([
            [half_l, -half_w, 0.02], [half_l, half_w, 0.02],
            [-half_l, half_w, 0.02], [-half_l, -half_w, 0.02],
        ])
        uv, ok = camera.project_points(corners, rw, rh)
        if ok.all():
            poly = np.round(uv + (rx, ry)).astype(np.int32)
            cv2.fillPoly(img, [poly], (32, 34, 36), cv2.LINE_AA)
            cv2.polylines(img, [poly], True, WHITE, 2, cv2.LINE_AA)
            ui_text.put(img, "EGO", int(poly[:, 0].mean()) - 12,
                        int(poly[:, 1].min()) - 6, size=10, color=WHITE)

    def _view_tag(self, view: FrameView, img: np.ndarray,
                  camera: VirtualCamera | None = None, single: bool = False) -> None:
        """视频区左上角的来源水印；不遮挡数据。"""
        rx, ry, rw, rh = VIEW_RECT
        label = str(getattr(view.status, "label", "UNKNOWN"))
        col = _source_color(label)
        w = 12 + 8 * len(label)
        _box(img, (rx + 8, ry + 8, w, 26), fill=(18, 16, 14),
             border=col, thickness=1)
        ui_text.put(img, label, rx + 14, ry + 12, size=13, color=col, bold=True)
        tag = _calib_tag(self.calib)
        bx = rx + 8 + w + 8
        if tag:
            tx = bx
            tw = 16 + 11 * len(tag)
            _box(img, (tx, ry + 8, tw, 26), fill=(38, 24, 10),
                 border=AMBER, thickness=1)
            ui_text.put(img, tag, tx + 7, ry + 12, size=13, color=AMBER, bold=True)
            bx = tx + tw + 8
        by = ry + 8

        def add_button(label: str, rect_attr: str) -> None:
            nonlocal bx, by
            bw = max(120, int(ui_text.size_of(label, 13, True)[0]) + 16)
            bh = 26
            if bx + bw > rx + rw - 8:
                bx = rx + 8
                by = ry + 40
            _box(img, (bx, by, bw, bh), fill=(18, 16, 14),
                 border=CYAN, thickness=1)
            ui_text.put(img, label, bx + 8, by + 4, size=13, color=CYAN, bold=True)
            setattr(self, rect_attr, (bx, by, bw, bh))
            bx += bw + 8

        if not single and self.toggle_label:
            add_button(self.toggle_label, "mode_button_rect")
        if not single and camera is not None:
            view_label = "视角: 俯瞰" if camera.view_name == "front" else "视角: 碗口"
            add_button(view_label, "view_button_rect")
        add_button(f"查看: {self.view_camera.upper()}", "channel_button_rect")
        add_button("模式: 单路" if self.layout_mode == "single" else "模式: 3D",
                   "layout_button_rect")
        note = str((self.calib.provenance or {}).get("coverage_note", "")).strip()
        if note:
            ny = ry + rh - 34
            cv2.rectangle(img, (rx + 8, ny), (rx + rw - 8, ny + 17), BG, -1)
            _trunc(img, note, rx + 12, ny + 2, rw - 24, size=10, color=AMBER)
        if view.mode == 3:
            ui_text.put(img, "深度：门禁关闭（无米制距离）", rx + rw - 14, ry + rh - 12,
                        size=11, color=AMBER, anchor="rb")

    # ---------------------------------------------------------------- GL 不可用
    def _gl_placeholder(self, view: FrameView, img: np.ndarray) -> None:
        rx, ry, rw, rh = VIEW_RECT
        cv2.rectangle(img, (rx, ry), (rx + rw - 1, ry + rh - 1), (10, 10, 11), -1)
        code = view.gl_reason or "OPENGL_UNAVAILABLE"
        ui_text.put(img, code, rx + rw // 2, ry + rh // 2 - 40, size=30, color=RED,
                    bold=True, anchor="cm")
        ui_text.put(img, "3D 视图不可用：2D Dashboard 不受影响，没有 CPU 点云回退",
                    rx + rw // 2, ry + rh // 2 + 2, size=15, color=TEXT, anchor="cm")
        detail = view.gl_detail or "需要 OpenGL 3.3 core + PyOpenGL + glfw"
        _trunc(img, detail, rx + 60, ry + rh // 2 + 30, rw - 120, size=12, color=DIM)
        ui_text.put(img, "（本程序不做 CPU 3D 光栅化；请检查显卡驱动/依赖）",
                    rx + rw // 2, ry + rh // 2 + 58, size=12, color=FAINT, anchor="cm")


def _wrap(text: str, width: int) -> list[str]:
    """按字符宽度粗略换行（CJK 一字算一格）。"""
    out: list[str] = []
    cur = ""
    for ch in text:
        if len(cur) >= width:
            out.append(cur)
            cur = ""
        cur += ch
    if cur:
        out.append(cur)
    return out
