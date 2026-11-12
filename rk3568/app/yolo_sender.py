"""板端 YOLO -> AVM3D 发送器（PC 上用 ONNX/Fake 替身，板端换 RKNN）。

方向：读取 2x2 atlas 的 front 格（或单路前视视频）-> 检测 -> `OBJECT`/`TRACK_V1`
经 UDP 7000 -> AVM3D `BoardSource`。bbox 坐标始终是 front 标定图像的坐标
（SIM=640x360），不是 atlas 的 1280x720，也不是网络输入 640x640。

示例（PC 替身，证明接口）::

    python rk_deploy/app/yolo_sender.py --backend fake \
        --video dashboard/avm3d/data/replay/avm_sim_4up.mp4 \
        --layout atlas --calib dashboard/avm3d/calib/sim_calibration.json \
        --host 127.0.0.1 --port 7000 --fps 20 --frames 120

板端（RKNN）::

    python3 rk_deploy/app/yolo_sender.py --backend rknn \
        --model rk_deploy/model/traffic9_split6_640.rknn \
        --video /dev/video0 --layout single --fps 20 --host <PC_IP> --port 7000
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from dashboard.avm3d.calib.loader import CalibrationError, load_calibration  # noqa: E402
from dashboard.vision.backends import (  # noqa: E402
    BackendUnavailable, FakeBackend, OnnxBackend, RknnBackend,
)
from dashboard.vision.transport import UdpDetectionSender  # noqa: E402

DEFAULT_CALIB = ROOT / "dashboard" / "avm3d" / "calib" / "sim_calibration.json"
DEFAULT_ONNX = ROOT / "traffic_yolo_deploy" / "deploy_rk3568" / "models" / "traffic9_split6_640.onnx"


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="板端 YOLO 检测结果 -> AVM3D UDP")
    ap.add_argument("--backend", choices=("fake", "onnx", "rknn"), default="fake")
    ap.add_argument("--host", default="127.0.0.1", help="PC IP（AVM3D 所在机器）")
    ap.add_argument("--port", type=int, default=7000, help="AVM3D metadata.udp_port")
    ap.add_argument("--video", default=None, help="2x2 atlas 视频或单路前视视频")
    ap.add_argument("--layout", choices=("atlas", "single"), default="atlas")
    ap.add_argument("--calib", default=str(DEFAULT_CALIB), help="AVM3D 标定（决定 front 格坐标）")
    ap.add_argument("--cell", default="front", choices=("front", "right", "rear", "left"))
    ap.add_argument("--fps", type=float, default=20.0)
    ap.add_argument("--frames", type=int, default=0, help="0=一直发")
    ap.add_argument("--loop", action="store_true", help="视频循环")
    ap.add_argument("--start-frame-id", type=int, default=0)
    ap.add_argument("--onnx", default=str(DEFAULT_ONNX))
    ap.add_argument("--model", default=str(ROOT / "rk_deploy" / "model" / "traffic9_split6_640.rknn"))
    ap.add_argument("--imgsz", type=int, default=640)
    ap.add_argument("--conf", type=float, default=0.30)
    ap.add_argument("--iou", type=float, default=0.45)
    ap.add_argument("--max-det", type=int, default=60)
    ap.add_argument("--ort-threads", type=int, default=4)
    ap.add_argument("--fake-objects", type=int, default=2)
    ap.add_argument("--source-id", default="RK3568",
                    help="协议 source_id；板端/PC 替身都默认 RK3568")
    ap.add_argument("--clock-domain-id", type=int, default=2)
    ap.add_argument("--quiet", action="store_true")
    return ap.parse_args(argv)


def _make_backend(args, cell_w: int):
    common = dict(imgsz=args.imgsz, conf=args.conf, iou=args.iou, max_det=args.max_det)
    if args.backend == "fake":
        return FakeBackend(n=args.fake_objects)
    if args.backend == "onnx":
        return OnnxBackend(args.onnx, ort_threads=args.ort_threads,
                           process_width=cell_w, **common)
    return RknnBackend(args.model, **common)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    calib_path = Path(args.calib)
    if not calib_path.is_absolute():
        calib_path = (ROOT / calib_path).resolve()
    try:
        calib = load_calibration(calib_path)
    except CalibrationError as exc:
        print(f"标定不可用 {exc.code}: {exc.detail}", file=sys.stderr)
        return 2
    cam = calib.cameras[args.cell]
    cell_w, cell_h = int(cam.width), int(cam.height)
    cell_col, cell_row = cam.cell

    try:
        backend = _make_backend(args, cell_w)
    except BackendUnavailable as exc:
        print(f"后端不可用 {exc.code}: {exc.detail}", file=sys.stderr)
        return 2

    cap = None
    if args.video:
        cap = cv2.VideoCapture(str(args.video))
        if not cap.isOpened():
            print(f"打不开视频：{args.video}", file=sys.stderr)
            backend.close()
            return 2

    sender = UdpDetectionSender(
        args.host, args.port, source_id=args.source_id,
        clock_domain_id=args.clock_domain_id, calibration_id=calib.calibration_id)
    fps = max(float(args.fps), 1e-3)
    t0 = time.monotonic()
    k = 0
    print(f"[yolo_sender] backend={args.backend} -> udp {args.host}:{args.port} "
          f"cell={args.cell} {cell_w}x{cell_h} calib_id={calib.calibration_id}")
    try:
        while True:
            if args.frames and k >= args.frames:
                break
            if cap is not None:
                ok, frame = cap.read()
                if not ok or frame is None:
                    if args.loop:
                        cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                        continue
                    break
                if args.layout == "atlas":
                    x0, y0 = cell_col * cell_w, cell_row * cell_h
                    cell = frame[y0:y0 + cell_h, x0:x0 + cell_w]
                else:
                    cell = frame
                    if cell.shape[1] != cell_w or cell.shape[0] != cell_h:
                        cell = cv2.resize(cell, (cell_w, cell_h),
                                          interpolation=cv2.INTER_AREA)
                if cell.shape[1] != cell_w or cell.shape[0] != cell_h:
                    print(f"front 格尺寸 {cell.shape[1]}x{cell.shape[0]} != "
                          f"标定 {cell_w}x{cell_h}", file=sys.stderr)
                    return 2
            else:
                cell = np.zeros((cell_h, cell_w, 3), np.uint8)

            frame_id = int(args.start_frame_id) + k
            t_sec = k / fps
            try:
                fd = backend.infer(cell, frame_id, t_sec)
            except Exception as exc:  # noqa: BLE001
                print(f"推理失败 frame={frame_id}: {exc!r}", file=sys.stderr)
                return 3
            sizes = sender.send(fd)
            if not args.quiet:
                top = fd.detections[0] if fd.detections else None
                extra = (f" top=c{top.class_id}:{top.score:.2f}"
                         f" [{top.bbox_xyxy[0]:.0f},{top.bbox_xyxy[1]:.0f},"
                         f"{top.bbox_xyxy[2]:.0f},{top.bbox_xyxy[3]:.0f}]"
                         if top else "")
                print(f"frame {frame_id:6d} n={len(fd.detections)} "
                      f"bytes={sum(sizes)}{extra}")
            k += 1
            target = t0 + k / fps
            while True:
                gap = target - time.monotonic()
                if gap <= 0:
                    break
                time.sleep(min(gap, 0.05))
    finally:
        sender.close()
        backend.close()
        if cap is not None:
            cap.release()
    print(f"[yolo_sender] sent {k} frames / {sender.sent_packets} packets / "
          f"{sender.sent_bytes} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
