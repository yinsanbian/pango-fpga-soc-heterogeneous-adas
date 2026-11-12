# 原文出处与勘误台账

本技能的正文、脚本与数值**不是凭空写的**，来源是下面四篇公开文章。
本文件做两件事：① 标注每部分内容出自哪篇；② 记录**原文里被本机实测证伪的地方**。

> **重要边界**：原文的数值（FPS、ms、压缩率、精度）是**作者在其硬件与数据集上的示例**，
> 不是本机实测值。本技能只把它们当"参考量级"，落地以自身基线为准。
> 而下面「勘误」栏目里的结论，全部是**在本机跑出来的**，可复现。

## 一、四篇原文

| 编号 | 标题 | 链接 | 取源状态 |
|---|---|---|---|
| A1 | YOLO 模型端侧硬件部署 从0到1 完整实战流程 | https://jishuzhan.net/article/2033112326203834370 | ✅ 已取全文 |
| A2 | YOLO 算力优化四大维度：模型压缩 + 硬件加速 + 推理策略 + 部署调优（工业级方案详解） | https://juejin.cn/post/7596478936386502698 | ✅ 已取全文 |
| A3 | YOLOv8模型压缩技术：剪枝与量化实战 | https://blog.csdn.net/weixin_32480007/article/details/156460781 | ✅ 已取全文 |
| A4 | YOLOv8n结构化剪枝实战：原理、实现与部署优化 | https://blog.csdn.net/weixin_33624741/article/details/165563780 | ✅ 换参数后取到（首次直连返回 HTTP 521） |

> A4 备注：`blog.csdn.net/weixin_33624741/article/details/165563780` 首次访问返回
> **HTTP 521（源站错误）**，加 `?spm=...` 查询参数后 200。CSDN 的 521 是源站侧临时故障，
> 遇到时加参数或稍后重试即可。

## 二、内容溯源对照

| 本技能位置 | 主要来源 | 具体对应 |
|---|---|---|
| `references/environment-baseline.md` | A1 §二/三 | 依赖安装清单、`.pt/.onnx/.trt/.rknn` 格式说明、n/s/m/l/x 档位选择 |
| `references/compress-notes.md` | A3 §剪枝 + A4 §2/§3 | **仅背景原理**（无代码）：BN-γ 与 L1 范数两种判据、依赖图必要性、分层比例 `backbone 0.4 / neck 0.3 / head 0.2`、敏感度分析、剪后微调 LR=1/10 且 10~30 epoch |
| ↑ 蒸馏部分 | A2 §1.3 + A4 §4.1 | 同系列师生模型、软损失权重争议（见勘误 5） |
| ↑ 剪枝效果数值 | A4 §1 + A3 收益表 | "40% 剪枝 → 体积↓35%、速度↑1.8×、mAP↓2.3pt"；"25MB→6.5MB、参数量↓40%、Jetson Nano 92→38ms、mAP 42.0→41.2" |
| `references/quantization.md` | A2 §1.1 + A3 §量化 | `Q = round(X/S + Z)`、PTQ/QAT 决策闸门、校准集 500~1000 张真实数据、输出层/注意力层不量化、ONNX Runtime 动态量化代码、TensorRT INT8 校准器 |
| `references/conversion.md` | A1 §六 + A2 §4.1 | 静态 ONNX 导出、`onnxsim`、格式优先级 `TensorRT Engine > RKNN > OpenVINO IR > ONNX > PyTorch`、四条后端转换命令 |
| `references/deployment.md` | A2 §2 + A1 §七 | TensorRT/OpenVINO/RKNN/FPGA/Android 分平台方案、Jetson/RK3588/Android 速度表 |
| `references/inference-tuning.md` | A2 §3 + §4.3 | ROI 推理三步、动态锚框 KMeans 聚类、NMS 三种优化、框架优先级、静态 batch、AVX-512、多线程调度与预处理异步化 |
| `references/case-study.md` | A2 案例 + A3/A4 收益 | 汽车焊接螺母案例四阶段表（180→110→35→22ms）、收益汇总表、"四维协同"提法 |
| ↑ 15 条踩坑清单 | A2 十条 + A1 五条 + A3 注意事项 | 合并去重，并**替换**了 3 条剪枝相关条目为实测踩坑（`quantize_dynamic` 参数错、ROI 切片赋值崩、剪枝工具不可用） |
| ~~`scripts/prune_yolo.py`~~ | A3 剪枝代码 | **已删除**（实测任何配置下剪枝量恒为 0，保留会造成"照着跑"的误导）。原理移至 `compress-notes.md`，但**不再提供可执行文件** |
| `scripts/quantize_onnx.py` | A2 §1.1 代码 | `quantize_dynamic(weight_type=QuantType.QUInt8, per_channel=False)` —— **已删掉原文的 `optimize_model=True`**（该参数在 onnxruntime 1.29 不存在，见勘误 10） |
| `scripts/roi_infer.py` | A2 §3.1 代码 | ROI 裁剪 → 小尺寸推理 → 坐标映射回原图；`imgsz=400`（坐标映射写法已改，见勘误 11） |
| `SKILL.md` 核心准则 | A2 前言 + A3 最佳实践 | "精度损失 ≤3%、提速 2~5 倍"；"mAP 不低于基线 95%" |

## 三、勘误：原文中被本机实测证伪的地方

> 环境：Python 3.13 / torch 2.14.0+cpu / ultralytics **8.4.147** /
> onnxruntime **1.29.0** / torch-pruning **1.6.0**。复现脚本见仓库 `tmp/verify_*.py`。

| # | 原文断言 | 本机实测 | 处理 |
|---|---|---|---|
| 1 | **A1**：`model.prune(amount=0.5)` 可直接剪枝 | ❌ `hasattr(YOLO, "prune") == False`（8.4.147 无此方法） | **剪枝能力整体移除**，见 `compress-notes.md` |
| 2 | **A1**：`model.distill(teacher="yolov8m.pt", data="coco8.yaml")` | ❌ `hasattr(YOLO, "distill") == False`，**该方法不存在** | 蒸馏仅留原理说明，不提供可执行实现 |
| 3 | **A3**：剪枝用 `tp.strategy.L1Strategy()` + `tp.prune_conv` + `DG.get_pruning_plan()` | ❌ 这三个 API 在 torch-pruning **1.5.3 与 1.6.0 都不存在**（实测两版都没有 `strategy` 子模块）；且两版的新高层 API 对 ultralytics 8.4 模型**剪枝量恒为 0**（依赖图只认出 1/64 层） | **`scripts/prune_yolo.py` 已删除**；原理移入 `compress-notes.md` |
| 4 | **A4**：`pip install torchpruner` 后用 `from torchpruner import StructuredPruner` | ❌ **PyPI 上无 `torchpruner` 包**（`ModuleNotFoundError`）。A4 用的参数名 `importance_criteria` 与真实库 `torch-pruning` 的 `importance=` 也不一致 | 该段代码**不可照抄**，已随剪枝能力一并移除 |
| 5 | **A2**：软损失权重 **0.7**、硬损失 0.3；**A3/A4**：`loss = 0.7*detection_loss + 0.3*KL`（硬 0.7/软 0.3） | 两篇**互相矛盾** | 不是错误而是口径分歧，已在 `compress-notes.md` 并存标注"两种口径均有实践，以自身实验为准" |
| 6 | **A2**：`quantize_dynamic(..., range_for_activation=QuantType.QUInt8)` | ❌ onnxruntime **1.29.0** 的 `quantize_dynamic` **没有** `range_for_activation`（签名仅 10 个参数） | `quantize_onnx.py` 已不传该参数 |
| 7 | **A4** §4.2：端侧部署建议"导出 ONNX 时添加 `--dynamic` 选项" | ❌ 与端侧静态 shape 硬约束冲突（会导致动态维度报错） | 已在 `deployment.md` 单开一节驳回，统一为"`dynamic=False`" |
| 8 | **A1**：导出用 `opset=13`；**A2/A3**：用 `opset=12` | 均可（实测 `export(opset=...)` 被接受），差异仅在算子集覆盖 | 统一表述为"**12 或 13**，转换失败先降级" |
| 9 | **A2**：`model.export(format="onnx", imgsz=640, opset=12, dynamic=False, batch=1)` | ✅ `export()` 走 `**kwargs` 透传，`opset/half/int8/dynamic` 均被接受 | 无需修改 |
| **10** | **A2**：`quantize_dynamic(..., optimize_model=True, ...)` | ❌ onnxruntime 1.29 的 `quantize_dynamic` **同样没有** `optimize_model` 参数 → **直接 `TypeError`**（本技能脚本原先照抄了这行，实测验尸确认） | **已从 `quantize_onnx.py` 删除**；这是"照原文抄会崩"的第 2 个量化参数 |
| **11** | **A2**：ROI 坐标映射用 `box.xyxy[0] = [x1, y1, x2, y2]` | ❌ torch 2.x 抛 `TypeError: can't assign a list to a torch.FloatTensor`；**只要检出目标就崩**，ROI 功能完全不可用（实测验尸：真实图片 + 本地权重） | **已改为整体重建张量**（`boxes.data.clone()` 后整体加偏移），并补 ROI 越界检查与无目标分支；5 个边界用例全通过 |

## 四、使用纪律

1. **先跑勘误，再抄代码**。四篇原文都写于较早的库版本，直接复制粘贴有概率踩上表 1/2/3/4/6/7/10/11。
2. 原文给出的性能数字是**他人的硬件与数据**上的结果，不要写进你的验收报告当自有实测值。
   本项目的实测口径见 `kpi-dashboard` 技能。
3. 涉及本项目硬件（紫光同创 PGL50H）时，`deployment.md` 的 Vitis AI 一节**不适用**，
   见该节说明与 `pangu-50k-dev` 技能。
4. **剪枝相关的一切已从本技能移除**（脚本删除、仅留原理）。不要再尝试在本环境恢复它，
   也不要升降 torch-pruning / ultralytics 版本来"凑通"——会破坏其他项目依赖。
5. 若你手上有更新版的原文或作者勘误，请回填本表并注明日期 —— 本表的价值在于**可追溯**。
