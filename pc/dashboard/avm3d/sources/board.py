"""板端视频源：2x2 atlas（采集卡/文件）+ AVM1 帧表 + 协议元数据。

这不是 LIVE 的“自动放行”：只有配置 verified、四格 source_map 全 live、
帧表与元数据都在线且当前帧 `frame_id` 可验证时，状态才变成 `LIVE`；
否则标签保持 `BOARD` 并带原因码。没有帧表时 frame_id 由本地序号生成，
状态里明确写 `UNSYNCED`，不冒充同帧。

用法（见 data/board/board_config.example.json）::

    --source board --board-config dashboard/avm3d/data/board/board_config.example.json

`video.kind` 支持 `file`（离线/演示）与 `capture`（HDMI 采集卡）。
"""
from __future__ import annotations

import json
import math
import socket
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path

import cv2
import numpy as np

from dashboard.avm3d.calib.loader import Calibration
from dashboard.avm3d.protocol_bridge import AvmProtocolStore
from dashboard.avm3d.sources.base import SourceBase, SourceError, SourceStatus, VideoFrame
from dashboard.avm3d.sources.frametable import (
    CELL_NAMES, CELL_STATES, FrameTable, FrameTableEntry,
)
from dashboard.avm3d.sources.udp import UdpDatagramReceiver

BOARD_FORMAT = "avm3d_board_v1"
VIDEO_KINDS = ("file", "capture")
TABLE_MODES = ("udp", "none")


@dataclass(frozen=True)
class VideoConfig:
    kind: str
    path: Path | None
    device: int
    fps: float
    loop: bool
    start_frame_id: int
    width: int
    height: int
    layout: str = "atlas"          # atlas | single
    sync_to_detections: bool = False
    detect_wait_ms: float = 500.0
    quad_paths: tuple[Path, ...] | None = None
    start_delay_ms: float = 0.0


@dataclass(frozen=True)
class AtlasConfig:
    width: int
    height: int
    cell_order: tuple[str, str, str, str]


@dataclass(frozen=True)
class FrameTableConfig:
    mode: str
    port: int
    tolerance_ms: float


@dataclass(frozen=True)
class BoardConfig:
    path: Path
    verified: bool
    video: VideoConfig
    atlas: AtlasConfig
    calibration_id: int
    source_map: dict[str, str]
    frame_table: FrameTableConfig
    metadata_udp_port: int
    notes: str
    control_host: str = ""
    control_start_port: int = 0
    raw: dict = field(default_factory=dict)


def _need(raw: dict, key: str) -> object:
    if key not in raw:
        raise SourceError("BOARD_CONFIG_INVALID", f"缺少字段 {key}")
    return raw[key]


def _int(value, name: str, lo: int, hi: int) -> int:
    try:
        out = int(value)
    except (TypeError, ValueError) as exc:
        raise SourceError("BOARD_CONFIG_INVALID", f"{name} 不是整数：{value!r}") from exc
    if not (lo <= out <= hi):
        raise SourceError("BOARD_CONFIG_INVALID", f"{name}={out} 超出 [{lo},{hi}]")
    return out


def _num(value, name: str, lo: float, hi: float) -> float:
    try:
        out = float(value)
    except (TypeError, ValueError) as exc:
        raise SourceError("BOARD_CONFIG_INVALID", f"{name} 不是数字：{value!r}") from exc
    if not math.isfinite(out) or not (lo <= out <= hi):
        raise SourceError("BOARD_CONFIG_INVALID", f"{name}={out} 超出 [{lo},{hi}]")
    return out


def load_board_config(path: str | Path) -> BoardConfig:
    """读板端配置；结构性错误一律 `BOARD_CONFIG_INVALID`（带字段名）。"""
    p = Path(path).resolve()
    if not p.exists():
        raise SourceError("BOARD_CONFIG_MISSING", f"配置不存在：{p}")
    try:
        raw = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SourceError("BOARD_CONFIG_INVALID", f"{p.name}: {exc}") from exc
    if not isinstance(raw, dict):
        raise SourceError("BOARD_CONFIG_INVALID", "顶层必须是 JSON object")
    schema = str(raw.get("schema", ""))
    if schema != BOARD_FORMAT:
        raise SourceError("BOARD_CONFIG_INVALID",
                          f"schema={schema!r} != {BOARD_FORMAT!r}")

    video_raw = _need(raw, "video")
    if not isinstance(video_raw, dict):
        raise SourceError("BOARD_CONFIG_INVALID", "video 必须是 object")
    kind = str(video_raw.get("kind", "file")).lower()
    if kind not in VIDEO_KINDS:
        raise SourceError("BOARD_CONFIG_INVALID", f"video.kind={kind!r}，支持 {VIDEO_KINDS}")
    layout = str(video_raw.get("layout", "atlas")).lower()
    if layout not in ("atlas", "single"):
        raise SourceError("BOARD_CONFIG_INVALID",
                          f"video.layout={layout!r}，支持 atlas/single")
    video_path = None
    quad_paths = None
    quad_raw = video_raw.get("quad_paths")
    if quad_raw is not None:
        if kind != "file":
            raise SourceError("BOARD_CONFIG_INVALID", "video.quad_paths 只支持 kind=file")
        if layout != "atlas":
            raise SourceError("BOARD_CONFIG_INVALID",
                              "video.quad_paths 需要 layout=atlas")
        if not isinstance(quad_raw, dict):
            raise SourceError("BOARD_CONFIG_INVALID", "video.quad_paths 必须是 object")
        qmap = {str(k).lower(): v for k, v in quad_raw.items()}
        if set(qmap) != set(CELL_NAMES):
            raise SourceError(
                "BOARD_CONFIG_INVALID",
                f"video.quad_paths 必须恰好包含 {CELL_NAMES}，实际 {sorted(qmap)}")
        qp = []
        for name in CELL_NAMES:
            vp = qmap.get(name)
            if not vp:
                raise SourceError("BOARD_CONFIG_INVALID",
                                  f"video.quad_paths.{name} 不能为空")
            q = Path(str(vp))
            if not q.is_absolute():
                q = (p.parent / q).resolve()
            if not q.exists():
                raise SourceError("BOARD_VIDEO_UNAVAILABLE", f"视频不存在：{q}")
            qp.append(q)
        quad_paths = tuple(qp)
        video_path = quad_paths[0]
    elif kind == "file":
        vp = video_raw.get("path")
        if not vp:
            raise SourceError("BOARD_CONFIG_INVALID", "video.kind=file 需要 video.path")
        video_path = Path(str(vp))
        if not video_path.is_absolute():
            video_path = (p.parent / video_path).resolve()
        if not video_path.exists():
            raise SourceError("BOARD_VIDEO_UNAVAILABLE", f"视频不存在：{video_path}")
    video = VideoConfig(
        kind=kind, path=video_path,
        device=_int(video_raw.get("device", 0), "video.device", 0, 64),
        fps=_num(video_raw.get("fps", 20.0), "video.fps", 1.0, 120.0),
        loop=bool(video_raw.get("loop", False)),
        start_frame_id=_int(video_raw.get("start_frame_id", 0),
                             "video.start_frame_id", 0, 0xFFFFFFFF),
        width=_int(video_raw.get("width", 0), "video.width", 0, 8192),
        height=_int(video_raw.get("height", 0), "video.height", 0, 8192),
        layout=layout,
        sync_to_detections=bool(video_raw.get("sync_to_detections", False)),
        detect_wait_ms=_num(video_raw.get("detect_wait_ms", 500.0),
                            "video.detect_wait_ms", 0.0, 10000.0),
        quad_paths=quad_paths,
        start_delay_ms=_num(video_raw.get("start_delay_ms", 0.0),
                            "video.start_delay_ms", 0.0, 10000.0),
    )

    atlas_raw = _need(raw, "atlas")
    if not isinstance(atlas_raw, dict):
        raise SourceError("BOARD_CONFIG_INVALID", "atlas 必须是 object")
    width = _int(_need(atlas_raw, "width"), "atlas.width", 2, 8192)
    height = _int(_need(atlas_raw, "height"), "atlas.height", 2, 8192)
    order_raw = atlas_raw.get("cell_order", list(CELL_NAMES))
    if not isinstance(order_raw, list) or len(order_raw) != 4:
        raise SourceError("BOARD_CONFIG_INVALID", "atlas.cell_order 必须是 4 个名字")
    order = tuple(str(n).lower() for n in order_raw)
    if set(order) != set(CELL_NAMES):
        raise SourceError("BOARD_CONFIG_INVALID",
                          f"atlas.cell_order={order}，必须包含 {CELL_NAMES}")
    atlas = AtlasConfig(width=width, height=height, cell_order=order)  # type: ignore[arg-type]

    calibration_id = _int(raw.get("calibration_id", 0),
                          "calibration_id", 0, 0xFFFF)
    source_map_raw = raw.get("source_map") or {}
    if not isinstance(source_map_raw, dict):
        raise SourceError("BOARD_CONFIG_INVALID", "source_map 必须是 object")
    source_map: dict[str, str] = {}
    for name, state in source_map_raw.items():
        key = str(name).lower()
        value = str(state).lower()
        if key not in CELL_NAMES:
            raise SourceError("BOARD_CONFIG_INVALID", f"source_map 未知相机 {name!r}")
        if value not in {s.lower() for s in CELL_STATES}:
            raise SourceError("BOARD_CONFIG_INVALID",
                              f"source_map[{key}]={value!r}，支持 {CELL_STATES}")
        source_map[key] = value

    ft_raw = raw.get("frame_table") or {}
    if not isinstance(ft_raw, dict):
        raise SourceError("BOARD_CONFIG_INVALID", "frame_table 必须是 object")
    mode = str(ft_raw.get("mode", "none")).lower()
    if mode not in TABLE_MODES:
        raise SourceError("BOARD_CONFIG_INVALID",
                          f"frame_table.mode={mode!r}，支持 {TABLE_MODES}")
    frame_table = FrameTableConfig(
        mode=mode,
        port=_int(ft_raw.get("port", 0), "frame_table.port", 0, 0xFFFF),
        tolerance_ms=_num(ft_raw.get("tolerance_ms", 30.0),
                          "frame_table.tolerance_ms", 0.0, 1000.0),
    )
    if mode == "udp" and frame_table.port <= 0:
        raise SourceError("BOARD_CONFIG_INVALID", "frame_table.mode=udp 需要 port > 0")

    meta_raw = raw.get("metadata") or {}
    if not isinstance(meta_raw, dict):
        raise SourceError("BOARD_CONFIG_INVALID", "metadata 必须是 object")
    metadata_udp_port = _int(meta_raw.get("udp_port", 0),
                             "metadata.udp_port", 0, 0xFFFF)
    ctl_raw = raw.get("control") or {}
    if not isinstance(ctl_raw, dict):
        raise SourceError("BOARD_CONFIG_INVALID", "control 必须是 object")
    control_host = str(ctl_raw.get("host", "")).strip()
    control_start_port = _int(ctl_raw.get("start_port", 0),
                              "control.start_port", 0, 0xFFFF)

    return BoardConfig(
        path=p, verified=bool(raw.get("verified", False)), video=video, atlas=atlas,
        calibration_id=calibration_id, source_map=source_map,
        frame_table=frame_table, metadata_udp_port=metadata_udp_port,
        notes=str(raw.get("notes", "")), control_host=control_host,
        control_start_port=control_start_port, raw=raw,
    )


class QuadCapture:
    """四个源文件逐帧读取并现场拼成 2x2 atlas；接口与 cv2.VideoCapture 对齐。"""

    def __init__(self, paths: dict[str, Path], cell_order: tuple[str, ...],
                 atlas_w: int, atlas_h: int):
        self.cell_w = max(int(atlas_w) // 2, 1)
        self.cell_h = max(int(atlas_h) // 2, 1)
        self.atlas_w = int(atlas_w)
        self.atlas_h = int(atlas_h)
        self.cell_order = tuple(cell_order)
        self.caps = {name: cv2.VideoCapture(str(paths[name]))
                     for name in self.cell_order}
        self.cap_fps = max(
            (float(cap.get(cv2.CAP_PROP_FPS) or 0.0) for cap in self.caps.values()),
            default=0.0)
        counts = [int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
                  for cap in self.caps.values()]
        self.frames = min(counts) if counts and all(n > 0 for n in counts) else 0

    def isOpened(self) -> bool:
        return all(cap.isOpened() for cap in self.caps.values())

    def get(self, prop: int) -> float:
        if prop == cv2.CAP_PROP_FPS:
            return self.cap_fps
        if prop == cv2.CAP_PROP_FRAME_WIDTH:
            return float(self.atlas_w)
        if prop == cv2.CAP_PROP_FRAME_HEIGHT:
            return float(self.atlas_h)
        if prop == cv2.CAP_PROP_FRAME_COUNT:
            return float(self.frames)
        return 0.0

    def set(self, prop: int, value: float) -> bool:
        if prop != cv2.CAP_PROP_POS_FRAMES:
            return False
        ok = True
        for cap in self.caps.values():
            ok = bool(cap.set(prop, value)) and ok
        return ok

    def read(self):
        frames: dict[str, np.ndarray] = {}
        for name, cap in self.caps.items():
            ok, img = cap.read()
            if not ok or img is None:
                return False, None
            if img.shape[1] != self.cell_w or img.shape[0] != self.cell_h:
                img = cv2.resize(img, (self.cell_w, self.cell_h),
                                 interpolation=cv2.INTER_AREA)
            frames[name] = img
        atlas = np.empty((self.atlas_h, self.atlas_w, 3), np.uint8)
        for slot, name in enumerate(self.cell_order):
            col, row = slot % 2, slot // 2
            y0, x0 = row * self.cell_h, col * self.cell_w
            atlas[y0:y0 + self.cell_h, x0:x0 + self.cell_w] = frames[name]
        return True, atlas

    def release(self) -> None:
        for cap in self.caps.values():
            cap.release()


class BoardSource(SourceBase):
    """2x2 atlas + 帧表 + 协议 UDP 的板端源；状态在每帧后重新评估。"""

    def __init__(self, store: AvmProtocolStore, calib: Calibration, cfg: BoardConfig,
                 *, realtime: bool = True, queue_size: int = 3,
                 max_frames: int | None = None, lane_onnx: str | Path | None = None,
                 lane_camera: str = "front"):
        video_source = "FILE" if cfg.video.kind == "file" else "CAPTURE"
        data_source = "UDP" if cfg.metadata_udp_port > 0 else "NONE"
        super().__init__(store, queue_size=queue_size, status=SourceStatus(
            label="BOARD", video_source=video_source, data_source=data_source,
            detail="板端 2x2 atlas；等待帧表/元数据", live=False))
        self.calib = calib
        self.cfg = cfg
        self.realtime = bool(realtime)
        self.max_frames = int(max_frames) if max_frames else None
        self.fps = float(cfg.video.fps)
        self.table = FrameTable()
        self.lane_camera = str(lane_camera)
        self.lane = None
        if lane_onnx:
            try:
                from dashboard.vision.lane_pc import PcLaneEstimator
                self.lane = PcLaneEstimator(lane_onnx, camera=self.lane_camera)
            except Exception as exc:  # noqa: BLE001
                raise SourceError("LANE_MODEL_UNAVAILABLE", repr(exc)) from exc
        self._receivers: list[UdpDatagramReceiver] = []
        self._aux_stop = threading.Event()
        self._video_ok = False
        self._last_resolve_reasons: list[tuple[str, str]] = []
        self._current_reasons: list[tuple[str, str]] = []
        self._expected_order = tuple(
            next(name for name, cam in calib.cameras.items() if cam.cell == cell)
            for cell in ((0, 0), (1, 0), (0, 1), (1, 1))
        )
        self._refresh_status(synced=None, cell_ok=None, video_ok=False)

    # ---------------------------------------------------------------- 门禁
    def _base_reasons(self) -> list[tuple[str, str]]:
        cfg = self.cfg
        reasons: list[tuple[str, str]] = []
        if not cfg.verified:
            reasons.append(("BOARD_CONFIG_UNVERIFIED",
                            "配置 verified=false；只做视频预览，不声明 LIVE"))
        if cfg.video.kind == "file":
            reasons.append(("BOARD_VIDEO_NOT_LIVE",
                            "video.kind=file；文件回放不是 LIVE 视频源"))
        if cfg.calibration_id and cfg.calibration_id != self.calib.calibration_id:
            reasons.append(("CALIB_MISMATCH",
                            f"配置 {cfg.calibration_id} != 标定 {self.calib.calibration_id}"))
        if (cfg.atlas.width, cfg.atlas.height) != (
                self.calib.atlas_width, self.calib.atlas_height):
            reasons.append(("BOARD_ATLAS_MISMATCH",
                            f"配置 {cfg.atlas.width}x{cfg.atlas.height} != 标定 "
                            f"{self.calib.atlas_width}x{self.calib.atlas_height}"))
        if tuple(cfg.atlas.cell_order) != self._expected_order:
            reasons.append(("CELL_ORDER_MISMATCH",
                            f"配置 {cfg.atlas.cell_order} != 标定 {self._expected_order}"))
        if not cfg.source_map:
            reasons.append(("SOURCE_MAP_MISSING", "缺少逐格 source_map"))
        elif set(cfg.source_map) != set(CELL_NAMES):
            reasons.append(("SOURCE_MAP_MISSING",
                            f"source_map 缺 {sorted(set(CELL_NAMES) - set(cfg.source_map))}"))
        elif any(state != "live" for state in cfg.source_map.values()):
            reasons.append(("SOURCE_MAP_NOT_LIVE",
                            f"source_map 非全 live：{cfg.source_map}"))
        if cfg.frame_table.mode != "udp":
            reasons.append(("FRAME_TABLE_MISSING",
                            "frame_table.mode!=udp；视频 frame_id 只能是本地序号"))
        if cfg.metadata_udp_port <= 0:
            reasons.append(("METADATA_SOURCE_MISSING",
                            "metadata.udp_port=0；没有同帧协议元数据"))
        return reasons

    def _refresh_status(self, synced: bool | None, cell_ok: bool | None,
                        video_ok: bool | None = None) -> None:
        if video_ok is None:
            video_ok = self._video_ok
        reasons = list(self._base_reasons())
        if not video_ok:
            reasons.append(("BOARD_VIDEO_WAITING", "视频尚未打开"))
        if self.cfg.frame_table.mode == "udp" and self.table.stats()["entries"] == 0:
            reasons.append(("FRAME_TABLE_WAITING", "尚未收到 AVM1 帧表"))
        if synced is False:
            reasons.extend(self._last_resolve_reasons)
        if cell_ok is False and not any(c == "CELL_NOT_LIVE" for c, _ in reasons):
            reasons.append(("CELL_NOT_LIVE", "当前帧有格不是 LIVE"))
        if self.cfg.metadata_udp_port > 0 and self.protocol_msgs == 0:
            reasons.append(("METADATA_WAITING", "尚未收到同帧协议元数据"))

        dedup: list[tuple[str, str]] = []
        seen: set[str] = set()
        for code, detail in reasons:
            if code not in seen:
                seen.add(code)
                dedup.append((code, detail))
        self._current_reasons = dedup
        if not dedup:
            self.status.label = "LIVE"
            self.status.live = True
            self.status.blocked_reason = ""
            self.status.detail = ("板端 2x2 LIVE：帧表与元数据同帧，四格 source_map=live")
        else:
            self.status.label = "BOARD"
            self.status.live = False
            self.status.blocked_reason = dedup[0][0]
            self.status.detail = "；".join(f"{code}（{detail}）" for code, detail in dedup)
        self.status.video_source = "FILE" if self.cfg.video.kind == "file" else "CAPTURE"
        self.status.data_source = "UDP" if self.cfg.metadata_udp_port > 0 else "NONE"
        self.status.mixed = (self.status.data_source != "NONE"
                             and self.status.data_source != self.status.video_source
                             and not self.status.live)

    # ---------------------------------------------------------------- 帧号
    def _resolve(self, pts_ms: float, k: int):
        """返回 (entry|None, synced, cell_ok, reasons)。"""
        reasons: list[tuple[str, str]] = []
        if self.cfg.frame_table.mode != "udp":
            reasons.append(("FRAME_TABLE_MISSING", "没有帧表，使用本地 frame_id"))
            self._last_resolve_reasons = reasons
            self.bump("table_missing")
            return None, False, True, reasons
        entry = self.table.lookup_pts(pts_ms, self.cfg.frame_table.tolerance_ms)
        if entry is None:
            reasons.append(("FRAME_TABLE_MISS",
                            f"pts={pts_ms:.1f}ms 容差 "
                            f"{self.cfg.frame_table.tolerance_ms:.0f}ms 内无条目"))
            self._last_resolve_reasons = reasons
            self.bump("table_miss")
            return None, False, True, reasons

        self.bump("table_hit")
        calib_ok = entry.calibration_id == self.calib.calibration_id
        if not calib_ok:
            reasons.append(("CALIB_MISMATCH",
                            f"帧表 {entry.calibration_id} != 标定 "
                            f"{self.calib.calibration_id}"))
            self.bump("table_calib_mismatch")
        order_ok = tuple(entry.cell_order) == self._expected_order
        if not order_ok:
            reasons.append(("CELL_ORDER_MISMATCH",
                            f"帧表 {entry.cell_order} != 标定 {self._expected_order}"))
            self.bump("table_order_mismatch")
        cell_ok = all(state == "LIVE" for state in entry.cell_state)
        if not cell_ok:
            reasons.append(("CELL_NOT_LIVE", f"帧表格状态 {entry.cell_state}"))
            self.bump("partial_cells")
        synced = calib_ok and order_ok
        self._last_resolve_reasons = reasons
        return (entry if synced else None), synced, cell_ok, reasons

    # ---------------------------------------------------------------- 视频
    def _open_video(self):
        cfg = self.cfg
        if (cfg.atlas.width, cfg.atlas.height) != (
                self.calib.atlas_width, self.calib.atlas_height):
            raise SourceError("BOARD_ATLAS_MISMATCH",
                              f"配置 atlas {cfg.atlas.width}x{cfg.atlas.height} != 标定 "
                              f"{self.calib.atlas_width}x{self.calib.atlas_height}")
        if cfg.video.kind == "file":
            if cfg.video.quad_paths:
                cap = QuadCapture(
                    dict(zip(CELL_NAMES, cfg.video.quad_paths)),
                    cfg.atlas.cell_order, cfg.atlas.width, cfg.atlas.height)
            else:
                cap = cv2.VideoCapture(str(cfg.video.path))
        else:
            cap = cv2.VideoCapture(int(cfg.video.device))
            if cfg.video.width > 0:
                cap.set(cv2.CAP_PROP_FRAME_WIDTH, cfg.video.width)
            if cfg.video.height > 0:
                cap.set(cv2.CAP_PROP_FRAME_HEIGHT, cfg.video.height)
            if cfg.video.fps > 0:
                cap.set(cv2.CAP_PROP_FPS, cfg.video.fps)
        if not cap.isOpened():
            what = cfg.video.path if cfg.video.kind == "file" else cfg.video.device
            raise SourceError("BOARD_VIDEO_UNAVAILABLE", f"打不开视频源：{what}")
        w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
        h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
        if cfg.video.layout == "atlas" and w > 0 and h > 0 and (w, h) != (
                cfg.atlas.width, cfg.atlas.height):
            cap.release()
            raise SourceError("BOARD_ATLAS_MISMATCH",
                              f"视频 {w}x{h} != 配置 atlas "
                              f"{cfg.atlas.width}x{cfg.atlas.height}")
        fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
        if fps > 0 and cfg.video.fps <= 0:
            self.fps = fps
        return cap

    def _validate_shape(self, img) -> None:
        if img is None:
            return
        h, w = img.shape[:2]
        if self.cfg.video.layout == "single":
            cam = self.calib.cameras["front"]
            expect = (cam.width, cam.height)
        else:
            expect = (self.cfg.atlas.width, self.cfg.atlas.height)
        if (w, h) != expect:
            self.bump("size_mismatch")
            raise SourceError("BOARD_VIDEO_MISMATCH",
                              f"帧尺寸 {w}x{h} != 期望 {expect[0]}x{expect[1]}")

    def _pts_ms(self, cap, k: int, t0_ns: int) -> float:
        if self.cfg.video.kind == "file":
            return k * 1000.0 / max(self.fps, 1e-6)
        raw = float(cap.get(cv2.CAP_PROP_POS_MSEC) or 0.0)
        if math.isfinite(raw) and raw > 0:
            return raw
        return (time.monotonic_ns() - t0_ns) / 1e6

    # ---------------------------------------------------------------- 辅助线程
    def _start_aux(self) -> None:
        cfg = self.cfg
        try:
            if cfg.frame_table.mode == "udp":
                rx = UdpDatagramReceiver(
                    "0.0.0.0", cfg.frame_table.port,
                    lambda buf, _addr: self.table.ingest(buf),
                    self._aux_stop, self.stopping)
                rx.start()
                self._receivers.append(rx)
            if cfg.metadata_udp_port > 0:
                rx = UdpDatagramReceiver(
                    "0.0.0.0", cfg.metadata_udp_port,
                    lambda buf, _addr: self.feed_protocol(buf),
                    self._aux_stop, self.stopping)
                rx.start()
                self._receivers.append(rx)
            if self.cfg.control_start_port > 0 and self.cfg.control_host:
                s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                try:
                    s.sendto(b"START", (self.cfg.control_host,
                                        int(self.cfg.control_start_port)))
                    self.bump("control_start_sent")
                finally:
                    s.close()
        except OSError as exc:
            self._stop_aux()
            raise SourceError("BOARD_PORT_BIND_FAILED", f"UDP 端口绑定失败：{exc}") from exc

    def _stop_aux(self) -> None:
        self._aux_stop.set()
        for rx in self._receivers:
            rx.stop()
        self._receivers.clear()

    def _wait_for_detection(self, frame_id: int) -> None:
        """检测驱动播放：本帧检测已到才发布，避免 PC 抢跑后 1s 空等。"""
        timeout_s = self.cfg.video.detect_wait_ms / 1000.0
        if timeout_s <= 0:
            return
        deadline = time.monotonic() + timeout_s
        while not self.stopping() and self.store.bundle(frame_id) is None:
            if time.monotonic() >= deadline:
                self.bump("detect_wait_timeout")
                return
            time.sleep(0.002)
        self.bump("detect_wait_hit")

    # ---------------------------------------------------------------- 产出
    def _produce(self) -> None:
        cap = self._open_video()
        self._video_ok = True
        self._start_aux()
        self._refresh_status(None, None)
        delay_s = self.cfg.video.start_delay_ms / 1000.0
        if delay_s > 0:
            self.bump("start_delay")
            deadline = time.monotonic() + delay_s
            while not self.stopping() and time.monotonic() < deadline:
                time.sleep(min(0.05, max(deadline - time.monotonic(), 0.0)))
        t0 = time.monotonic_ns()
        produced = 0
        total = 0
        k = 0
        try:
            while not self.stopping():
                ok, img = cap.read()
                if not ok or img is None:
                    if self.cfg.video.loop and self.cfg.video.kind == "file":
                        self.bump("loops")
                        cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                        t0 = time.monotonic_ns()
                        produced = 0
                        k = 0
                        continue
                    break
                if self.cfg.video.layout == "single":
                    cam = self.calib.cameras["front"]
                    if img.shape[1] != cam.width or img.shape[0] != cam.height:
                        img = cv2.resize(img, (cam.width, cam.height),
                                         interpolation=cv2.INTER_AREA)
                self._validate_shape(img)
                pts_ms = self._pts_ms(cap, k, t0)
                entry, synced, cell_ok, _reasons = self._resolve(pts_ms, k)
                frame_id = entry.frame_id if entry is not None else (
                    self.cfg.video.start_frame_id + k)
                if (self.cfg.video.sync_to_detections
                        and self.cfg.metadata_udp_port > 0):
                    self._wait_for_detection(frame_id)
                lane = None
                if self.lane is not None:
                    if self.cfg.video.layout == "single":
                        lane_img = img
                    else:
                        cam = self.calib.cameras[self.lane_camera]
                        x0, y0 = cam.cell[0] * cam.width, cam.cell[1] * cam.height
                        lane_img = img[y0:y0 + cam.height, x0:x0 + cam.width]
                    lane = self.lane.update(lane_img, frame_id)
                self._refresh_status(synced, cell_ok)
                if self.status.live:
                    label = "LIVE"
                elif entry is not None and not cell_ok:
                    label = "BOARD_PARTIAL"
                else:
                    label = "BOARD"
                self.publish(VideoFrame(
                    frame_id=frame_id, image=img, mono_ns=time.monotonic_ns(),
                    label=label, index=k, lane=lane))
                produced += 1
                total += 1
                k += 1
                if self.max_frames is not None and total >= self.max_frames:
                    break
                if self.realtime:
                    target = t0 + int(produced / max(self.fps, 1e-6) * 1e9)
                    while not self.stopping():
                        gap = target - time.monotonic_ns()
                        if gap <= 0:
                            break
                        time.sleep(min(gap / 1e9, 0.05))
        finally:
            cap.release()
        self.bump("frames_total", total)

    def stop(self, timeout_s: float = 2.0) -> None:
        """视频先结束后，UI 可能还在等同帧元数据；接收线程跟 stop() 一起收。"""
        super().stop(timeout_s)
        self._stop_aux()

    @property
    def single_video(self) -> bool:
        return self.cfg.video.layout == "single"

    # ---------------------------------------------------------------- 描述
    def describe(self) -> str:
        cfg = self.cfg
        if cfg.video.quad_paths:
            where = "quad:" + ",".join(p.name for p in cfg.video.quad_paths)
        else:
            where = (str(cfg.video.path) if cfg.video.kind == "file"
                     else f"device {cfg.video.device}")
        table = f"{cfg.frame_table.mode}:{cfg.frame_table.port}"
        meta = str(cfg.metadata_udp_port) if cfg.metadata_udp_port else "off"
        return (f"{self.status.banner()} | {cfg.video.kind} {where} @ {self.fps:.1f} fps"
                f" | layout={cfg.video.layout} | lane={'on' if self.lane else 'off'}"
                f" | sync={'dets' if cfg.video.sync_to_detections else 'off'}"
                f" | frame_table={table} | metadata_udp={meta}"
                f" | calib_id={self.calib.calibration_id}")

    def stats(self) -> dict:
        d = super().stats()
        d.update({
            "board_config": str(self.cfg.path),
            "video_kind": self.cfg.video.kind,
            "video_layout": self.cfg.video.layout,
            "video": str(self.cfg.video.path) if self.cfg.video.kind == "file"
            else self.cfg.video.device,
            "quad_paths": ([str(x) for x in self.cfg.video.quad_paths]
                           if self.cfg.video.quad_paths else None),
            "fps": self.fps,
            "start_delay_ms": self.cfg.video.start_delay_ms,
            "verified": self.cfg.verified,
            "frame_table": self.table.stats(),
            "sync_hits": self.extra_counters.get("table_hit", 0),
            "sync_misses": self.extra_counters.get("table_miss", 0),
            "partial_cells": self.extra_counters.get("partial_cells", 0),
            "metadata_msgs": self.protocol_msgs,
            "detect_sync": self.cfg.video.sync_to_detections,
            "detect_wait_hits": self.extra_counters.get("detect_wait_hit", 0),
            "detect_wait_timeouts": self.extra_counters.get("detect_wait_timeout", 0),
            "lane": (self.lane.stats() if self.lane is not None else None),
            "gate_reasons": [code for code, _ in self._current_reasons],
            "receivers": [rx.stats() for rx in self._receivers],
        })
        return d


__all__ = [
    "BOARD_FORMAT", "BoardConfig", "BoardSource", "VideoConfig", "AtlasConfig",
    "FrameTableConfig", "FrameTableEntry", "load_board_config",
]
