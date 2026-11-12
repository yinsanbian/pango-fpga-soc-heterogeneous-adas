"""BOARD 源测试：配置校验、2x2 atlas、AVM1 帧号、门禁、UDP 元数据。

跑：python dashboard\\avm3d\\tests\\test_board_source.py
"""
from __future__ import annotations

import json
import socket
import tempfile
import time
from pathlib import Path

import cv2
import numpy as np

from harness import check, equal, run, section  # noqa: E402

import payloads  # noqa: E402

from dashboard.avm3d.calib.loader import load_calibration  # noqa: E402
from dashboard.avm3d.config import DEFAULT_CALIBRATION, DEFAULT_REPLAY_VIDEO  # noqa: E402
from dashboard.avm3d.protocol_bridge import AvmProtocolStore  # noqa: E402
from dashboard.avm3d.sources.base import SourceError  # noqa: E402
from dashboard.avm3d.sources.board import (  # noqa: E402
    BoardSource, load_board_config,
)
from dashboard.avm3d.sources.frametable import FrameTableEntry, encode_entry  # noqa: E402
from dashboard.protocol import schema  # noqa: E402

CALIB = load_calibration(DEFAULT_CALIBRATION)
SPEC = schema.load_spec()
VIDEO = Path(DEFAULT_REPLAY_VIDEO).resolve()


def _base_doc() -> dict:
    return {
        "schema": "avm3d_board_v1",
        "verified": False,
        "video": {
            "kind": "file", "path": str(VIDEO), "device": 0, "fps": 20.0,
            "loop": False, "start_frame_id": 0, "width": 1280, "height": 720,
        },
        "atlas": {
            "width": 1280, "height": 720,
            "cell_order": ["front", "right", "rear", "left"],
        },
        "calibration_id": CALIB.calibration_id,
        "source_map": {"front": "live", "right": "live", "rear": "live", "left": "live"},
        "frame_table": {"mode": "none", "port": 0, "tolerance_ms": 30.0},
        "metadata": {"udp_port": 0},
        "notes": "test",
    }


def _write(tmp: Path, doc: dict, name: str = "board.json") -> Path:
    p = tmp / name
    p.write_text(json.dumps(doc, ensure_ascii=False), encoding="utf-8")
    return p


def _free_port() -> int:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(("127.0.0.1", 0))
    port = int(s.getsockname()[1])
    s.close()
    return port


def _drain(src, timeout_s: float = 15.0):
    out = []
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        fr = src.poll(0.2)
        if fr is not None:
            out.append(fr)
            continue
        if src.ended.is_set():
            break
    return out


def t_config_guards() -> None:
    section("t_config_guards  配置结构/路径/端口错误")
    with tempfile.TemporaryDirectory() as td:
        d = Path(td)
        cases = []
        bad = _base_doc()
        bad["schema"] = "wrong"
        cases.append(("schema", bad, "BOARD_CONFIG_INVALID"))
        bad = _base_doc()
        del bad["video"]["path"]
        cases.append(("缺 video.path", bad, "BOARD_CONFIG_INVALID"))
        bad = _base_doc()
        bad["video"]["path"] = str(d / "nope.mp4")
        cases.append(("视频不存在", bad, "BOARD_VIDEO_UNAVAILABLE"))
        bad = _base_doc()
        bad["atlas"]["cell_order"] = ["front", "front", "rear", "left"]
        cases.append(("cell_order 重复", bad, "BOARD_CONFIG_INVALID"))
        bad = _base_doc()
        bad["frame_table"] = {"mode": "udp", "port": 0, "tolerance_ms": 30}
        cases.append(("udp 端口 0", bad, "BOARD_CONFIG_INVALID"))
        bad = _base_doc()
        bad["video"]["detect_wait_ms"] = -1
        cases.append(("检测等待为负", bad, "BOARD_CONFIG_INVALID"))
        for name, doc, code in cases:
            p = _write(d, doc, "bad.json")
            try:
                load_board_config(p)
                raise AssertionError(f"{name} 必须被拒绝")
            except SourceError as exc:
                equal(f"{name} 错误码", exc.code, code)
        good = load_board_config(_write(d, _base_doc(), "good.json"))
        equal("合法配置指纹", good.video.kind, "file")
        equal("合法配置帧表", good.frame_table.mode, "none")
        equal("检测驱动默认关", good.video.sync_to_detections, False)
        equal("检测等待默认 500ms", good.video.detect_wait_ms, 500.0)
        sync_doc = _base_doc()
        sync_doc["video"]["sync_to_detections"] = True
        sync_doc["video"]["detect_wait_ms"] = 250
        sync_doc["video"]["start_delay_ms"] = 1200
        sync = load_board_config(_write(d, sync_doc, "sync.json"))
        equal("检测驱动可开启", sync.video.sync_to_detections, True)
        equal("检测等待可调", sync.video.detect_wait_ms, 250.0)
        equal("启动延时可调", sync.video.start_delay_ms, 1200.0)


def t_preview_source() -> None:
    section("t_preview_source  文件预览：帧/标签/门禁原因")
    with tempfile.TemporaryDirectory() as td:
        cfg = load_board_config(_write(Path(td), _base_doc()))
        store = AvmProtocolStore()
        src = BoardSource(store, CALIB, cfg, realtime=False, max_frames=5)
        src.start()
        frames = _drain(src)
        src.stop()
        equal("帧数", len(frames), 5)
        equal("frame_id 本地连续", [f.frame_id for f in frames], [0, 1, 2, 3, 4])
        equal("图像形状", {f.image.shape for f in frames}, {(720, 1280, 3)})
        equal("视频标签", {f.label for f in frames}, {"BOARD"})
        equal("无致命错误", src.fatal, None)
        equal("状态不是 LIVE", (src.status.label, src.status.live), ("BOARD", False))
        reasons = [c for c, _ in src._current_reasons]
        check("含未核验原因", "BOARD_CONFIG_UNVERIFIED" in reasons)
        check("含文件非 LIVE 原因", "BOARD_VIDEO_NOT_LIVE" in reasons)
        check("含缺帧表原因", "FRAME_TABLE_MISSING" in reasons)
        check("含缺元数据原因", "METADATA_SOURCE_MISSING" in reasons)
        equal("统计 video_kind", src.stats()["video_kind"], "file")
        equal("统计元数据消息", src.stats()["metadata_msgs"], 0)


def t_single_video_layout() -> None:
    section("t_single_video_layout  单视频 layout=single 缩放到 front 640x360")
    with tempfile.TemporaryDirectory() as td:
        doc = _base_doc()
        doc["video"]["layout"] = "single"
        doc["source_map"] = {"front": "live", "right": "absent",
                             "rear": "absent", "left": "absent"}
        cfg = load_board_config(_write(Path(td), doc))
        equal("配置 layout", cfg.video.layout, "single")
        src = BoardSource(AvmProtocolStore(), CALIB, cfg, realtime=False, max_frames=3)
        src.start()
        frames = _drain(src)
        src.stop()
        equal("单视频标记", src.single_video, True)
        equal("帧数", len(frames), 3)
        equal("缩放后形状", {f.image.shape for f in frames}, {(360, 640, 3)})
        equal("frame_id 本地连续", [f.frame_id for f in frames], [0, 1, 2])
        equal("无致命错误", src.fatal, None)
        equal("统计 layout", src.stats()["video_layout"], "single")

def t_quad_video() -> None:
    section("t_quad_video  四个源文件现场拼 1280x720，顺序 front/right/rear/left")
    with tempfile.TemporaryDirectory() as td:
        d = Path(td)
        colors = {"front": (255, 0, 0), "right": (0, 255, 0),
                  "rear": (0, 0, 255), "left": (255, 255, 255)}
        quad = {}
        for name, color in colors.items():
            p = d / f"{name}.mp4"
            w = cv2.VideoWriter(str(p), cv2.VideoWriter_fourcc(*"mp4v"),
                                10.0, (320, 180))
            for _ in range(4):
                w.write(np.full((180, 320, 3), color, np.uint8))
            w.release()
            quad[name] = str(p)
        doc = _base_doc()
        doc["video"] = {
            "kind": "file", "path": quad["front"], "device": 0, "fps": 10.0,
            "loop": False, "start_frame_id": 0, "width": 0, "height": 0,
            "layout": "atlas", "quad_paths": quad, "start_delay_ms": 0,
        }
        doc["source_map"] = {"front": "live", "right": "live",
                             "rear": "live", "left": "live"}
        cfg = load_board_config(_write(d, doc))
        equal("四路路径", len(cfg.video.quad_paths or ()), 4)
        src = BoardSource(AvmProtocolStore(), CALIB, cfg, realtime=False, max_frames=2)
        src.start()
        frames = _drain(src)
        src.stop()
        equal("帧数", len(frames), 2)
        equal("atlas 形状", frames[0].image.shape, (720, 1280, 3))
        img = frames[0].image
        centers = {"front": (180, 320), "right": (180, 960),
                   "rear": (540, 320), "left": (540, 960)}
        b, g, r = img[centers["front"]]
        check("front 在左上且为蓝色", b > 150 and r < 100)
        b, g, r = img[centers["right"]]
        check("right 在右上且为绿色", g > 150 and r < 100)
        b, g, r = img[centers["rear"]]
        check("rear 在左下且为红色", r > 150 and b < 100)
        b, g, r = img[centers["left"]]
        check("left 在右下且为白色", min(b, g, r) > 180)
        equal("无致命错误", src.fatal, None)


def t_atlas_mismatch() -> None:
    section("t_atlas_mismatch  2x2 尺寸不符必须硬失败")
    with tempfile.TemporaryDirectory() as td:
        doc = _base_doc()
        doc["atlas"]["width"] = 1920
        doc["atlas"]["height"] = 1080
        cfg = load_board_config(_write(Path(td), doc))
        src = BoardSource(AvmProtocolStore(), CALIB, cfg, realtime=False)
        try:
            src._open_video()
            raise AssertionError("尺寸不符必须失败")
        except SourceError as exc:
            equal("错误码", exc.code, "BOARD_ATLAS_MISMATCH")


def t_live_gate_and_resolve() -> None:
    section("t_live_gate_and_resolve  帧表/门禁：只有全条件满足才 LIVE")
    with tempfile.TemporaryDirectory() as td:
        doc = _base_doc()
        doc["verified"] = True
        doc["video"] = {"kind": "capture", "path": None, "device": 0, "fps": 20.0,
                        "loop": False, "start_frame_id": 0, "width": 1280, "height": 720}
        doc["frame_table"] = {"mode": "udp", "port": 7001, "tolerance_ms": 30.0}
        doc["metadata"]["udp_port"] = 7000
        cfg = load_board_config(_write(Path(td), doc))
        src = BoardSource(AvmProtocolStore(), CALIB, cfg, realtime=False)
        equal("配置基础原因", src._base_reasons(), [])

        ent = FrameTableEntry(frame_id=42, pts_ms=100.0,
                              calibration_id=CALIB.calibration_id)
        src.table.add(ent)
        got, synced, cell_ok, reasons = src._resolve(101.0, 2)
        equal("帧表命中 frame_id", got.frame_id if got else None, 42)
        equal("同步成功", synced, True)
        equal("四格 live", cell_ok, True)
        equal("无拒绝原因", reasons, [])
        src._video_ok = True
        src.protocol_msgs = 1
        src._refresh_status(True, True)
        equal("全条件满足 -> LIVE", (src.status.label, src.status.live),
              ("LIVE", True))
        equal("LIVE 无阻塞码", src.status.blocked_reason, "")

        bad = FrameTableEntry(frame_id=43, pts_ms=200.0,
                              calibration_id=CALIB.calibration_id,
                              cell_state=("LIVE", "STALE", "LIVE", "LIVE"))
        src.table.add(bad)
        got2, synced2, cell2, reasons2 = src._resolve(200.0, 3)
        equal("有格非 live 仍取到帧号", got2.frame_id if got2 else None, 43)
        equal("有格非 live 不算全 live", cell2, False)
        check("记录 CELL_NOT_LIVE", any(c == "CELL_NOT_LIVE" for c, _ in reasons2))
        src._refresh_status(True, False)
        equal("有格非 live -> BOARD", src.status.label, "BOARD")
        equal("阻塞码", src.status.blocked_reason, "CELL_NOT_LIVE")

        got3, synced3, _cell3, reasons3 = src._resolve(9999.0, 4)
        equal("PTS 无条目返回 None", got3, None)
        equal("不同步", synced3, False)
        check("记录 FRAME_TABLE_MISS",
              any(c == "FRAME_TABLE_MISS" for c, _ in reasons3))
        src._refresh_status(False, True)
        equal("缺帧表 -> BOARD", (src.status.label, src.status.blocked_reason),
              ("BOARD", "FRAME_TABLE_MISS"))


def t_frame_table_end_to_end() -> None:
    section("t_frame_table_end_to_end  真实 UDP 帧表驱动 frame_id")
    with tempfile.TemporaryDirectory() as td:
        port = _free_port()
        doc = _base_doc()
        doc["frame_table"] = {"mode": "udp", "port": port, "tolerance_ms": 30.0}
        cfg = load_board_config(_write(Path(td), doc))
        src = BoardSource(AvmProtocolStore(), CALIB, cfg, realtime=True, max_frames=20)
        src.start()
        time.sleep(0.15)
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        for k in range(30):
            ent = FrameTableEntry(frame_id=100 + k, pts_ms=k * 50.0,
                                  calibration_id=CALIB.calibration_id)
            sock.sendto(encode_entry(ent), ("127.0.0.1", port))
        sock.close()
        frames = _drain(src)
        src.stop()
        equal("无致命错误", src.fatal, None)
        check("有帧表命中", src.stats()["sync_hits"] > 0)
        check("frame_id 来自帧表", any(f.frame_id >= 100 for f in frames))
        equal("全部标签 BOARD（文件/未核验）", {f.label for f in frames}, {"BOARD"})


def t_detection_sync() -> None:
    section("t_detection_sync  已有同帧检测时不等待，直接发布")
    with tempfile.TemporaryDirectory() as td:
        port = _free_port()
        doc = _base_doc()
        doc["metadata"]["udp_port"] = port
        doc["video"]["sync_to_detections"] = True
        doc["video"]["detect_wait_ms"] = 500
        cfg = load_board_config(_write(Path(td), doc))
        store = AvmProtocolStore()
        buf = SPEC.encode(
            "LANE", payloads.LANE, source_id="RK3568", mode_id=0, status="OK",
            invalid_reason="NONE", calibration_id=CALIB.calibration_id,
            frame_id=0, timestamp_ns=0, clock_domain_id=2, sequence=0)
        store.feed(buf)
        src = BoardSource(store, CALIB, cfg, realtime=False, max_frames=1)
        src.start()
        frames = _drain(src)
        src.stop()
        equal("帧数", len(frames), 1)
        equal("检测等待命中", src.stats()["detect_wait_hits"], 1)
        equal("检测等待超时", src.stats()["detect_wait_timeouts"], 0)


def t_detection_sync_timeout() -> None:
    section("t_detection_sync_timeout  检测迟到时超时放行，不卡死")
    with tempfile.TemporaryDirectory() as td:
        port = _free_port()
        doc = _base_doc()
        doc["metadata"]["udp_port"] = port
        doc["video"]["sync_to_detections"] = True
        doc["video"]["detect_wait_ms"] = 50
        cfg = load_board_config(_write(Path(td), doc))
        src = BoardSource(AvmProtocolStore(), CALIB, cfg, realtime=False, max_frames=1)
        src.start()
        frames = _drain(src)
        src.stop()
        equal("帧数", len(frames), 1)
        equal("检测等待命中", src.stats()["detect_wait_hits"], 0)
        equal("检测等待超时", src.stats()["detect_wait_timeouts"], 1)


def t_metadata_udp() -> None:
    section("t_metadata_udp  协议 UDP 元数据进 store")
    with tempfile.TemporaryDirectory() as td:
        port = _free_port()
        doc = _base_doc()
        doc["metadata"]["udp_port"] = port
        cfg = load_board_config(_write(Path(td), doc))
        store = AvmProtocolStore()
        src = BoardSource(store, CALIB, cfg, realtime=True, max_frames=40)
        src.start()
        time.sleep(0.15)
        buf = SPEC.encode(
            "LANE", payloads.LANE, source_id="RK3568", mode_id=0, status="OK",
            invalid_reason="NONE", calibration_id=CALIB.calibration_id,
            frame_id=0, timestamp_ns=0, clock_domain_id=2, sequence=0)
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.sendto(buf, ("127.0.0.1", port))
        sock.close()
        deadline = time.monotonic() + 1.5
        while src.protocol_msgs < 1 and time.monotonic() < deadline:
            time.sleep(0.02)
        src.stop()
        equal("收到协议消息", src.protocol_msgs, 1)
        bundle = store.bundle(0)
        check("同帧 bundle 可见", bundle is not None and bundle.has("LANE"))
        equal("无致命错误", src.fatal, None)


def main() -> int:
    return run((t_config_guards, t_preview_source, t_single_video_layout, t_quad_video,
                t_atlas_mismatch, t_live_gate_and_resolve, t_frame_table_end_to_end,
                t_detection_sync, t_detection_sync_timeout,
                t_metadata_udp), "test_board_source")


if __name__ == "__main__":
    raise SystemExit(main())
