---
name: yolo-edge-deploy
description: "将 YOLO（v5/v8/v9/v10）模型做端侧部署与算力优化的完整工作流：量化（FP16/INT8、PTQ/QAT）、格式转换（ONNX/TensorRT/RKNN/NCNN/OpenVINO）、硬件加速部署（Jetson/RK3588/Android/ARM Linux）与推理策略调优（ROI、动态锚框、NMS、多线程）。当用户需要把 YOLO 部署到边缘/端侧设备、提升端侧推理速度、压缩模型体积、降低显存占用、解决端侧精度暴跌或转换失败，或提出量化、模型转换、ROI 推理、算力优化、部署调优等需求时使用。注意：本技能在本机环境下**不提供结构化剪枝**（工具链与 ultralytics 8.4 不兼容，see references/provenance.md），遇到剪枝需求应直接说明不可用并给出替代路径。"
---

# YOLO 端侧部署与算力优化

## Overview

指导将 YOLO（v5/v8/v9/v10）部署到 Jetson、RK3588、Android、ARM Linux 等边缘设备，走完「训练基线 → 量化 → 转换 → 硬件部署 → 推理调优」全流程，目标：**精度损失 ≤3%，推理提速 2~5 倍**，兼顾实时性、稳定性、低成本。

## 核心准则（全程强制）

- 以 **mAP@0.5** 为唯一监控指标，硬性通过线：**不低于原始模型（基线）的 95%**；关键缺陷场景建议 ≥99%。
- 量化后 mAP 下降 **<1%** 直接上线；超过则回退做 QAT。
- 任一环节 mAP 跌破基线 95% 即回退（量化后 → 改 QAT）。
- 每步记录基线对照四指标：**mAP@0.5、单帧延迟、模型体积、显存占用**。
- 校准集**必须用现场真实数据**，禁止用 COCO 等公开数据集。

## 不支持的能力（不要承诺，不要尝试）

**本技能不提供结构化剪枝，也不提供知识蒸馏的可执行实现。** 原因已实测确认，不是"没写"：

- `YOLO.prune()` / `YOLO.distill()` 在 ultralytics **8.4.147** 上**不存在**；
- 剪枝工具链与 ultralytics 8.4 模型不兼容（依赖图只识别 1/64 个可剪组，任何配置下剪枝量均为 0）；
- 原文曾推荐的 `torchpruner` 包在 PyPI 上不存在，其代码不可运行。

遇到剪枝/蒸馏需求时，**直接告知用户本技能不支持**，并给出替代路径：
① 只做量化 + 转换 + ROI（本技能已覆盖，通常能拿到主要收益）；
② 模型侧改小档位（yolov8l → yolov8s/n）重训；
③ 若必须剪枝，需另建独立环境（不同 ultralytics/torch-pruning 版本组合），
   不要在本项目环境里改依赖版本。逐条证据见 `references/provenance.md`。

## 总流程

```
原始模型(.pt)
  → ① 训练/微调（自定义数据集，建立基线 mAP）
  → ② 模型量化（FP32 → FP16 → INT8）
  → ③ 模型转换（统一到 ONNX → TensorRT/RKNN/OpenVINO/NCNN/MNN）
  → ④ 硬件加速部署（GPU/CPU/嵌入式）
  → ⑤ 推理策略与部署调优（ROI、NMS、多线程）
  ↺ 任一环节 mAP 跌破基线 95% 即回退（改 QAT / 换方案）
```

## 环境实测备注（本机已验证，先读再动手）

> 2026-09 在**本机**（Python 3.13 / torch 2.14.0+cpu / ultralytics 8.4.147 /
> onnxruntime 1.29.0）逐项实测。换环境请重测 —— 这些是**版本相关的硬事实**。

| 项 | 实测结论 | 影响 |
|---|---|---|
| **剪枝** | ❌ **不可用**：`YOLO.prune()` / `DetectionModel.prune` 在 8.4.147 上不存在；torch-pruning 1.5.3 与 1.6.0 **都没有** `strategy` 子模块（原文那套 API 在任何版本都不存在）；两版都对 ultralytics 8.4 只识别 1/64 个可剪组，剪枝量恒为 0 | **已删除剪枝脚本**；见上节"不支持的能力" |
| **量化** | ✅ `scripts/quantize_onnx.py` 端到端实测通过：yolov8n FP32 12.7MB → INT8 **3.37MB（26.5%）**，输入/输出签名与 FP32 完全一致，两侧都能推理 | 可直接用 |
| **ROI 推理** | ✅ `scripts/roi_infer.py` 五个边界用例全通过（有目标/无目标/子区域/越界/图不存在）；坐标映射经"同图全图推理"独立交叉验证，逐框一致 | 可直接用 |
| `YOLO("yolov8n.pt")` 自动下载 | ❌ 本机 GitHub 直连超时（`ConnectionError ... Curl return value 28`）。项目内已有 `gen/yolov8n.pt`、`yolo裁切方案/models/yolov8n.pt` | **显式传本地权重路径**，别依赖自动下载 |
| **原文 API 断言** | 本技能正文源自 4 篇公开文章，其中多处 API 已被本机证伪（`model.prune`、`model.distill`、`torchpruner`、`range_for_activation`、`optimize_model`、导出 `--dynamic`） | 抄代码前先看 **`references/provenance.md` 的勘误表** |

**已修掉的 bug**（两个脚本各一处，均经实测复现后修正）：
- `roi_infer.py`：`box.xyxy[0] = [...]` 在 torch 2.x 抛 `TypeError`，**只要检出目标就崩**。
  已改为整体重建张量，并补 ROI 越界检查与"未检测到目标"分支。
- `quantize_onnx.py`：原代码传了 `optimize_model=True`，而 onnxruntime 1.29 的
  `quantize_dynamic` **没有** 该参数（**直接 TypeError**）。已移除，并补上输入校验与体积报告。

（这两处都是靠真图 + 本地权重跑端到端才抓到的；只读代码看不出来。）

## Workflow Decision Tree

按用户所处阶段路由到对应 reference；每完成一步，把四指标对照基线汇报给用户。

- **从零开始 / 还没有基线模型** → 读 `references/environment-baseline.md`：装依赖、获取/训练模型、记录基线四指标。标注规范 `class x y w h` 归一化，文件路径不含中文。
- **模型太大 / 太慢 / 要压缩** → 走量化路线：读 `references/quantization.md` + 跑 `scripts/quantize_onnx.py`（实测 12.7MB → 3.37MB）。**不要走剪枝**——本技能不支持，见上文说明。若体积仍不达标，建议换小档位模型重训。
- **要量化 / 显存不够 / 再提速** → 读 `references/quantization.md`：FP16 过渡 → INT8；PTQ 快速验证（`scripts/quantize_onnx.py`），mAP 掉 <1% 上线，否则 QAT。校准集必须用现场真实数据 500~1000 张。
- **要换格式 / 部署到具体硬件** → 读 `references/conversion.md`：先导出静态 ONNX（opset 12 或 13、dynamic=False、simplify），再按硬件转 TensorRT/RKNN/OpenVINO/NCNN。
- **已转换完要部署 / 加速** → 读 `references/deployment.md`：GPU=TensorRT、CPU=OpenVINO、RK3588=RKNN、Android=NCNN，勿混用。
- **延迟不达标 / 要零精度损失提速** → 读 `references/inference-tuning.md`：ROI 推理（`scripts/roi_infer.py`）、动态锚框、NMS 优化、多线程调度、静态 batch=1、AVX-512。
- **遇到报错 / 精度暴跌 / 转换失败 / 速度没提升** → 逐项对照 `references/case-study.md` 的 15 条高频踩坑清单。
- **要参考收益 / 完整工业案例** → 读 `references/case-study.md`。
- **用户明确要求剪枝 / 蒸馏** → 读 `references/compress-notes.md` 了解原理，然后**如实告知不可用**并给替代路径（见上文「不支持的能力」）。

## 关键闸门（先判断再动手）

- PTQ 后 mAP 下降 <1% → 上线；否则 → 回退 QAT。
- CPU 场景用 OpenVINO，GPU 场景才用 TensorRT；CPU 上跑 TensorRT 模型无效。
- 端侧导出必须 `dynamic=False` + 固定 `imgsz` + 静态 batch=1，否则报动态 shape 错误。
- 用户要求"剪枝/蒸馏"→ **不要尝试**，按上文「不支持的能力」如实说明并给替代路径。

## Resources

### scripts/（两个脚本均已端到端实测通过，可直接跑）

- `quantize_onnx.py` — ONNX Runtime 动态 INT8 量化（CPU 快速验证路径）
- `roi_infer.py` — ROI 区域推理 + 坐标映射回原图

### references/

- `environment-baseline.md` — 依赖安装、模型获取、基线与验收线
- `quantization.md` — 量化路线、PTQ/QAT 决策、校准集要求、TensorRT INT8、红线
- `conversion.md` — ONNX 静态导出、简化、各后端转换命令、格式优先级
- `deployment.md` — 各硬件平台部署方式与选型
- `inference-tuning.md` — ROI、动态锚框、NMS、多线程、静态 batch、指令集
- `case-study.md` — 工业案例、收益汇总、15 条踩坑清单、一键命令串
- `compress-notes.md` — 剪枝/蒸馏的**背景原理**（仅作知识参考，**本技能不提供可执行实现**）
- **`provenance.md` — 原文出处 + 逐条勘误；照抄任何代码前必读**

> 本技能正文与脚本的来源是 4 篇公开文章（见 `provenance.md` 的链接表）。
> 原文性能数字是**作者硬件/数据**上的示例，不是本机实测；写验收报告时请用
> `kpi-dashboard` 技能记录自有实测口径。

所有数值（FPS、ms、压缩率、精度）均来自实测/示例数据，不同硬件与数据集差异较大，落地时以自身基线实测为准，向用户说明这一前提。
