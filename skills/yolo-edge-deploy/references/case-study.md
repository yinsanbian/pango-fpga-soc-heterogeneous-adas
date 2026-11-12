# 工业案例、收益与踩坑清单

> 本文件里的**数值均来自原作者的硬件与数据集**，是参考量级，不是本机实测。
> 本项目写验收报告时请用 `kpi-dashboard` 技能记录自有实测口径。

## 工业级完整案例（原作者数据）

场景：汽车焊接螺母缺陷检测（缺失/偏位/变形），产线要求 ≤50ms/帧、精度 ≥99%，
硬件 Jetson Xavier NX，模型 YOLOv8-l。

| 优化阶段 | 推理速度 | 精度 | 是否达标 |
|---|---|---|---|
| 原始 FP32 | 180ms/帧 | 99.5% | 否 |
| INT8 量化（原作者另叠加了 20% 剪枝） | 110ms/帧 | 98.3% | 否 |
| + TensorRT INT8 | 35ms/帧 | 98.3% | 是 |
| + ROI 推理（只检焊接区） | 22ms/帧 | 98.2% | 是 |

最终：速度提升约 8.1 倍，精度损失约 1.3%。

> ⚠️ 该案例的"110ms"一步**同时用了剪枝**。本技能不提供剪枝，因此本技能可复现的
> 路径是从 FP32 直接进量化和 TensorRT——通常仍能拿到主要收益（案例中 180→22ms 的
> 大部分来自 TensorRT 与 ROI），但不要承诺复现表里的 110ms 一档。

## 预期收益汇总（原作者数据）

### YOLOv8n 量化前后对比

| 指标 | 原始模型 | 量化后 | 变化 |
|---|---|---|---|
| 模型大小 | ~25 MB | ~6.5 MB | ↓74% |
| Jetson Nano 延迟 | 92ms | 38ms | ↑2.4 倍 |
| 显存占用 | ~2GB | <500MB | ↓75% |
| mAP@0.5 (COCO) | 42.0% | 41.2% | ↓0.8% |

> 原表标题为"剪枝 + INT8 量化"，其参数下降 40% 主要来自剪枝。**只有量化时，
> 体积下降更明显（本机实测 FP32 12.7MB → INT8 3.37MB = 26.5%），
> 而参数量不变、mAP 变化需用现场数据实测。**

### 协同提示

多维叠加（INT8 + TensorRT + ROI）常可实现端到端 60% 以上乃至数倍提速。
三者互补：量化压缩存储并提速、TensorRT 做层融合与内核调优、ROI 直接减少计算量。

## 高频踩坑清单

| 序号 | 现象/问题 | 根因 | 解法 |
|---|---|---|---|
| 1 | 动态维度/动态 shape 报错 | 端侧不支持动态 shape | 导出 `dynamic=False`，固定 `imgsz=640`、静态 batch=1 |
| 2 | 量化后精度暴跌 | 校准集用了公开数据/数量不足 | 换现场真实数据 500~1000 张，增加量化轮数，必要时改 QAT |
| 3 | 推理无框 / 全是背景 | 预处理归一化与训练不一致 | 对齐 letterbox、归一化、BGR/RGB、缩放方式 |
| 4 | 模型转换失败 | opset 过高/含不支持算子 | 降到 opset 12/13，先 `onnxsim` 简化 |
| 5 | 速度仍慢 | 没用 INT8 | 必须走 INT8，FP16 只是过渡 |
| 6 | CPU 上跑 TensorRT 模型无效 | 硬件与模型不匹配 | CPU 用 OpenVINO，GPU 才用 TensorRT |
| 7 | 预处理拖慢整体 | 预处理占比 >50% | 预处理异步化、与推理并行 |
| 8 | 锚框不准/速度慢 | 沿用 COCO 锚框 | 现场标注 KMeans 聚类重训 |
| 9 | CPU 推理慢 | 未开 AVX-512 | 开启硬件指令集优化 |
| 10 | 多线程更慢 | 多线程抢占 GPU | 线程亲和/资源隔离，线程数=相机数 |
| 11 | 导出 ONNX TensorRT 解析失败 | 未指定 opset | 指定 opset 12/13 |
| 12 | 产线偶发停机 | 未处理超时/模糊图 | 加推理超时与异常兜底 |
| 13 | **`quantize_dynamic` 报 TypeError** | 传了不存在的参数（`optimize_model=` / `range_for_activation=`） | 只传 onnxruntime 签名里的参数；用 `scripts/quantize_onnx.py` |
| 14 | **ROI 框位置错乱/脚本崩溃** | 用 `box.xyxy[0] = [...]` 切片赋值（torch 2.x 抛 TypeError） | 整体重建张量；用 `scripts/roi_infer.py` |
| 15 | **想剪枝却发现工具全不可用** | torch-pruning 与 ultralytics 8.4 不兼容 | 别剪枝；走量化 + 换小档位模型，见 `compress-notes.md` |

## 从 0 到 1 一键命令串（已按本机实测校正）

```bash
# 1. 安装依赖（注意：不装 torch-pruning，本技能不做剪枝）
pip install ultralytics onnx onnxruntime onnx-simplifier opencv-python

# 2. 加载模型 —— 必须用本地权重，自动下载在本机会超时
python -c "from ultralytics import YOLO; YOLO(r'D:\ziguang\gen\yolov8n.pt')"

# 3. 导出静态 ONNX（端侧必须 dynamic=False）
#    model.export(format="onnx", opset=12, simplify=True, dynamic=False, imgsz=640)

# 4. INT8 量化（本技能脚本，已实测通过）
python scripts/quantize_onnx.py --model yolov8n.onnx

# 5. 按硬件转端侧模型
trtexec --onnx=yolov8n.onnx --saveEngine=yolov8n.trt --fp16        # Jetson/NVIDIA
rknn_toolkit convert --model yolov8n.onnx --output yolov8n.rknn --int8  # RK3588
onnx2ncnn yolov8n.onnx yolov8n.param yolov8n.bin                   # Android

# 6. ROI 推理（检测区域固定时，进一步提速且零精度损失）
python scripts/roi_infer.py --model yolov8n.pt --image img.jpg --roi 100,100,500,500
```
