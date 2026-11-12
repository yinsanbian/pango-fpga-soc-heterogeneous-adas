#!/usr/bin/env python3
"""RK3568 无窗口板端 YOLO：RKNN 推理 -> OBJECT(0x20) UDP -> PC AVM3D。

板端只做识别；车道/路线/弯向在 PC 端做。
输入视频按 front 标定缩放到 640x360，bbox 坐标系与 PC 一致。

性能：默认 fast 后处理只对过阈值锚点做 DFL，避免每帧对 6400 个锚点做
softmax；预处理直接 resize 到 640x360 再写进 640x640 画布，省掉二次缩放。
`--post ref` 可切回 traffic9_postprocess.postprocess，`--verify-post N`
会同时跑两条路径并逐项比对，用于改后处理后的精度回归。
"""
from __future__ import annotations

import argparse
import math
import socket
import struct
import sys
import time
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from dashboard.protocol import schema  # noqa: E402
from dashboard.vision.contract import (  # noqa: E402
    Detection, DetectionProtocol, FrameDetections,
)

DEFAULT_POSTPROCESS = Path.home() / "traffic9_rk3568_deploy" / "linux"
DEFAULT_MODEL = Path.home() / "traffic9_rk3568_deploy" / "models" / "traffic9_split6_640_rk3568.rknn"


def parse_args(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default=str(DEFAULT_MODEL))
    ap.add_argument("--postprocess-dir", default=str(DEFAULT_POSTPROCESS))
    ap.add_argument("--video", default=None, help="视频文件；与 --capture-device 二选一")
    ap.add_argument("--capture-device", type=int, default=None,
                    help="V4L2 设备号，如 0=/dev/video0（USB HDMI 采集卡）")
    ap.add_argument("--capture-width", type=int, default=1920)
    ap.add_argument("--capture-height", type=int, default=1080)
    ap.add_argument("--capture-fps", type=float, default=15.0)
    ap.add_argument("--capture-fourcc", default="MJPG")
    ap.add_argument("--capture-timeout", type=float, default=30.0,
                    help="等待 HDMI 首帧/信号的最长秒数")
    ap.add_argument("--min-mean", type=float, default=5.0,
                    help="采集首帧最低平均亮度；低于此值视为 No Signal/黑屏")
    ap.add_argument("--allow-dark", action="store_true",
                    help="允许接近全黑的首帧（夜间场景）")
    ap.add_argument("--crop", default="",
                    help="采集后裁剪 x,y,w,h；auto/front=左上 1/4 前向格")
    ap.add_argument("--host", required=True, help="PC IP")
    ap.add_argument("--port", type=int, default=7000)
    ap.add_argument("--video-port", type=int, default=0,
                    help="回传 JPEG 前向画面的 PC UDP 端口；0=关闭")
    ap.add_argument("--video-quality", type=int, default=70)
    ap.add_argument("--atlas-port", type=int, default=0,
                    help="可选：整张四宫格推理 OBJECT 的 UDP 端口；0=关闭")
    ap.add_argument("--atlas-video-port", type=int, default=0,
                    help="可选：整张四宫格 JPEG 的 UDP 端口；0=关闭")
    ap.add_argument("--atlas-width", type=int, default=960)
    ap.add_argument("--atlas-height", type=int, default=540)
    ap.add_argument("--atlas-quality", type=int, default=60)
    ap.add_argument("--fps", type=float, default=15.0,
                    help="发送节拍；0=板端全速（长视频离线处理）")
    ap.add_argument("--frames", type=int, default=0)
    ap.add_argument("--loop", action="store_true")
    ap.add_argument("--imgsz", type=int, default=640)
    ap.add_argument("--width", type=int, default=640)
    ap.add_argument("--height", type=int, default=360)
    ap.add_argument("--conf", type=float, default=0.25)
    ap.add_argument("--iou", type=float, default=0.45)
    ap.add_argument("--max-det", type=int, default=60)
    ap.add_argument("--warmup", type=int, default=3)
    ap.add_argument("--print-every", type=int, default=10)
    ap.add_argument("--post", choices=("fast", "ref"), default="fast",
                    help="fast=候选锚点后处理；ref=traffic9_postprocess 原实现")
    ap.add_argument("--verify-post", type=int, default=0, metavar="N",
                    help="前 N 帧同时跑 ref 并逐项比对，不一致退出码 5")
    ap.add_argument("--resize-interp", choices=("linear", "area"), default="linear")
    ap.add_argument("--calibration-id", type=int, default=7301)
    ap.add_argument("--source-id", default="RK3568")
    ap.add_argument("--clock-domain-id", type=int, default=2)
    ap.add_argument("--start-frame-id", type=int, default=0)
    ap.add_argument("--control-port", type=int, default=0,
                    help="等待 PC 发 START 的 UDP 端口；0=不等待")
    return ap.parse_args(argv)


def _sigmoid(x: np.ndarray) -> np.ndarray:
    return 1.0 / (1.0 + np.exp(-np.clip(x, -60.0, 60.0)))


def _dfl_boxes(box: np.ndarray, idx: np.ndarray, imgsz: int,
               reg_max: int = 16,
               reg_weights: np.ndarray | None = None) -> np.ndarray:
    """只解码 idx 指向的锚点；返回网络坐标下的 xywh [M,4]。"""
    if idx.size == 0:
        return np.zeros((0, 4), np.float32)
    if reg_weights is None:
        reg_weights = np.arange(reg_max, dtype=np.float32)
    _, _, h, w = box.shape
    stride = float(imgsz) / h
    sel = box.reshape(1, 4, reg_max, h * w)[0][:, :, idx]
    sel = sel - sel.max(axis=1, keepdims=True)
    e = np.exp(sel)
    e /= e.sum(axis=1, keepdims=True)
    dist = (e * reg_weights.reshape(reg_max, 1)).sum(axis=1)
    ix = (idx % w).astype(np.float32)
    iy = (idx // w).astype(np.float32)
    cx = ix + 0.5
    cy = iy + 0.5
    x1 = (cx - dist[0]) * stride
    y1 = (cy - dist[1]) * stride
    x2 = (cx + dist[2]) * stride
    y2 = (cy + dist[3]) * stride
    return np.stack([(x1 + x2) / 2, (y1 + y2) / 2, x2 - x1, y2 - y1],
                    axis=1).astype(np.float32)


def _nms_candidates(xywh: np.ndarray, scores: np.ndarray, cls_ids: np.ndarray,
                    iou_thres: float, max_det: int,
                    max_wh: float) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    if scores.size == 0:
        return (np.zeros((0, 4), np.float32), np.zeros(0, np.float32),
                np.zeros(0, np.int64))
    xyxy = np.concatenate([xywh[:, :2] - xywh[:, 2:] / 2,
                           xywh[:, :2] + xywh[:, 2:] / 2], axis=1)
    xyxy_nms = xyxy + cls_ids.astype(np.float32)[:, None] * float(max_wh)
    order = np.argsort(-scores, kind="stable")
    xyxy, xyxy_nms = xyxy[order], xyxy_nms[order]
    scores, cls_ids = scores[order], cls_ids[order]
    out_i, out_s, out_c = [], [], []
    while len(xyxy_nms) and len(out_i) < max_det:
        cur = xyxy_nms[0]
        out_i.append(xyxy[0])
        out_s.append(scores[0])
        out_c.append(cls_ids[0])
        if len(xyxy_nms) == 1:
            break
        x1 = np.maximum(cur[0], xyxy_nms[1:, 0])
        y1 = np.maximum(cur[1], xyxy_nms[1:, 1])
        x2 = np.minimum(cur[2], xyxy_nms[1:, 2])
        y2 = np.minimum(cur[3], xyxy_nms[1:, 3])
        inter = np.clip(x2 - x1, 0, None) * np.clip(y2 - y1, 0, None)
        a0 = (cur[2] - cur[0]) * (cur[3] - cur[1])
        a1 = (xyxy_nms[1:, 2] - xyxy_nms[1:, 0]) * (xyxy_nms[1:, 3] - xyxy_nms[1:, 1])
        keep = (inter / (a0 + a1 - inter + 1e-9)) <= iou_thres
        keep = np.concatenate([[False], keep])
        xyxy, xyxy_nms = xyxy[keep], xyxy_nms[keep]
        scores, cls_ids = scores[keep], cls_ids[keep]
    return (np.array(out_i, np.float32), np.array(out_s, np.float32),
            np.array(out_c, np.int64))


def _postprocess_fast(outs, tp, imgsz: int, ratio: float, pad, orig_shape,
                      conf: float, iou: float, max_det: int,
                      multi_label: bool):
    """与 tp.postprocess 等价的快速路径：先过 logit 阈值，再只解码候选锚点。"""
    if 0.0 < conf < 1.0:
        logit_thr = math.log(conf / (1.0 - conf))
    else:
        logit_thr = -math.inf if conf <= 0.0 else math.inf
    reg_weights = np.arange(16, dtype=np.float32)
    names = tp.OUTPUT_NAMES
    all_boxes, all_scores, all_cls = [], [], []
    for si in (8, 16, 32):
        box = outs[names.index(f"box_s{si}")]
        cls = outs[names.index(f"cls_s{si}")]
        _, _, h, w = box.shape
        n = h * w
        logits = np.asarray(cls.reshape(1, -1, n)[0], dtype=np.float32)
        if multi_label:
            cand_cls, cand_idx = np.nonzero(logits > logit_thr)
            if cand_idx.size:
                scores = _sigmoid(logits[cand_cls, cand_idx]).astype(np.float32)
                uniq, inv = np.unique(cand_idx, return_inverse=True)
                boxes = _dfl_boxes(box, uniq, imgsz, 16, reg_weights)[inv]
                cids = cand_cls.astype(np.int64)
            else:
                boxes = np.zeros((0, 4), np.float32)
                scores = np.zeros(0, np.float32)
                cids = np.zeros(0, np.int64)
        else:
            best_cls = logits.argmax(axis=0)
            best = logits[best_cls, np.arange(n, dtype=np.int64)]
            idx = np.nonzero(best > logit_thr)[0]
            if idx.size:
                boxes = _dfl_boxes(box, idx, imgsz, 16, reg_weights)
                scores = _sigmoid(best[idx]).astype(np.float32)
                cids = best_cls[idx].astype(np.int64)
            else:
                boxes = np.zeros((0, 4), np.float32)
                scores = np.zeros(0, np.float32)
                cids = np.zeros(0, np.int64)
        all_boxes.append(boxes)
        all_scores.append(scores)
        all_cls.append(cids)
    boxes = np.concatenate(all_boxes, axis=0)
    scores = np.concatenate(all_scores, axis=0)
    cids = np.concatenate(all_cls, axis=0)
    boxes, scores, cids = _nms_candidates(boxes, scores, cids, iou, max_det,
                                          tp.MAX_WH)
    return tp.scale_boxes(boxes, ratio, pad, orig_shape), scores, cids


def _preprocess(frame: np.ndarray, canvas: np.ndarray, width: int, height: int,
                imgsz: int, interp: int) -> tuple[float, tuple[int, int]]:
    """一帧直接缩到 width x height 并写进预分配的方形画布。"""
    dw = (imgsz - width) // 2
    dh = (imgsz - height) // 2
    if dw < 0 or dh < 0:
        raise ValueError(f"输入 {width}x{height} 大于 imgsz={imgsz}")
    roi = canvas[dh:dh + height, dw:dw + width]
    if frame.shape[1] == width and frame.shape[0] == height:
        roi[:] = frame
    else:
        cv2.resize(frame, (width, height), dst=roi, interpolation=interp)
    return 1.0, (dw, dh)


def _parse_crop(text: str):
    text = (text or "").strip()
    if not text:
        return None
    if text.lower() in ("auto", "front"):
        return "auto"
    try:
        x, y, w, h = (int(v.strip()) for v in text.split(","))
    except (ValueError, TypeError) as exc:
        raise ValueError(f"--crop 必须是 x,y,w,h：{text!r}") from exc
    if x < 0 or y < 0 or w <= 0 or h <= 0:
        raise ValueError(f"--crop 必须是非负 x/y 和正 w/h：{text!r}")
    return x, y, w, h


def _same_detections(a, b) -> bool:
    if len(a[1]) != len(b[1]):
        return False
    for x, y in zip(a, b):
        if not np.allclose(x, y, atol=1e-3, rtol=1e-4):
            return False
    return True


def _send_jpeg(sock, dst, img: np.ndarray, fid: int, out_w: int, out_h: int,
               quality: int, max_bytes: int, label: str, k: int,
               print_every: int) -> int:
    if sock is None:
        return 0
    disp = img
    if disp.shape[1] != out_w or disp.shape[0] != out_h:
        disp = cv2.resize(disp, (out_w, out_h), interpolation=cv2.INTER_AREA)
    q = max(30, min(int(quality), 95))
    ok, jpg = cv2.imencode(".jpg", disp, [int(cv2.IMWRITE_JPEG_QUALITY), q])
    if ok and len(jpg) > max_bytes and q > 45:
        ok, jpg = cv2.imencode(".jpg", disp,
                               [int(cv2.IMWRITE_JPEG_QUALITY), 45])
    if ok and len(jpg) <= max_bytes:
        header = b"JPG0" + struct.pack("!IHH", int(fid), int(out_w), int(out_h))
        sock.sendto(header + jpg.tobytes(), dst)
        return int(len(jpg))
    if print_every and k % print_every == 0:
        size = len(jpg) if ok else -1
        print(f"frame {fid}: {label} JPEG skip size={size}", file=sys.stderr)
    return 0


def main(argv=None) -> int:
    args = parse_args(argv)
    sys.path.insert(0, str(Path(args.postprocess_dir)))
    import traffic9_postprocess as tp
    from traffic9_postprocess import to_uint8_nhwc_bgr
    from rknnlite.api import RKNNLite

    if args.width > args.imgsz or args.height > args.imgsz:
        print(f"width/height 不能大于 imgsz={args.imgsz}", file=sys.stderr)
        return 2

    rk = RKNNLite(verbose=False)
    if rk.load_rknn(args.model) != 0:
        print(f"load_rknn failed: {args.model}", file=sys.stderr)
        return 2
    if rk.init_runtime(core_mask=0) != 0:
        print("init_runtime failed; check rknpu driver", file=sys.stderr)
        return 2

    if bool(args.video) == (args.capture_device is not None):
        print("必须且只能指定 --video 或 --capture-device", file=sys.stderr)
        return 2
    if args.loop and args.capture_device is not None:
        print("--capture-device 不支持 --loop", file=sys.stderr)
        return 2
    try:
        crop = _parse_crop(args.crop)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    if bool(args.atlas_port) != bool(args.atlas_video_port):
        print("--atlas-port 与 --atlas-video-port 必须同时给出",
              file=sys.stderr)
        return 2
    atlas_enabled = bool(args.atlas_port)
    if atlas_enabled:
        if not (2 <= args.atlas_width <= 1920 and 2 <= args.atlas_height <= 1080):
            print("--atlas-width/height 超出 [2,1920]x[2,1080]", file=sys.stderr)
            return 2
        if args.atlas_width % 2 or args.atlas_height % 2:
            print("--atlas-width/height 必须是偶数（2x2 宫格）", file=sys.stderr)
            return 2
        ports = [args.port, args.video_port, args.atlas_port, args.atlas_video_port]
        active = [p for p in ports if p]
        if len(active) != len(set(active)):
            print(f"UDP 端口不能冲突：{ports}", file=sys.stderr)
            return 2

    capture = args.capture_device is not None
    pending_frame = None
    if capture:
        cap = cv2.VideoCapture(int(args.capture_device), cv2.CAP_V4L2)
        if not cap.isOpened():
            print(f"open capture device failed: /dev/video{args.capture_device}",
                  file=sys.stderr)
            return 2
        cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*args.capture_fourcc))
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, args.capture_width)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.capture_height)
        cap.set(cv2.CAP_PROP_FPS, args.capture_fps)
        cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
        actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
        actual_fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
        src_fps = actual_fps or float(args.capture_fps)
        print(f"[board] capture=/dev/video{args.capture_device} "
              f"fourcc={args.capture_fourcc} actual={actual_w}x{actual_h} "
              f"@{actual_fps:.2f}fps crop={crop}", flush=True)
        deadline = time.monotonic() + max(float(args.capture_timeout), 0.1)
        last_err = ""
        while time.monotonic() < deadline:
            try:
                ok, frame = cap.read()
            except cv2.error as exc:
                ok, frame = False, None
                last_err = str(exc).splitlines()[0]
            if ok and frame is not None:
                mean = float(frame.mean())
                if not args.allow_dark and mean < args.min_mean:
                    if args.print_every:
                        print(f"[board] 采集首帧偏黑 mean={mean:.2f}，"
                              f"可能是采集卡 No Signal，继续等待 ...", flush=True)
                    time.sleep(0.2)
                    continue
                print(f"[board] first capture frame {frame.shape[1]}x{frame.shape[0]} "
                      f"mean={mean:.2f}", flush=True)
                pending_frame = frame
                break
            time.sleep(0.05)
        if pending_frame is None:
            cap.release()
            print("HDMI 采集无有效帧：检查 FPGA HDMI OUT 是否接到采集卡、"
                  "FPGA 位流/输出是否运行；" + last_err, file=sys.stderr)
            return 2
    else:
        cap = cv2.VideoCapture(args.video)
        if not cap.isOpened():
            print(f"open video failed: {args.video}", file=sys.stderr)
            return 2
        actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
        actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
        src_fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
    W, H = int(args.width), int(args.height)
    target_fps = float(args.fps)
    pace = target_fps > 0
    spec = schema.load_spec()
    proto = DetectionProtocol(spec, source_id=args.source_id,
                              clock_domain_id=args.clock_domain_id,
                              calibration_id=args.calibration_id)
    proto_atlas = (DetectionProtocol(spec, source_id=args.source_id,
                                     clock_domain_id=args.clock_domain_id,
                                     calibration_id=args.calibration_id)
                   if atlas_enabled else None)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    dst = (args.host, int(args.port))
    video_sock = (socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                  if args.video_port else None)
    video_dst = (args.host, int(args.video_port)) if video_sock else None
    atlas_sock = (socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                  if atlas_enabled else None)
    atlas_dst = (args.host, int(args.atlas_port)) if atlas_sock else None
    atlas_video_sock = (socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                        if atlas_enabled else None)
    atlas_video_dst = ((args.host, int(args.atlas_video_port))
                       if atlas_video_sock else None)

    # NPU 首帧预热
    dummy = np.zeros((args.imgsz, args.imgsz, 3), np.uint8)
    for _ in range(max(0, args.warmup)):
        rk.inference(inputs=[to_uint8_nhwc_bgr(dummy)])

    if args.control_port:
        cs = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        cs.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        cs.bind(("0.0.0.0", int(args.control_port)))
        cs.settimeout(120.0)
        print(f"[board] WAIT_START udp :{args.control_port}", flush=True)
        try:
            data, addr = cs.recvfrom(64)
        except socket.timeout:
            print("wait START timeout", file=sys.stderr)
            return 4
        finally:
            cs.close()
        print(f"[board] START from {addr} {data!r}", flush=True)

    pace_txt = f"{target_fps:.2f}" if pace else "max"
    atlas_txt = (f" atlas={args.atlas_width}x{args.atlas_height}"
                 f"@{args.atlas_port}/{args.atlas_video_port}"
                 if atlas_enabled else "")
    print(f"[board] model={args.model} imgsz={args.imgsz} dst={dst[0]}:{dst[1]} "
          f"fps={pace_txt} frames={args.frames or 'inf'} post={args.post} "
          f"src_fps={src_fps:.2f}{atlas_txt}", flush=True)
    interp = cv2.INTER_LINEAR if args.resize_interp == "linear" else cv2.INTER_AREA
    canvas = np.full((args.imgsz, args.imgsz, 3), 114, np.uint8)
    t_frame_fps = src_fps if src_fps > 0 else (target_fps if pace else 15.0)

    def infer_stream(src, out_w, out_h, proto_obj, meta_sock, meta_dst,
                     v_sock, v_dst, quality, max_bytes, label, fid, verify):
        # 网络输入不超过 imgsz；输出/回传仍按 out_w x out_h，框按比例还原。
        scale = min(args.imgsz / out_w, args.imgsz / out_h, 1.0)
        infer_w = max(2, int(round(out_w * scale)))
        infer_h = max(2, int(round(out_h * scale)))
        t_pre0 = time.perf_counter()
        ratio, pad = _preprocess(src, canvas, infer_w, infer_h,
                                 args.imgsz, interp)
        pre_ms = (time.perf_counter() - t_pre0) * 1000.0
        t1 = time.perf_counter()
        outs = rk.inference(inputs=[to_uint8_nhwc_bgr(canvas)])
        inf_ms = (time.perf_counter() - t1) * 1000.0
        if outs is None:
            print(f"frame {k}: {label} inference returned None", file=sys.stderr)
            return None
        t2 = time.perf_counter()
        if args.post == "fast":
            boxes, scores, cls = _postprocess_fast(
                outs, tp, args.imgsz, ratio, pad, (infer_h, infer_w),
                args.conf, args.iou, args.max_det, False)
        else:
            boxes, scores, cls = tp.postprocess(
                outs, args.imgsz, ratio, pad, (infer_h, infer_w),
                conf_thres=args.conf, iou_thres=args.iou,
                max_det=args.max_det, multi_label=False)
        post_ms = (time.perf_counter() - t2) * 1000.0
        if verify and k < args.verify_post:
            ref = tp.postprocess(
                outs, args.imgsz, ratio, pad, (infer_h, infer_w),
                conf_thres=args.conf, iou_thres=args.iou,
                max_det=args.max_det, multi_label=False)
            if not _same_detections((boxes, scores, cls), ref):
                print(f"POST_VERIFY_FAIL frame={k} fast={len(scores)} "
                      f"ref={len(ref[1])}", file=sys.stderr)
                return None
        sx = out_w / infer_w
        sy = out_h / infer_h
        dets = [
            Detection(class_id=int(c), score=float(s),
                      bbox_xyxy=(float(b[0]) * sx, float(b[1]) * sy,
                                 float(b[2]) * sx, float(b[3]) * sy))
            for b, s, c in zip(boxes, scores, cls)
        ]
        bytes_jpg = 0
        fd = FrameDetections(frame_id=fid, width=out_w, height=out_h,
                             detections=dets, t_sec=k / t_frame_fps,
                             source="RK3568")
        buf = proto_obj.encode_object(fd)
        # 先发 OBJECT 再发 JPEG：PC 收到画面时同帧框已可查，避免启动期缺包。
        meta_sock.sendto(buf, meta_dst)
        bytes_jpg = _send_jpeg(v_sock, v_dst, src, fid, out_w, out_h,
                               quality, max_bytes, label, k, args.print_every)
        return len(dets), pre_ms, inf_ms, post_ms, bytes_jpg, len(buf)

    k = 0
    sent = 0
    t0 = time.monotonic()
    try:
        while True:
            if args.frames and k >= args.frames:
                break
            if pending_frame is not None:
                frame = pending_frame
                pending_frame = None
                ok = True
            else:
                try:
                    ok, frame = cap.read()
                except cv2.error as exc:
                    print(f"capture read failed: {exc}", file=sys.stderr)
                    ok, frame = False, None
            if not ok or frame is None:
                if args.loop:
                    cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                    continue
                break
            full_frame = frame
            if crop is not None:
                fh, fw = frame.shape[:2]
                if crop == "auto":
                    cx, cy, cw, ch = 0, 0, fw // 2, fh // 2
                else:
                    cx, cy, cw, ch = crop
                if cx + cw > fw or cy + ch > fh:
                    print(f"crop {crop} 超出帧 {fw}x{fh}", file=sys.stderr)
                    return 2
                frame = frame[cy:cy + ch, cx:cx + cw]
            fid = int(args.start_frame_id) + k
            res = infer_stream(frame, W, H, proto, sock, dst,
                               video_sock, video_dst, args.video_quality,
                               60_000, "front", fid, True)
            if res is None:
                return 3
            n_f, pre_f, inf_f, post_f, _jpg_f, bytes_f = res
            if atlas_enabled:
                res = infer_stream(full_frame, int(args.atlas_width),
                                   int(args.atlas_height), proto_atlas,
                                   atlas_sock, atlas_dst, atlas_video_sock,
                                   atlas_video_dst, args.atlas_quality,
                                   64_000, "atlas", fid, False)
                if res is None:
                    return 3
                n_a, pre_a, inf_a, post_a, _jpg_a, bytes_a = res
            sent += 1
            if args.print_every and (k % args.print_every == 0):
                total_f = pre_f + inf_f + post_f
                if atlas_enabled:
                    total_a = pre_a + inf_a + post_a
                    print(f"frame {fid:5d} nF={n_f:2d} preF={pre_f:4.1f} "
                          f"inferF={inf_f:5.1f} postF={post_f:4.1f} "
                          f"totalF={total_f:5.1f}ms bytesF={bytes_f} | "
                          f"nA={n_a:2d} preA={pre_a:4.1f} inferA={inf_a:5.1f} "
                          f"postA={post_a:4.1f} totalA={total_a:5.1f}ms "
                          f"bytesA={bytes_a}", flush=True)
                else:
                    print(f"frame {fid:5d} n={n_f:2d} pre={pre_f:4.1f} "
                          f"infer={inf_f:5.1f} post={post_f:4.1f} "
                          f"total={total_f:5.1f}ms bytes={bytes_f}", flush=True)
            k += 1
            if pace:
                target = t0 + k / target_fps
                while True:
                    gap = target - time.monotonic()
                    if gap <= 0:
                        break
                    time.sleep(min(gap, 0.05))
    finally:
        cap.release()
        try:
            rk.release()
        except Exception:
            pass
        sock.close()
        if video_sock is not None:
            video_sock.close()
        if atlas_sock is not None:
            atlas_sock.close()
        if atlas_video_sock is not None:
            atlas_video_sock.close()
    elapsed = max(time.monotonic() - t0, 1e-9)
    print(f"[board] sent {sent} frames in {elapsed:.2f}s "
          f"({sent/elapsed:.2f} fps)", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
