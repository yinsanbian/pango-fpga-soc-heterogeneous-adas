# 模型量化

## 量化路线与对比

路线：**FP32 → FP16 → INT8**。

| 方式 | 精度损失 | 收益 | 适用 |
|---|---|---|---|
| FP16 | 基本无损 | 体积减半、小幅提速 | 快速无损起步 |
| INT8 | 需校准/微调 | 体积 ↓4 倍、速度 ×3~5、功耗大降 | 端侧必备 |

以 YOLOv8n 为例：原模型约 25MB，INT8 后约 6MB，体积减少约 75%；在支持 INT8 的硬件（TensorRT、Hexagon DSP）上速度提升 2~4 倍。

量化本质是线性映射：`Q = round(X/S + Z)`，还原 `X' = S × (Q - Z)`，其中 S（缩放因子）、Z（零点）由校准阶段统计得出。

## PTQ 与 QAT 选择

- **PTQ（训练后量化）**：无需重训，少量校准数据即可，先用来快速验证可行性。
- **QAT（量化感知训练）**：训练中插入伪量化节点模拟舍入误差，精度要求严苛时启用。
- **决策闸门**：PTQ 后 mAP 下降 **<1%** 直接上线；否则回退做 QAT。

## 校准集要求（关键）

- 必须用**现场真实数据**（如产线零部件图像），**不能用 COCO 等公开数据集**，否则量化范围估计不准、精度暴跌。
- 数量 **500~1000 张**即可覆盖主要检测目标。
- 校准后用少量现场数据微调，精度可恢复到原模型 99% 以上。

## ONNX Runtime 动态量化（CPU 快速验证）

运行 `scripts/quantize_onnx.py`：

```bash
python scripts/quantize_onnx.py --model yolov8l.onnx
```

参考代码（无需校准集，适合 CPU 快速验证）。
**下面这段是本机实测可运行的版本**，或直接用 `scripts/quantize_onnx.py`：

```python
from ultralytics import YOLO
from onnxruntime.quantization import quantize_dynamic, QuantType

# 1. 导出 FP32 ONNX（用本地权重，自动下载在本机会超时）
model = YOLO(r"D:\ziguang\gen\yolov8n.pt")
model.export(format="onnx", imgsz=640, opset=12)

# 2. 动态量化为 INT8
quantize_dynamic(
    "yolov8n.onnx", "yolov8n_int8.onnx",
    weight_type=QuantType.QUInt8,
    per_channel=False,   # 工业场景关闭逐通道，提升速度
)
```

> ⚠️ **勘误（两个参数，照抄必崩）**：来源文章的这段代码里还传了
> `optimize_model=True` 和 `range_for_activation=QuantType.QUInt8`，
> 但 onnxruntime **1.29.0** 的 `quantize_dynamic` **两个参数都没有**。
> 它只接受这 10 个：
> `model_input, model_output, op_types_to_quantize, per_channel, reduce_range,
> weight_type, nodes_to_quantize, nodes_to_exclude, use_external_data_format, extra_options`。
> 上例是本机跑通的版本；`scripts/quantize_onnx.py` 同。
> 本机实测结果：yolov8n FP32 12.7MB → INT8 **3.37MB（26.5%）**，
> 输入/输出签名与 FP32 完全一致。逐条勘误见 `provenance.md`。

## TensorRT INT8 量化（GPU 生产路径）

```python
import tensorrt as trt

logger = trt.Logger(trt.Logger.WARNING)
builder = trt.Builder(logger)
network = builder.create_network(1 << int(trt.NetworkDefinitionCreationFlag.EXPLICIT_BATCH))
parser = trt.OnnxParser(network, logger)
with open("yolov8l.onnx", "rb") as f:
    parser.parse(f.read())

config = builder.create_builder_config()
config.max_workspace_size = 1 << 30          # 1GB，按硬件调整
config.set_flag(trt.BuilderFlag.INT8)        # 开启 INT8
config.int8_calibrator = MyCalibrator(        # 现场数据校准器
    calib_data_path="industrial_calib/", batch_size=8, cache_file="yolov8l_calib.cache")

engine = builder.build_serialized_network(network, config)
with open("yolov8l_int8.trt", "wb") as f:
    f.write(engine)
```

TensorRT 还会自动做层融合（Conv+BN+激活合一）与内核自动调优。

## 精度补偿技巧

- 对**输出层、注意力机制层不量化**，保留 FP32，可有效降低精度损失。
- 量化后用少量现场数据微调。

## 量化红线

- YOLO 的 **Upsample、NMS、Detect 头锚点计算**等不支持原生量化，交给后端（TensorRT/OpenVINO）处理或单独冻结。
- **固定输入尺寸**（如 640×640）与静态 shape，便于编译优化。
- 校准时 Conv+BN 先融合，量化效率更高。
