# 05 · 车道线检测 RTL 设计说明（ALG-09）

> 来源：CSDN《【保姆级教程】基于OpenCV实现实时道路车道检测》
> <https://blog.csdn.net/qq_42589613/article/details/142173526>
> 目标平台：**盘古50K / PGL50H-6IFBG484**（紫光同创 Logos 系列，PDS 工具链）

---

## 一、原文算法 → 硬件模块 一一映射

| # | 原文（OpenCV） | 硬件模块 | 目录 | 目标 ID |
|---|---|---|---|---|
| 1 | `cv2.cvtColor(img, COLOR_BGR2GRAY)` | `rgb2gray` | `rtl/preprocess/` | ALG-02 |
| 2 | `cv2.GaussianBlur(gray,(5,5),0)` | `gauss5x5`（可分离） | `rtl/preprocess/` | ALG-03 |
| 3 | `cv2.Canny(blur,50,150)` — Sobel 梯度 | `sobel_3x3` | `rtl/preprocess/` | ALG-06 |
| 4 | `cv2.Canny` — 非极大值抑制 | `canny_nms` | `rtl/lane/` | ALG-06 |
| 5 | `cv2.Canny` — 双阈值 + 滞后 | `canny_hyst` | `rtl/lane/` | ALG-06 |
| 6 | `region_selection()` 梯形掩膜 | `roi_mask` | `rtl/lane/` | ALG-09 |
| 7 | `cv2.HoughLinesP(...)` | `hough_acc` | `rtl/lane/` | ALG-09 |
| 8 | `average_slope_intercept()` + `pixel_points()` | `lane_fit` | `rtl/lane/` | ALG-09 |
| 9 | `draw_lane_lines()` | `lane_draw` | `rtl/lane/` | ALG-09 |
| — | （基础设施） | `line_buffer_rows` / `line_buffer_3x3` | `rtl/preprocess/` | ALG-01 |
| — | （基础设施） | `div_seq` / `cdc_cfg_sync` | `rtl/common/` | ALG-07 / SYS-01 |

**原文参数逐条对齐**（全部保留原值，不做"顺手优化"）：

| 原文参数 | 值 | 硬件实现 |
|---|---|---|
| `kernel_size` | 5 | 5×5 二项式核（σ≈1.0 近似 OpenCV 反算的 σ=1.1） |
| `low_t` / `high_t` | 50 / 150 | `cfg_thr_low` / `cfg_thr_high` 寄存器，**同值可用**（幅值同为 L1 口径） |
| ROI 顶点 | (0.1W,0.95H)(0.4W,0.6H)(0.6W,0.6H)(0.9W,0.95H) | `roi_mask` 的 localparam，逐行线性插值 |
| `rho` / `theta` | 1 / π/180 | ρ 步长 1 个降采样像素；θ 64 档（见 §三 取舍说明） |
| `threshold` | 20 | `lane_fit` 的 `P_VOTE_THRESH`（按降采样折算） |
| `minLineLength` / `maxLineGap` | 20 / 500 | 隐含在票数门限中 |
| `y1` / `y2` | `H` / `0.6H` | `lane_fit` 的 `P_Y1` / `P_Y2` |
| `color` / `thickness` | [255,0,0] / 12 | `cfg_color` / `cfg_thickness` 寄存器 |

---

## 二、顶层结构

```
                    ┌──────────── 检测流（当前帧，来自 OV5640）────────────┐
 s_axis (RGB888) ──▶ rgb2gray ──▶ gauss5x5 ──▶ sobel_3x3 ──▶ canny_nms ──▶ canny_hyst
                                                                              │
                                                              roi_mask ◀──────┘
                                                                 │
                                                        hough_acc（降采样投票 + 逐θ峰值）
                                                                 │ 64×(θ,ρ,votes)
                                                          lane_fit（加权拟合 + 端点求解）
                                                                 │ 帧间保持
                    ┌──────────── 显示流（DDR3 读回，滞后 1 帧）────┼──────────┐
 v_axis (RGB888) ──▶──────────────────────────────────── lane_draw ◀┘          │
                                                                │              │
                                                            m_axis (RGB888 + 车道线)
                                                                              │
 cfg_clk 域 ──▶ cdc_cfg_sync ──▶ 配置字 ───────────────────────────────────────┘
                cdc_cfg_sync ◀── 状态回读（vote_drop / 车道端点）
```

### ★ 两条独立视频流（关键架构决策）

原文是**逐帧**算法：第 N 帧的霍夫统计必须整帧结束才有结果。流式硬件里这意味着
车道线参数只能在**下一帧**生效。本设计不额外加帧缓存，而是复用平台上已有的
**DDR3 乒乓帧缓存**：

| 流 | 来源 | 用途 |
|---|---|---|
| `s_axis_*` | 相机当前帧 | 只做检测，输出车道参数 |
| `v_axis_*` | DDR3 读回的上一帧 | 叠加当前参数后送 HDMI |

结果：**结构性 1 帧延迟**（33 ms @30fps），画面**无撕裂**（参数帧间保持，
只在 `lane_fit` 拟合完成时整体更新）。这 1 帧延迟在 §七 KPI 中单独列出，
不与流水线拍数混为一谈。

---

## 三、定点参数表（唯一来源：代码头注释 + `model/ref_lane_detect.py` 的 `Q` 字典）

| 信号 | 格式 | 位宽 | 范围/说明 |
|---|---|---|---|
| 灰度 Y | 8.0 | 8 | `(77R+150G+29B+128)>>8` |
| 高斯水平/垂和 | 12.0 / 16.0 | 12 / 16 | 255×16 / 4080×16 |
| Gx, Gy | 补码 | 11 有符号 | ±1020 |
| 幅值 \|G\|₁ | 12.0 | 12 | ≤2040（L1，与 OpenCV Canny 默认一致） |
| ρ | 降采样像素单位 | 11 有符号 | \|ρ\| ≤ 0.708·(XD+YD) |
| 斜率 m | Q8.8 | 16 有符号 | \|m\| ≤ 1（θ∈[45°,135°) 的必然结果） |
| 截距 c | Q8.8 | 32 有符号 | 降采样单位，再 ×DECIM 折算全分辨率 |
| 车道端点 x | 整数像素 | 12 有符号 | 钳位到 [0, W−1] |

### 参数取舍（必须向评审核实的三处）

| 取舍 | 原文 | 本设计 | 理由 |
|---|---|---|---|
| **高斯核** | σ=1.1 真高斯 | 二项式 `[1 4 6 4 1]/16` | 只需加/移位，**不占 DSP**；实测 PSNR **51.01 dB**（判据 >40） |
| **θ 范围与分档** | 0~180°，180 档 | **45°~135°，64 档**（1.40625°） | 前视相机车道线法线必落此区间；由此 \|ρ\| 有界 → 累加器可做到 576 Kbit。**代价**：\|m\|≤1，即只能表示与水平线夹角 ≥45° 的线（车道线满足） |
| **投票降采样** | 全分辨率 | **按行 ÷4**（x 量化、y 抽样、行内按列去重） | 全分辨率累加器需 3.07 Mbit（占 PGL50H BRAM 全部）。降采样后 576 Kbit。⭐ 只对 **y** 抽样、x 只用 `>>2` 量化而**不做 %4 过滤** —— 否则 1 像素宽的 Canny 细线会被再砍掉 3/4 的票 |

---

## 四、延迟登记（供 SYS-04 端到端核算）

| 模块 | LATENCY | 备注 |
|---|---|---|
| `rgb2gray` | 3 拍 | |
| `line_buffer_rows` | 1 拍 + (N−1) 行 | 零计数器实现 |
| `line_buffer_3x3` | 2 拍 + 2 行 | 中心坐标已扣 1 行 1 列 |
| `gauss5x5` | 5 拍 + 2 行 | h 级 4 拍坐标链 + v 级 1 拍 + 算术 2 拍 |
| `sobel_3x3` | 4 拍 + 2 行 | |
| `canny_nms` | 3 拍 + 4 行 | |
| `canny_hyst` | 3 拍 + 6 行 | |
| `roi_mask` | 1 拍 | |
| `hough_acc` | **帧内批处理** | 投票随 ROI 进行；SCAN 74 K 拍 + CLEAR 74 K 拍在消隐/非 ROI 区完成 |
| `lane_fit` | 8 次顺序除法 ≈ 272 拍/帧 | |
| `lane_draw` | 1 拍 | 参数来自上一帧 |

**检测链总延迟** ≈ **14 行 + 22 拍**
→ 1080P@30（pclk 74.25 MHz）：`14×2200 + 22 ≈ 30,822` 拍 ≈ **0.42 ms**；
→ 720P@30（pclk 37.125 MHz）：`14×1650 + 22 ≈ 23,122` 拍 ≈ **0.62 ms**。

**参数到画面生效**：+1 帧（结构性，见 §二）。

---

## 五、时序预算（每帧，1080P）

| 阶段 | 拍数 | 可用窗口 | 余量 |
|---|---|---|---|
| 投票（burst 128 拍/点） | 最坏 ~870 K | ROI 378 行 × 2200 = 831 K | **紧张**，忙时丢弃（`o_vote_drop` 可读） |
| SCAN（64×1154） | 73,856 | SOF 到 ROI 首行 = 747 行 = 1.64 M | 22× |
| CLEAR（73728） | 73,728 | 同上 | 22× |

典型场景（边缘点占 ROI 面积 8%）：投票点 ≈ 1800，≈230 K 拍，占用 28%。

---

## 六、资源预估（**待 PDS 综合报告回填**）

| 资源 | 预估 | 主要来源 |
|---|---|---|
| BRAM | **≈576 Kbit**（约 32 块 18K） | 霍夫累加器 64×1152×8 |
| 行缓存 | ≈180 Kbit（可由 LUTRAM/BRAM 混合） | gauss×4(12b) + sobel×2(9b) + nms×2(15b) + hyst×2(2b) |
| DSP | **2** | hough 的 `x·cos`、`y·sin` |
| LUT | 估 6~9 K | 算术流水 + 扫描 FSM |
| FF | 估 5~7 K | 各级流水 + 累加和 |

> PGL50H 公开数据（ALINX P50 核心板手册）：LUT5 **42,800** / 等效 LUT4 51,360 /
> FF **64,200** / 分布式 RAM 544 Kb。BSRAM 与 DSP 的准确数量需以 PDS
> 数据手册或综合报告为准，**本表 BSRAM 占比一栏暂空**，M6 前必须回填。

---

## 七、文件清单与复现步骤

```
rtl/common/div_seq.v              有符号顺序除法器（32 拍）
rtl/common/cdc_cfg_sync.v         多 bit 配置跨域（toggle 握手 + 两级同步）
rtl/preprocess/line_buffer_rows.v 通用 N 行缓存（★ 零计数器）
rtl/preprocess/line_buffer_3x3.v  3×3 窗口
rtl/preprocess/rgb2gray.v         ALG-02
rtl/preprocess/gauss5x5.v         ALG-03
rtl/preprocess/sobel_3x3.v        ALG-06
rtl/lane/canny_nms.v              ALG-06
rtl/lane/canny_hyst.v             ALG-06
rtl/lane/roi_mask.v               ALG-09
rtl/lane/hough_acc.v              ALG-09（核心）
rtl/lane/lane_fit.v               ALG-09
rtl/lane/lane_draw.v              ALG-09
rtl/lane/lane_detect_top.v        顶层
rtl/lane_detect.f                 综合/仿真文件清单（★ 顺序即依赖顺序）
constr/lane_detect.fdc            PDS 时序约束（增量）
model/ref_lane_detect.py          ①②④ 参考模型 + 金标准导出
sim/sim.f                         仿真文件清单（★ TB 必须置顶）
sim/tb/tb_lane_pipeline.v         逐拍比对
sim/tb/tb_hough_fit.v             霍夫定向测试
tools/rtl_lint.py                 静态自检
reports/lint_lane_detect.md       Lint 报告
reports/sim_lane_detect.md        仿真验证报告
reports/metrics_lane_detect.md    定点精度指标
```

```powershell
$env:Path = "C:\iverilog\bin;$env:Path"     # 本机已装 iverilog 14.0
cd D:\ziguang

python model\ref_lane_detect.py             # ① ② ④
iverilog -g2005 -o sim_pipe.out -f sim\sim.f
vvp sim_pipe.out                            # ⑤ 期望 PASS (mismatch = 0)
python tools\rtl_lint.py                    # 门禁自检，期望 0 issue
```

**接入 PDS 工程**：把 `rtl/` 与 `constr/lane_detect.fdc` 加入官方例程
`10_HDMI_DDR3_OV5640_test`，在 `hdmi_ddr_ov5640_top.v` 中：
`fram_buf` 的写口 → `lane_detect_top.s_axis_*`；`fram_buf` 的读口 → `v_axis_*`；
`m_axis_*` → `sync_vg` 前的 RGB 通路。

---

## 八、已知限制与整改计划

| # | 限制 | 影响 | 计划 |
|---|---|---|---|
| 1 | **霍夫峰值统计量偏弱**：θ 方向能量铺开，加权平均被噪声分档拉偏 | 车道端点误差大（详见 `reports/sim_lane_detect.md` §四） | **P0**：扫描时改用"±2 bin 滑窗票数和"取峰 |
| 2 | ρ 量化 = 4 像素 | 截距精度上限 ±4 px | P1：抛物线亚 bin 插值 |
| 3 | `canny_hyst` 的滞后是**单次 3×3 邻域连接**，非 OpenCV 的全图 8 连通迭代传播 | 极弱边缘可能丢失 | 车道线是连续长边，实测边缘主体完整；如需严格一致可加行内 1 遍传播 |
| 4 | `lane_draw` 的线宽判据 `\|x−x(y)\| ≤ (t+1)/2` 与 `cv2.line` 有 ±1 像素舍入差 | 视觉无差异 | 不修 |
| 5 | 忙时丢弃投票 | 极端复杂场景票数下降 | 已有 `o_vote_drop` 可观测量；必要时加大 ROI 行降采样精度 |
| 6 | θ 只覆盖 45°~135° | 无法表示近水平线 | 车道场景下是优点（抑制噪声），已写入 §三 取舍表 |
