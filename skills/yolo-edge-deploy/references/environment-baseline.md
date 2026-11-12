# 环境与基线准备

## 依赖安装（PC 端）

```bash
pip install ultralytics                        # YOLO 官方
pip install onnx onnxruntime onnx-simplifier   # 模型转换与简化
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu118
pip install opencv-python                      # scripts/roi_infer.py 需要
```

> ⚠️ **不要装 `torch-pruning`**：本技能不提供剪枝（工具链与 ultralytics 8.4 不兼容，
> 实测剪枝量恒为 0），装了也用不上。详见 `compress-notes.md` 顶部说明。

## 获取原始模型

```python
from ultralytics import YOLO
model = YOLO(r"D:\ziguang\gen\yolov8n.pt")   # ✅ 用本地路径
# model = YOLO("yolov8n.pt")                 # ❌ 本机 GitHub 直连超时，自动下载会失败
```

> ⚠️ **本机实测**：`YOLO("yolov8n.pt")` 的自动下载会抛
> `ConnectionError ... Curl return value 28`（GitHub 直连超时）。
> 项目内已有可用权重：`gen/yolov8n.pt`、`yolo裁切方案/models/yolov8n.pt`。
> n/s/m/l/x 按目标算力选。

常见模型格式：

- `.pt`：PyTorch 原始模型；
- `.onnx`：跨平台中间格式（必经过渡层）；
- `.trt / .rknn / .xml+.bin / .param+.bin`：各端侧后端格式。

## 建立基线与验收线

1. 若用自定义数据集，先完成训练/微调，得到基线 `.pt`。
2. 记录基线 **mAP@0.5、单帧延迟、模型体积、显存占用**，作为后续每一步的对照。
3. 标注规范：`class x y w h` 归一化格式；**文件路径不要含中文**。

## 说明

若用户还没有模型与数据，先引导确认：目标硬件（决定模型档位 n/s/m/l/x）、目标延迟与精度要求（决定优化深度）、是否已有现场数据集（决定基线如何建立）。此步不确定会导致后续量化策略（PTQ vs QAT）与验收线选错。

> ⚠️ **不要建议剪枝比例**——本技能不提供剪枝，见 `compress-notes.md`。
