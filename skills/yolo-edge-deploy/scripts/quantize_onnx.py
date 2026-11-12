#!/usr/bin/env python3
"""ONNX 动态 INT8 量化（快速验证，无需校准集，适合 CPU）。

工业要点：
- 这是快速验证路径；生产 GPU 路径走 TensorRT INT8 + 现场数据校准器（见 references/quantization.md）；
- 校准集必须用现场真实数据（500~1000 张），不能 COCO 等公开数据集；
- PTQ 后 mAP 下降 <1% 直接上线，否则回退 QAT。

用法:
  python quantize_onnx.py --model yolov8l.onnx
  python quantize_onnx.py --model yolov8l.onnx --output yolov8l_int8.onnx
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from onnxruntime.quantization import QuantType, quantize_dynamic


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="ONNX Runtime 动态 INT8 量化")
    parser.add_argument("--model", required=True, help="输入 FP32 ONNX 路径")
    parser.add_argument("--output", default=None, help="输出 INT8 ONNX 路径（默认 输入名_int8.onnx）")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    src = Path(args.model)
    if not src.is_file():
        sys.exit(f"找不到输入模型: {src}")
    if src.suffix.lower() != ".onnx":
        sys.exit(f"输入必须是 .onnx（当前 {src.suffix}）；请先用 model.export(format='onnx') 导出")

    dst = Path(args.output) if args.output else src.with_name(f"{src.stem}_int8.onnx")

    # ⚠️ 参数必须与当前 onnxruntime 的签名一致。
    # 本机 onnxruntime 1.29.0 的 quantize_dynamic 只接受：
    #   model_input, model_output, op_types_to_quantize, per_channel, reduce_range,
    #   weight_type, nodes_to_quantize, nodes_to_exclude, use_external_data_format, extra_options
    # 网上流传的 optimize_model= / range_for_activation= **均不存在**，传了直接 TypeError。
    quantize_dynamic(
        str(src), str(dst),
        weight_type=QuantType.QUInt8,
        per_channel=False,   # 工业场景关闭逐通道，提升速度
    )

    if not dst.is_file():
        sys.exit("量化未产生输出文件，请检查 onnxruntime 日志")

    print(f"量化完成: {src} -> {dst}")
    print(f"体积: {src.stat().st_size:,} -> {dst.stat().st_size:,} bytes "
          f"({100.0 * dst.stat().st_size / src.stat().st_size:.1f}%)")
    print("注意：动态量化只压权重、不动激活，精度影响需用**现场数据**实测 mAP 后再上线。")


if __name__ == "__main__":
    main()


if __name__ == "__main__":
    main()
