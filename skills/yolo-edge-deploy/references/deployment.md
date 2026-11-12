# 硬件加速与部署

## GPU / TensorRT（工业首选）

- 核心：ONNX → Engine，INT8 量化 + 层融合 + 内核调优。
- GPU 选型建议：
  - 边缘：Jetson Xavier NX（约 21 TOPS，产线视觉）；Jetson AGX Orin（约 275 TOPS，高分辨率/多目标）。
  - 工控机：RTX 3060/3070（性价比，支持 TensorRT）。
  - 云端：A100（大规模批量推理）。

```python
# OpenVINO CPU 读取参考
from openvino.runtime import Core
ie = Core()
model = ie.read_model(model="yolov8l_openvino_model/yolov8l.xml")
compiled = ie.compile_model(model=model, device_name="CPU")
```

## CPU / OpenVINO（无 GPU 场景）

Intel CPU 上利用 AVX-512 指令集，提速约 1.5~2 倍；跨 CPU/核显/FPGA，部署轻量。**CPU 场景务必用 OpenVINO 而非 TensorRT**（TensorRT 模型在 CPU 上无效）。

## 嵌入式 RK3588 / RKNN（低成本）

内置 NPU（约 6 TOPS），用官方 `rknn-toolkit2` 转 RKNN，结合现场校准集做 INT8（精度损失 ≤2%），开启 NPU 硬件流水线减少传输延迟。

## FPGA（超高实时性）

要求 ≤10ms/帧（如高速分拣线）时使用，必须 INT8，将卷积/池化映射为硬件并行逻辑，工具链用 Xilinx Vitis AI；开发成本高，适合大规模量产。

> ⚠️ **本项目用的是紫光同创 PGL50H（盘古50K），不适用 Vitis AI** —— Vitis AI 只支持
> Xilinx 器件，其 DPU IP 无法移植。PGL50H 上没有现成 CNN 推理 IP：需要在 **PDS**
> 里手写 RTL 实现卷积阵列，或用 PGL50H 的 APM（乘法器，共 **84** 个）搭 MAC 阵列。
> 具体走法见 `pangu-50k-dev` 技能（PDS 工具链 / 引脚约束 / 资源预算：LUT 42800、
> FF 64200、DRM18K 134、APM 84）；权重导入见 `int8-weight-export` 技能。
> **把 YOLO 放到 PGL50H 上的现实路径是"重写成 RTL"，不是"工具链一键转换"** ——
> 排期按前者估工。

## Android / NCNN

把 `.param` + `.bin` 推到手机，用 Java/Kotlin 调 NCNN 示例运行。

## ⚠️ 勘误：某原文的"导出加 `--dynamic`"是错的

有一篇来源文章在"部署优化建议"里写 **"导出 ONNX 时添加 `--dynamic` 选项"**。
**这条不要采纳**，它和端侧部署的硬约束直接冲突：

- 端侧后端（RKNN / TensorRT / NCNN）普遍**不支持动态 shape**，动态导出会在转换或
  首次推理时报动态维度错误；
- 本技能 `conversion.md` 与 `case-study.md` 踩坑 #1 都要求 `dynamic=False` + 固定 `imgsz` +
  静态 `batch=1`；
- 连该文章自己前面也强调"下采样层通道必须匹配、结构要规整"，动态 shape 与之矛盾。

**统一口径**：端侧导出 = `dynamic=False`、固定 `imgsz`、静态 batch=1。
逐条勘误与复现方式见 `provenance.md`。

## 各平台速度参考（YOLOv8n INT8）

| 平台 | 后端 | 参考 FPS |
|---|---|---|
| Jetson Orin/Nano | TensorRT | 100~300 |
| RK3588 | RKNN | 80~150 |
| Android 手机 | NCNN | 30~60 |

数值为实测/示例参考，不同模型档位与分辨率下差异较大。
