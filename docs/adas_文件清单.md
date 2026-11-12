# 文件清单（MANIFEST）

本清单由 `tools\make_review_package.py` 自动生成。每个 `.py` 的「用途」一栏
是**从该文件自己的模块 docstring 里抽出来的第一行**，不是手写的 ——
手写的说明会随代码漂移，抽出来的不会。

* 收录文件：**122** 个 / **771 KB**
* 未收录：ONNX 模型、样片视频、虚拟环境、`__pycache__`、以及 `tools/` 下与本项目无关的脚本（见 F 组）

---

## A. 核心交付链路

_链路上真正在跑的东西（含标注工具与训练/评估）_

| 文件 | 大小 | 用途（取自模块 docstring） |
|---|---|---|
| `tools/adas_dash.py` | 35.1 KB | ADAS 仪表盘：左侧相机画面 + 右侧实时仪表盘。 |
| `tools/adas_demo.py` | 60.8 KB | adas_demo.py —— 在真实行车视频上生成「类 ADAS / 特斯拉风格」可视化（PC 侧 REPLAY 演示）。 |
| `tools/adas_live.py` | 22.3 KB | ADAS 实时可视化 —— 本地网页版：把视频拖进去就能看。 |
| `tools/adas_paths.py` | 3.6 KB | 跨平台路径解析 —— Windows 开发机与 Linux 部署机共用同一份代码。 |
| `tools/conf_calib.py` | 10.0 KB | 把"预期误差"标定出来，用来替换那个恒等于 1.000 的假置信度。 |
| `tools/lane_annotator.py` | 20.0 KB | A 路线 · 人工标注工具：在画面上点出**本车道中心线**，存成 jsonl。 |
| `tools/lane_byseg.py` | 4.7 KB | 按片段分列评估任意一组 ONNX 模型，用来做"同一条没见过的街"上的公平对比。 |
| `tools/lane_compare_models.py` | 6.2 KB | 同一段视频、同一批帧，两个模型并排画在同一幅画面上。 |
| `tools/lane_eval.py` | 9.7 KB | A 路线 · 评估：横向偏移误差 / 路径点误差 / 失效检出率 + 目视叠加验证。 |
| `tools/lane_generalize.py` | 4.9 KB | A 路线 · 换场景泛化测试。 |
| `tools/lane_labels.py` | 11.9 KB | A 路线 · 标签存储：人工标注的车道中心路径点。 |
| `tools/lane_loo.py` | 8.8 KB | A 路线 · 留一交叉验证（LOO）：在小标注量下给出**不掺水**的精度数字。 |
| `tools/lane_loso.py` | 7.4 KB | A 路线 · 留一片段交叉验证（LOSO）：**唯一能回答"它换条街还行不行"的实验**。 |
| `tools/lane_predict.py` | 13.0 KB | A 路线 · 在线推理：加载 lane_train.py 导出的 ONNX，给出本车道中心路径点。 |
| `tools/lane_train.py` | 24.5 KB | A 路线 · 训练：从画面直接回归**本车道中心线**的图像空间路径点 + 有效性。 |
| `tools/lane_train_subset.py` | 2.5 KB | 只用标签的一个时间子集训练 —— 用来重做"一条街 vs 八条街"的公平对比。 |
| `tools/requirements.txt` | 1.1 KB | 运行时依赖（opencv-python / numpy / onnxruntime / scipy） |
| `tools/run_adas_live.cmd` | 0.5 KB | — |
| `tools/run_adas_live.sh` | 2.3 KB | — |
| `tools/traffic9_postprocess.py` | 12.1 KB | traffic9 端侧后处理（RK3568 / CPU 侧）（**来自交通检测交付包，本项目直接 import**） |

## B. 诊断与证据脚本

_上面那些数字是怎么量出来的；也包括几次结构回退的机械替换脚本_

| 文件 | 大小 | 用途（取自模块 docstring） |
|---|---|---|
| `tools/_bench_ort.py` | 1.7 KB | 测：检测 + 车道两个 ONNX session 同时跑时，线程数该怎么配。 |
| `tools/_bench_ort2.py` | 2.1 KB | 测（用真实图像，不用全零）：检测 + 车道两个 session 同时跑时的线程配置。 |
| `tools/_check_seg_labels.py` | 1.1 KB | 看某段时间里人工标注都标在哪 —— 用来核对模型判断，也用来核对我自己以前的判断。 |
| `tools/_dbg_ann.py` | 6.2 KB | 诊断：核对人工标注到底标的是"本车道中心线"还是"别的东西"。 |
| `tools/_dbg_cal.py` | 1.6 KB | — |
| `tools/_dbg_cvtype.py` | 0.6 KB | — |
| `tools/_dbg_ev.py` | 1.2 KB | — |
| `tools/_dbg_ev2.py` | 1.8 KB | — |
| `tools/_dbg_ev3.py` | 1.2 KB | — |
| `tools/_dbg_ev4.py` | 1.0 KB | — |
| `tools/_dbg_ev5.py` | 0.8 KB | — |
| `tools/_dbg_ev6.py` | 1.3 KB | — |
| `tools/_dbg_gate.py` | 4.5 KB | 诊断：形状闸门到底卡在哪一条判据上。 |
| `tools/_dbg_geo.py` | 1.1 KB | — |
| `tools/_dbg_geo2.py` | 1.2 KB | — |
| `tools/_dbg_grid.py` | 1.9 KB | — |
| `tools/_dbg_ipm.py` | 5.0 KB | _dbg_ipm.py —— 逆透视（IPM）鸟瞰图 + 列剖面找峰 原型验证。 |
| `tools/_dbg_lane.py` | 1.7 KB | — |
| `tools/_dbg_lane2.py` | 3.3 KB | _dbg_lane2.py —— 车道二值化方案对比诊断（临时脚本）。 |
| `tools/_dbg_lane3.py` | 2.6 KB | — |
| `tools/_dbg_lane4.py` | 1.0 KB | — |
| `tools/_dbg_lbl.py` | 2.2 KB | 诊断 lane_labeler：把漆线掩码和首行 bootstrap 的搜索过程摊开看。 |
| `tools/_dbg_lbl2.py` | 2.6 KB | 诊断 2：复刻 track_lane 的 bootstrap 逐 dx 过程，看每侧到底找到了什么。 |
| `tools/_dbg_lbl3.py` | 2.2 KB | 诊断 3：追踪新版 track_lane 的逐带决策。 |
| `tools/_dbg_lbl4.py` | 2.6 KB | 诊断 v2：打印候选竖直线的数量、宽度扫描的最佳原始分与中位数。 |
| `tools/_dbg_lbl5.py` | 3.7 KB | 诊断 v3：先估地平线，把搜索限制在路面；再验证"漆线亮块的边界"是否就是车道线。 |
| `tools/_dbg_lbl6.py` | 5.1 KB | 诊断 v4：车身下方是路面！——利用"车道中心线必然穿过画面底边车底"这个约束。 |
| `tools/_dbg_lbl7.py` | 3.4 KB | 诊断 v5：**时间累积漆线证据**——单帧分不开的东西，多看几帧能不能分开。 |
| `tools/_dbg_runs.py` | 2.2 KB | 诊断 4：把漆线掩码的所有合法游程直接画回画面，用眼睛核对"哪个游程才是车道线"。 |
| `tools/_dbg_sob.py` | 2.5 KB | — |
| `tools/_diag_bias.py` | 3.2 KB | 符号偏差：模型是不是系统性地"把车道判在偏右"？ |
| `tools/_diag_calib.py` | 3.7 KB | 校验曲线 + 逐段真值轨迹：模型是不是"往中间缩"（shrinkage）？ |
| `tools/_diag_compare.py` | 2.6 KB | 把两份 LOSO 报告的诊断量并排打印，用来判断"补标有没有用"。 |
| `tools/_diag_conf.py` | 10.4 KB | 找出"运行时可算、且真的和误差相关"的量，用来替换那个恒等于 1.000 的假置信度。 |
| `tools/_diag_conf2.py` | 6.8 KB | 接 `_diag_conf.py`：把**模型自己输出的形状量**也拿去和误差做相关。 |
| `tools/_diag_left_byseg.py` | 3.6 KB | 按片段拆开看「真值明显偏左」那一小撮帧，回答一个具体问题： |
| `tools/_diag_prior.py` | 3.1 KB | 模型输出 vs 真值：是"在看画面"还是"在背先验"？ |
| `tools/_diag_shrink.py` | 3.0 KB | 收缩（shrinkage）还是"看不到"？—— 在真值为负的子集里单独看相关性与尺度。 |
| `tools/_probe_bins.py` | 3.8 KB | 在动手改网络之前，先把「分多少箱、箱子铺多宽」用真实标注定下来。 |
| `tools/_relabel_rows.py` | 1.9 KB | 按 V1 结构的固定采样行，重算所有标注的 u_norm。 |
| `tools/_restore_v3.py` | 13.0 KB | 把输出结构改回 V3（锚点 + 形状基，OUT_DIM=4）。 |
| `tools/_revert_v1.py` | 4.4 KB | 把输出结构从 V3（锚点+形状，OUT_DIM=4）回退到 V1（7 个自由 u 值，OUT_DIM=8）。 |
| `tools/_revert_v1b.py` | 3.6 KB | V1 回退第 2 步：损失函数、解码、评估三处。 |
| `tools/_revert_v1c.py` | 2.1 KB | V1 回退第 3 步：把模块头那段 V2/V3 的设计说明换成"试过并放弃"的结论块。 |
| `tools/_revert_v1d.py` | 2.4 KB | V1 回退第 4 步：lane_predict.py 与 lane_loo.py 的解码。 |
| `tools/_revert_v1e.py` | 2.2 KB | V1 回退第 5 步：lane_loo.py 的解码。 |
| `tools/_smoke_annot.py` | 3.2 KB | 冒烟测试：lane_labels 的拟合/采样 + lane_annotator 的 HTTP 接口。 |
| `tools/_smoke_annotator.py` | 1.1 KB | 冒烟：验证标注服务的"保存 -> 跳到下一个未标注帧"整条流程（复现前端行为）。 |
| `tools/_smoke_conf.py` | 6.0 KB | 冒烟：新置信度（标定预期误差）在几个已知帧上是否合理。 |
| `tools/_smoke_predict.py` | 1.0 KB | 冒烟：验证 lane_predict.LaneNetPredictor 能跑通导出的 ONNX。 |
| `tools/_smoke_v3.py` | 1.5 KB | V3（锚点 + 形状，直接回归）结构冒烟：输出维度、损失量级、梯度、形状重建精度。 |
| `tools/_stat_label_spread.py` | 2.5 KB | 按片段统计**人工标注本身**的横向位置分布。 |
| `tools/_stat_labels.py` | 2.7 KB | 看一下标注集现在长什么样：按片段分组统计。 |
| `tools/_stat_netfull.py` | 1.2 KB | — |
| `tools/_truth_left.py` | 3.5 KB | 从 LOSO 报告里挖出"真值明显偏左"的帧，并给出时间聚类。 |
| `tools/mine_negatives.py` | 11.6 KB | 自动挖掘"本车道不可用"的负样本 —— 给有效性头补上它从来没有过的反面例子。 |
| `tools/test_detector_on_dashcam.py` | 3.6 KB | 在真实行车视频上试跑 traffic9 9 类检测器（ONNXRuntime，CPU）。 |

## C. 转向 / 航向估计（**死路留档**）

_三次判死，过程与教训写在路线文档 §6.3。留档是为了别重走_

| 文件 | 大小 | 用途（取自模块 docstring） |
|---|---|---|
| `tools/ego_turn.py` | 30.8 KB | Ego turn verdict: straight / left / right, from far-field optical flow. |
| `tools/mark_intent.py` | 3.9 KB | 把"转弯/路口帧"的人工标注从 `src="human"` 改成 `src="human_intent"`。 |
| `tools/probe_lane_signal.py` | 16.1 KB | Probe: how usable is the existing opencv_lane (Hough + x(y) fit) pipeline on |
| `tools/probe_lane_signal2.py` | 19.2 KB | Probe #2: fix the two flaws probe #1 exposed, then find real turns. |
| `tools/rank_turn_candidates.py` | 7.7 KB | Rank candidate turn intervals from a probe signals.csv. |
| `tools/scan_lane_full.py` | 8.6 KB | 全片扫描：找出"本车道中心明显落在画面左半边"的路段（补标的候选）。 |
| `tools/turn_classify.py` | 8.2 KB | Turn class + annotation, and a sweep that validates it against the video. |
| `tools/turn_estimator.py` | 28.5 KB | Ego turn estimator: yaw rate from optical flow, tracked by a constant-rate |
| `tools/turn_test.py` | 6.5 KB | Discriminative test for the focus-of-expansion turn signal. |
| `tools/yaw_from_farfield.py` | 9.8 KB | Ego yaw rate from the FAR-FIELD flow field, using the y equation. |

## D. 部署与运行

_本地网页、WSL/Linux、标注服务_

| 文件 | 大小 | 用途（取自模块 docstring） |
|---|---|---|
| `tools/_grab_stream.py` | 1.2 KB | 从 /stream 抓几帧存盘，用于目视核对网页版渲染是否正常。 |
| `tools/_wsl_bootstrap.sh` | 2.3 KB | — |
| `tools/_wsl_e2e.sh` | 0.7 KB | — |
| `tools/_wsl_iobench.sh` | 1.3 KB | — |
| `tools/_wsl_probe.sh` | 0.7 KB | — |
| `tools/_wsl_render.sh` | 1.0 KB | — |
| `tools/run_annotator.ps1` | 2.2 KB | — |
| `tools/run_annotator_watchdog.py` | 1.6 KB | 看门狗：把标注服务跑起来，崩了就自动重启。 |

## E. 文档工具

_把章节追加进路线文档的补丁脚本，不是运行链路的一部分_

| 文件 | 大小 | 用途（取自模块 docstring） |
|---|---|---|
| `tools/_doc_patch_s10.py` | 10.3 KB | 往 D:\ziguang\docs\ADAS可视化实现路线.md 末尾追加 §10（假置信度的标定）。 |
| `tools/_doc_patch_s8.py` | 11.7 KB | 把 §8（参考项目核查 + 仪表盘实现）插入 ADAS 路线文档，并更新附录两处。 |
| `tools/_doc_patch_s9.py` | 7.0 KB | 在路线文档末尾追加 §9：Linux 部署与本地网页入口。 |
| `tools/_patch_dash_pipeline.py` | 10.7 KB | 把 adas_dash.py 的主循环抽成 class AdasPipeline，供 adas_live.py 复用。 |
| `tools/make_review_package.py` | 28.7 KB | 打包给外部 AI 评审的 zip（含详细清单 MANIFEST.md）。 |

## F. 与本项目无关

_属于另一个交付包（交通目标检测）的脚本，列出仅为说明 tools/ 里有它们_

| 文件 | 大小 | 用途（取自模块 docstring） |
|---|---|---|
| `tools/_dl.ps1` | 0.9 KB | — |
| `tools/_dl2.ps1` | 0.7 KB | — |
| `tools/_fmt.py` | 1.8 KB | — |
| `tools/_net.ps1` | 0.9 KB | — |
| `tools/_probe_env.py` | 0.5 KB | 环境勘察：A 路线（回归头）需要深度学习栈。逐个模块报可用性。 |
| `tools/_probe_gpu.py` | 1.4 KB | 环境勘察 2：GPU 可用性 + ResNet-18 预训练权重是否已缓存/可下载。 |
| `tools/add_lint_exception.py` | 1.1 KB | — |
| `tools/analyze_traffic_class_filter.py` | 3.8 KB | 过滤前影响面分析（只读）。 |
| `tools/audit_train_annotations.py` | 4.7 KB | Audit LabelMe annotations in 交通场景数据集/train before YOLO conversion. |
| `tools/check_and_preview_traffic_yolo.py` | 3.6 KB | 让 ultralytics 真正解析数据集（构建 labels cache），并渲染抽检图。 |
| `tools/filter_traffic_classes.py` | 11.6 KB | 按「只保留交通目标」重新生成 YOLO 标注，并重排类别索引。 |
| `tools/fix_neg_literal.py` | 0.4 KB | — |
| `tools/inspect_ambiguous_labels.py` | 2.9 KB | 检查 red/green/yellow/clock/toilet/skateboard 等存疑标签的真实形态。 |
| `tools/labelme2yolo_traffic.py` | 14.4 KB | 把 交通场景数据集/train 下的 LabelMe 标注转换为 YOLOv8 可训练的 txt 标注， |
| `tools/lane_labeler.py` | 19.4 KB | A 路线 · 自动标签生成器：从行车视频里抠出「车道中心」的轨迹，当回归目标。 |
| `tools/lane_labeler2.py` | 14.8 KB | A 路线 · 标签生成器 v2：竖直方向导数 + 期望宽度配对。 |
| `tools/preview_filtered_traffic_yolo.py` | 3.1 KB | 渲染过滤后的 train 抽检图，确认新类别框位置正确。 |
| `tools/rtl_lint.py` | 6.0 KB | tools/rtl_lint.py —— rtl/ 提交前静态自检（verilog-lint-gate 的自动化部分） |
| `tools/strip_bom.py` | 0.8 KB | — |
| `tools/verify_filtered_traffic_yolo.py` | 9.0 KB | 独立校验：交通过滤后的数据集是否符合预期。 |
| `tools/verify_traffic_yolo.py` | 4.6 KB | 独立校验 traffic_yolo 数据集：文件配对、坐标范围、标注可反解、与源 json 逐框比对。 |
| `tools/看模型图.py` | 7.0 KB | 在 PyCharm 里打开模型权重图（v1.1 及任意 .pt / .onnx） |

---

## G. 文档

| zip 内路径 | 原路径 | 说明 |
|---|---|---|
| `docs/ADAS_ROADMAP_zh.md` | `docs\ADAS可视化实现路线.md` | **主文档，1318 行**。§4.8 = 车道回归这条线的全部实测与失败记录；§6.3 = 航向估计三次判死；§8 = 参考项目核查；§9 = 交付形态；§10 = 假置信度的标定 |
| `docs/ADAS_LINUX_DEPLOY_zh.md` | `docs\ADAS_Linux部署说明.md` | Linux/WSL 部署、依赖、三个坑、跨机访问 |

## H. 证据（JSON）

| zip 内路径 | 说明 |
|---|---|
| `evidence/loso_v3final.json` | **最终评估口径**：296 帧、留一整个片段的交叉验证（LOSO）、9 折，每折每帧的 `pred_offset_px / human_offset_px / offset_err_px / points_mae_px / conf / shape_ok`。路线文档 §4.8 所有段级数字都出自这里 |
| `evidence/loso_v3.json` | 同一结构的上一次运行，用于核对复现性（41.3 vs 41.5 px） |
| `evidence/loso4_280frames.json` | 补标 16 帧**之前**的 280 帧版本，用于「补标有没有用」的同帧对照 |
| `evidence/loso_cls_64bin.json` | **否定结果**：64 箱分类头（mean 47.2 px，比回归头差 25%）。不要重复这条路 |
| `evidence/byseg_only1_vs_v3.json` | 公平对照：只用 1 个片段 22 帧训练 vs 用 8 个片段 280 帧训练，在同一批没见过的帧上的逐段误差（71.4 → 39.7 px） |
| `evidence/train_log_v9.json` | 最终交付模型（`_lane_runs/v9/lanenet.onnx`）的训练曲线与 val 指标。⚠ val 是时间切分，落在 OOD 片段上，**不能当泛化指标** |
| `evidence/conf_calib.json` | 置信度标定系数 + 十分位标定表 + 逐折 rho |
| `evidence/conf_shape.json` | 296 帧上「模型自报形状量」与「实际误差」的相关（置信度标定的数据来源） |
| `evidence/conf_features.json` | 运行时特征（漆线覆盖率 / 亮度 / 梯度 / 车辆数）与误差的相关 —— **全部无效**，这是三条被否掉的路的证据 |
| `evidence/gate_diag.json` | 563 帧逐帧记录形状闸门三条判据的取值，用来定位「折返度判据把 100% 的帧全拒了」 |
| `evidence/adas_dash_summary.json` | 最终样片（959 帧 / 1920×720）的实测：FPS、各段耗时、车道有效率 |
| `labels/labels.jsonl` | **人工标注集**：296 帧，8 个路段。每行 `{frame, t, abc, pts, n_pts, img, src, u_norm, v_norm}`。`abc` 是 `x(y)=ay²+by+c`；`u_norm/v_norm` 是归一化后的采样行坐标 |

## I. 截图

| zip 内路径 | 说明 |
|---|---|
| `shots/01_dashboard_card_t371.jpg` | **最终形态的仪表盘**：左 1280 相机画面 + 右 640 六张卡。车道卡第三行是标定后的「预期误差 ±19 px / 高 / 置信度 0.870」 |
| `shots/02_overlay_t386.jpg` | 路面叠加：橙色中心线 + 目标框 + 趋势箭头 |
| `shots/03_left_curve_t338.jpg` | **左偏工况**：模型输出 −196.7 px，真值 −220.2 px。橙色中心线在画面左下、几乎是横的 |
| `shots/04_1street_vs_8streets.jpg` | 公平对照的视频截帧：品红 = 1 街 22 帧训的，橙 = 8 街 280 帧训的 |
| `shots/05_label_vs_pred_bridge.jpg` | 评估出图：绿 = 人工标注，橙 = 网络预测（高架桥下，误差 +16.3 px） |
| `shots/06_annotation_convention.jpg` | **标注口径取证**：等距线 + 人工点。这张是右转路口帧，人工点越过 +3.50 m 等距线 —— 路线文档 §4.8 末节讨论的就是这件事 |
| `shots/07_intersection_no_laneline.jpg` | 路口证据帧：斑马线、红绿灯，**一根车道线都没有**。这就是「车道几何是 fair-weather 信号」的物证 |

## J. 没放进包里的东西（清单在此，需要时可单独传）

| 文件 | 大小 / 说明 |
|---|---|
| `tools/_lane_runs/v9/lanenet.onnx` | 46.09 MB —— **最终交付模型**。ResNet-18 骨干，输入 3 帧堆叠 320×180，输出 4 维 |
| `tools/_lane_runs/only1/lanenet.onnx` | 46.09 MB —— 对照模型（1 街 22 帧） |
| `tools/_lane_runs/loso_cls/lanenet.onnx` | 46.09 MB —— 否定结果模型（64 箱分类头） |
| `traffic_yolo_deploy/deploy_rk3568/models/traffic9_split6_640.onnx` | 12.08 MB —— 目标检测器（9 类交通目标），来自另一个交付包。**后处理权威实现 `traffic9_postprocess.py` 已收录在本包里** |
| `docs/adas_dashboard_363-395s.mp4` | 77.66 MB —— 最终样片（1920×720 / 32 s） |
| `docs/adas_demo_v9_lanenet_363-395s.mp4` | 65.69 MB —— 纯叠加版样片（1280×720） |
| `docs/adas_lane_1street_vs_8streets_480-530s.mp4` | 89.47 MB —— 公平对照视频 |
| 行车视频源 | 289 MB —— 1280×720 / 15960 帧 / 532.5 s / 29.97 fps，城市行车记录仪（第三方素材，不在包内） |

## K. 复现路径（最短）

```bash
# 1) 依赖（4 条）
pip install -r tools/requirements.txt

# 2) 解析跨平台路径（模型在哪、仓库根在哪）
python tools/adas_paths.py --print all

# 3) 批量出片（1920x720 仪表盘）
python tools/adas_dash.py --video <行车视频> \
    --onnx <traffic9_split6_640.onnx> --lane-onnx <v9/lanenet.onnx> \
    --out out/dash --start 363 --duration 32 --write-video --dump-json

# 4) 本地网页（浏览器里拖视频进去就能看）
python tools/adas_live.py --onnx <检测 onnx> --lane-onnx <车道 onnx> --open

# 5) 重新评估（需要标签 + 视频；约 20 分钟 / 9 折）
python tools/lane_loso.py --labels labels/labels.jsonl --video <行车视频> \
    --out out/loso --epochs 40

# 6) 重新标定置信度
python tools/conf_calib.py --compare
```

⚠ **`adas_live.py` 与 `adas_dash.py` 共用同一个 `AdasPipeline`**（定义在 `adas_dash.py` 里）。这是刻意的：否则「网页里看到的」与「导出的样片」会悄悄分叉。
