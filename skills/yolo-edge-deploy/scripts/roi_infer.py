#!/usr/bin/env python3
"""ROI 区域推理：只裁剪感兴趣区域推理，再把框坐标映射回原图（零精度损失提速）。

工业要点：
- 适用于检测范围固定的场景（如传送带中间区域），示例：全图 35ms → ROI 22ms（Jetson Xavier NX）；
- ROI 推理尺寸小于全图，速度更快；坐标映射必须加回 ROI 偏移，否则框位置错乱。

用法:
  python roi_infer.py --model yolov8l_int8.pt --image path/to/img.jpg
  python roi_infer.py --model yolov8l_int8.pt --image img.jpg --roi 100,100,500,500 --imgsz 400
"""
from __future__ import annotations

import argparse

import cv2
from ultralytics import YOLO


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="ROI 区域推理 + 坐标映射回原图")
    parser.add_argument("--model", default="yolov8l_int8.pt", help="模型权重")
    parser.add_argument("--image", required=True, help="图片路径")
    parser.add_argument("--roi", default="100,100,500,500", help="ROI 区域 x1,y1,x2,y2")
    parser.add_argument("--imgsz", type=int, default=400, help="ROI 推理尺寸（小于全图更快）")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    x1, y1, x2, y2 = map(int, args.roi.split(","))

    model = YOLO(args.model)
    img = cv2.imread(args.image)
    if img is None:
        raise FileNotFoundError(f"无法读取图片: {args.image}")

    h, w = img.shape[:2]
    if not (0 <= x1 < x2 <= w and 0 <= y1 < y2 <= h):
        raise ValueError(f"ROI ({x1},{y1},{x2},{y2}) 超出图片范围 {w}x{h}")

    roi_img = img[y1:y2, x1:x2]                     # 裁剪 ROI
    results = model(roi_img, imgsz=args.imgsz)      # 推理尺寸变小

    # 坐标映射回原图。
    # ⚠️ 必须整体重建张量：形如 `boxes.xyxy[0] = [..]` 的切片赋值在 torch 2.x 上
    #    会抛 `TypeError: can't assign a list to a torch.FloatTensor`（本机实测复现），
    #    旧版脚本正死在这一行 —— 只要检出目标就报错退出。
    boxes = results[0].boxes
    if len(boxes) == 0:
        print("未检测到目标")
        return

    data = boxes.data.clone()                       # (n, 6) = xyxy + conf + cls
    data[:, 0] += x1
    data[:, 2] += x1
    data[:, 1] += y1
    data[:, 3] += y1

    print(f"检测到 {len(data)} 个目标（坐标已映射回原图）:")
    for row in data.tolist():
        bx1, by1, bx2, by2, conf, cls_id = row
        print("  [%.0f, %.0f, %.0f, %.0f]  conf=%.3f  cls=%d"
              % (bx1, by1, bx2, by2, conf, int(cls_id)))


if __name__ == "__main__":
    main()
