# 06 · 多 Agent 协作任务书

> 编写时间：2026-09-22
> 适用：把本工程剩余工作拆成可并行的工作流，交给多个 agent 协作推进
> 前置阅读：`docs/04-工作流程.md`（怎么干）· `docs/02-目标分类.md`（做到什么程度）

---

## 〇、怎么用这份文档（**先读这一节，否则会踩别人的坑**）

### 给每个 agent 的固定开场

```
你在 D:\ziguang（夜瞳异构 FPGA 工程）。
先读 docs/06-多Agent协作任务书.md 全文，再读你负责工作流的「输入」一栏列出的文件。
只修改「文件所有权」表中属于你的文件。不属于你的，需要改动时在报告里提出，不要动手。
完成后必须跑通「统一门禁」（§六）并贴出原始输出。
```

### 五条硬规则

| # | 规则 | 理由 |
|---|---|---|
| 1 | **只改自己名下的文件** | 多 agent 并发写同一文件 = 静默丢改动。所有权表见 §6.1 |
| 2 | **改 RTL 必须先跑仿真门禁** | 本工程已有一次"改了但没验证"导致综合把整块逻辑优化掉的事故（§3.4） |
| 3 | **`sim/tests.json` 是共享文件，改动前先声明** | 所有新 TB 都要在这里注册，是唯一的写冲突热点（§6.2） |
| 4 | **不要 `git add -A` 而不看内容** | 工作区有 36.6 GB 数据集（已 gitignore，但规则被删就完了） |
| 5 | **不要臆造引脚** | 任何 `LOC=` 必须能追到 `pinmap.md` 某一行；查询用 `pinmap_query.py` |

### 结论口径

- 判定"通过"必须给**原始输出**，不接受"应该可以"；
- 已知失败项（`hough`）**不要改判据去迁就**，要修设计；
- 报告写进 `reports/`，命名 `reports/<主题>_<日期>.md`。

---

## 一、环境事实（**已实测，别重新发现**）

### 1.1 工具链

| 项 | 值 | 备注 |
|---|---|---|
| 器件 | `PGL50H-6FBG484`（盘古50K / MES50HP） | PDS 里器件串**不带 I** |
| PDS | `D:\PDS23.2\PDS_2023.2-SP3-ads` | 2023.2-SP3 build 154097 |
| PDS 批处理 | `bin\pds_shell.exe -file <tcl> -work_dir <dir>` | 官方批处理入口 |
| ModelSim | `D:\modelsim\win64` | **SE-64 10.1c**（2012），完整版 |
| ModelSim license | `LM_LICENSE_FILE=D:\modelsim\win64\LICENSE.TXT` | ⚠️ 名字像说明文档，**其实是节点锁定 license** |
| iverilog | **未安装** | 原 `sim/*.f` 的 iverilog 流程实际跑不起来 |
| Python | `.venv_gpu` / `.venv_compression` | 技能脚本用系统 `python` 亦可 |

### 1.2 命令速查

```powershell
# 仿真回归（工程根目录，必须）
.\sim\sim.ps1 -All                    # 全量；退出码 0=全通过 1=有失败 2=参数错
.\sim\sim.ps1 -List                   # 看清单与上次结果
.\sim\sim.ps1 -Test <name> -Wave      # 开 GUI 看波形
.\sim\Modelsim\precompile_pango.ps1   # Pango 原语库（post-synth 用，已就绪）

# PDS 实现流程
.\pds\pds_flow.ps1                    # 综合→布局布线→时序→位流，约 60~90 秒
.\pds\pds_flow.ps1 -Open              # 跑完自动开 GUI

# 引脚查询 / 约束审查 / RTL lint
# ★ 先设 PYTHONIOENCODING，否则这些脚本在 GBK 控制台上会崩（见坑 #13）
$env:PYTHONIOENCODING = 'utf-8'

python .dsh\skills\pangu-50k-dev\scripts\pinmap_query.py <关键词>
python .dsh\skills\pangu-50k-dev\scripts\pinmap_query.py --pin <PIN>
python .dsh\skills\pangu-50k-dev\scripts\pinmap_query.py --dup      # 查重复占用
python .dsh\skills\pangu-50k-dev\scripts\fdc_audit.py <你的.fdc>     # 约束审查 C1-C8
python tools\rtl_lint.py                                            # RTL 静态自检
```

**实测**（2026-09-22，均已在当前代码上跑过）：

| 命令 | 结果 |
|---|---|
| `fdc_audit.py constr/lane_selftest.fdc` | exit **0**，硬问题 0，提示 2（C3 单时钟无跨域对；C8 无 IO 延时——端口直连引脚且已 `PAP_IO_LOC` 锁定，正常） |
| `rtl_lint.py` | exit **0**，15 文件 0 问题 |
| `pinmap_query.py --dup` | 正常输出（**修好了**，原先崩溃） |

### 1.3 已踩过的坑（**照着避，别重踩**）

| # | 坑 | 现象 | 对策 |
|---|---|---|---|
| 1 | 裸 `vsim` 命中 Quartus ASE | 32 位免费版、容量受限 | `sim.ps1` 自动把完整版提到 PATH 最前 |
| 2 | `vsim` 不认 `-work` | `Unknown option '-work'` | `-work` 是 `vlog` 的；`vsim` 用 `work.<top>` |
| 3 | `Start-Process -ArgumentList` 不加引号 | `Failed to open -f file "-l"` | `-do "run -all; quit -f"` 里的 `-f` 被拆成独立选项 |
| 4 | `vdir <路径>` | `Could not find work.<路径>` | 用 `vdir -lib <库名>` |
| 5 | 库内文件名被改写 | `Test-Path GTP_PLL_E3` 永假 | 编码成 `@g@t@p_@p@l@l_@e3`；用 `vdir -lib` 查 |
| 6 | Verilog `$display` 里的中文 | 日志变 `>>> ????????????` | **`$display` 字符串必须纯 ASCII**（注释中文无妨） |
| 7 | PowerShell 写 Verilog 注入 BOM | `unexpected non-printable character 0xef` | 用 `[System.IO.File]::WriteAllText(..., UTF8Encoding($false))`；另有 `tools/strip_bom.py` |
| 8 | `.ps1` 带中文 | PS 5.1 按 GBK 解析 → 语法错误 | **`.ps1` 本体保持纯 ASCII**；本环境 `pwsh` 实为 **PowerShell 5.1** |
| 9 | GUI 开着跑 Tcl | `.pds` 被写坏 | `pds_flow.ps1` 会拒绝运行；要开 GUI 用 `-Open` |
| 10 | 数据总线悬空 | 综合裁掉整条通路，资源报告失真 | 每个输出总线都要有可观测去处（§3.4） |
| 11 | `git commit -m` 消息含中文引号 | PowerShell 当成字符串结束符，提交失败且消息后半段被当路径 | 消息里别用 `"`；复杂消息写文件用 `git commit -F` |
| 12 | 命令顺序 | 技能称"必须先 `set_arch`" | **实测两种顺序都能编译，0 错误**（`tmp/pds_probe/order_{a,b}.log`） |
| 13 | Python 脚本在 GBK 控制台崩溃 | `UnicodeEncodeError: 'gbk' codec can't encode character '\u2139'`（`pinmap_query.py --dup` 曾直接崩） | **先 `$env:PYTHONIOENCODING='utf-8'`**；脚本本身也已加 `sys.stdout.reconfigure` 兜底 |
| 14 | `Select-Object -First N` 掐断管道 | 被截断的命令退出码变成 `-1`，误判为失败 | 看退出码时别用 `-First`；或改用 `Select-String` |
| 15 | 时序判据读错文件 | `Design Summary` 只在 `.rtr` 里，不在 flow log 里 | 驱动脚本已修；手工查时序**读 `.rtr`** |
| 16 | slack 只看一行 | `.rtr` 有 24 行跨 corner，随便读一行会偏乐观（+0.223 vs 真实最差 +0.176） | **取最差值** |

---

## 二、当前状态快照（2026-09-22，HEAD `4d6a33f`）

### 2.1 两条流程的实测结果

```
.\sim\sim.ps1 -All    →  PASS 3 / FAIL 1   退出码 1
.\pds\pds_flow.ps1    →  PDS FLOW: PASS    退出码 0   81 秒   E: 错误 0 条
```

| 仿真测试 | 覆盖 | 结果 | 耗时 |
|---|---|---|---|
| `lane` | rgb2gray→gauss→sobel→nms→hyst→roi 逐拍比对 | ✅ PASS（mismatch = 0） | 1.8 s |
| `div` | div_seq（含负数、除零） | ✅ PASS（fails=0） | 1.7 s |
| `lane_top` | **集成级 SOF 贯通** | ✅ PASS | 2.2 s |
| `hough` | hough_acc→lane_fit 端到端 | ❌ **FAIL（err_cnt = 4）** | 2.8 s |

### 2.2 PDS 实测数据

| 项 | 值 | 判据 |
|---|---|---|
| 流程 | 11 阶段全成功，`E:` 0 条 | ✅ |
| **时序** | **All Constraints Met** | ✅ |
| Setup WNS | **+6.630 ns**（周期 20 ns） | ✅ |
| Hold 最差 slack | **+0.176 ns**（24 行中最差，跨 corner） | ⚠️ 偏紧 |
| Fmax | **74.79 MHz**（约束 50） | ✅ |
| LUT | 2053 / 42800（4.80%） | — |
| Register | 1741 / 64200（2.71%） | — |
| **DRM18K** | **72 / 134（53.73%）** | ⚠️ 已过半 |
| APM | 12 / 84（14.29%） | — |
| Latch | **0** | ✅ ALG-07 |
| 位流 | `pds/work/generate_bitstream/lane_selftest_top.sbit`（2.0 MB） | — |

### 2.3 设计配置

- 顶层：`lane_selftest_top`，图像 **640×480**，`sys_clk` = 50 MHz（P20）
- 板级自检：内部图案发生器产生"路面 + 两条车道线" → 全链路 → LED
- **未接入真实视频链路**（无摄像头/DDR3/HDMI），这是后续最大的一块

### 2.4 版本控制状态

- 跟踪 **824** 个文件，工作区干净
- 数据集 **36.6 GB 已 gitignore**（`交通场景数据集` 18.3GB / `红绿灯车辆数据集` 18.3GB / `标注完数据集`）
- 虚拟环境 `.venv_gpu` 3.57 GB 已 gitignore

---

## 三、已走过的流程（**别重复做**）

### 3.1 仿真流程（已建立）

```
sim/sim.ps1            驱动：编译+运行+判定+日志+退出码，含硬超时
sim/tests.json         测试清单（加 TB 只改这里）
sim/*.f                文件清单（`#` 注释，ModelSim 与 iverilog 双兼容）
modelsim.ini           工程级库映射（work / pango_lib）★ 必须入库
sim/modelsim/wave.do   GUI 波形配置
sim/modelsim/precompile_pango.ps1   Pango 原语库预编译
```

**判定机制**：`sim.ps1` 从 `tests.json` 的 `expect` 正则判定，不看日志"像不像通过"。
默认**清空 work 库重建**（避免陈旧目标文件的经典陷阱），含真实超时强杀。

### 3.2 PDS 流程（已跑通）

```
pds/impl.tcl       官方命令序列（来源：官方例程 impl.tcl 最完整形态）
pds/pds_flow.ps1   驱动：护栏 + 资源/时序自动提取
constr/lane_selftest.fdc   时序 + 引脚合一
```

序列：
```
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
add_design（读 rtl/lane_selftest.f，15 个文件）
add_constraint constr/lane_selftest.fdc
compile -top_module lane_selftest_top
synthesize -ads -selected_syn_tool_opt 2
dev_map → place → route → route_optimize
report_timing
gen_bit_stream -master_configuration_clock_frequency {40M}
```

> `.pcf` 是 `device_map/` 下的**生成物不是输入**。引脚写 `.fdc`。

### 3.3 Pango 原语库（已预编译就绪）

- 源：`<PDS>\arch\vendor\pango\verilog\simulation\` 的 **373 个明文 Verilog 原语**
- 产物：`sim/modelsim/libs/pango_lib`，12 个 PGL50H 必需原语已校验齐备
- **5 个文件含 IEEE-1735 加密区**，10.1c 无密钥：`GTP_HSSTHP_HPLL/LANE/LANE_E1`、
  `GTP_HSSTUP_LANE`、`GTP_LUT5S` —— 全属 **HSSTHP/HSSTUP**，**盘古50K 用 HSSTLP 不受影响**
- ⚠️ 排除而非忽略报错：解不开的保护区会产出**空桩**，"编译成功但功能残缺"比硬报错危险
- 用法：`vsim -L pango_lib work.<top>`

### 3.4 ★ 已修复的真实缺陷（含一条方法论教训）

**缺陷**：`lane_detect_top` 的 SOF 断链。只有 `rgb2gray` 重建 `tuser`，
`gauss5x5`/`sobel_3x3`/`canny_nms`/`canny_hyst` **四个模块两条分支都赋 `1'b0`**，
`roi_mask` 只透传，而顶层把它的输入接成 `1'b0` → `hough_acc` 永远收不到 SOF
→ 状态机进不了 `S_SCAN` → **累加器被综合整块删除，上板车道线功能整体失效**。

**为什么藏得住**：`tb_lane_pipeline` 逐级直连各模块、`tb_hough_fit` 直连 `hough_acc`，
**两者都没例化 `lane_detect_top`**。集成层零覆盖。

**已修**：`lane_detect_top` 内按行号回绕重建 SOF/EOL；新增 `sim/tb/tb_lane_top_sof.v`。

**⚠️ 方法论教训（非常重要，后续 agent 必读）**：
第一版修复用 `(c_tx==0 && c_ty==0)` 是**错的** —— 各级有效区逐级内缩
（gray 全图 64×48 → roi 只剩 54×38，每边缩 5），坐标 `(0,0)` 根本不出现。
阴险之处：综合器**无法证明**该条件恒假，于是**保留了逻辑** ——
DRM18K 从 8 涨到 72，"看起来修好了"，**但运行时依然坏的**。
**是新写的集成 TB 抓出来的，综合和位流生成都没发现。**

> **推论**：新写的回归测试必须做**反向验证**（注入 bug → 确认变红 → 恢复 → 确认变绿）。
> 抓不到 bug 的测试等于没有。本次已验证：注入 `c_sof=1'b0` → 干净编译后判
> `FAIL (SOF never reached hough_acc)`。

**遗留**：四模块真正透传 `tuser` 的彻底修法未做（见 W2）。

### 3.5 资源报告失真事件（教训）

第一版板级顶层只把 `tvalid` 接 LED、数据总线悬空 → 综合裁掉整条不可观测通路，
**连带 hough 累加器消失**：`DRM18K 8 (5.97%)` vs 真实的 `72 (53.73%)`。

> **纪律**：bring-up 设计里**每个输出总线都必须有可观测去处**。
> 这不是调试花活，是资源报告有效性的前提。

---

## 四、待解决问题（工作流分解）

### 4.0 并行度与依赖总览

```
         ┌─────────────────────────────────────────────────────┐
         │  W1 hough 精度整改  ──┐                             │
         │  W2 tuser 透传修复  ──┼──► 门禁（§六）──► 集成       │
         │  W4 post-synth 仿真 ─┤                             │
         │  W7 文档同步        ─┘                             │
         └─────────────────────────────────────────────────────┘
  W5 资源优化 ── 必须等 W1 完成（同文件 hough_acc.v）
  W3 上板验证 ── 需要硬件，独立
  W6 hold 收紧 ── 需先有 PDS 基线（已有）
  W8 真实视频链路 ── 大工程，可另起一条线
```

| 工作流 | 优先级 | 可并行 | 关键依赖 |
|---|---|---|---|
| **W1** hough 精度整改 | **P0** | ✅ **已认领·已完成**（2026-09-23，产出见 §W1 尾注） | 无 |
| **W2** tuser 透传彻底修复 | **P0** | ✅ | 无（但与 W1 抢门禁时间） |
| **W3** 上板验证 | P1 | ✅ | **需要板卡** |
| **W4** post-synth 仿真 | P1 | ✅ | 无 |
| **W5** DRM18K 资源优化 | P2 | ❌ | **必须等 W1** |
| **W6** hold 时序收紧 | P2 | ✅ | 无 |
| **W7** 文档与知识库同步 | P2 | ✅ | 无 |
| **W8** 真实视频链路接入 | P1（大） | ✅ | 可独立成线 |

---

### W1 · hough_acc 峰值统计量整改 【P0】

**问题**：`tb_hough_fit` 稳定判 `FAIL (err_cnt = 4)`。两条车道**都检出**了
（`valid=1`）、投票无丢包、无除法错，**错的只是峰值定位精度**：端点偏差 111~238 px。

**根因**（`reports/sim_lane_detect.md` §四，证据充分）：θ 方向峰值**铺开**。
`lane_fit` 对全部过门限的 θ 分档做加权平均，噪声分档把斜率拉偏。
日志里 `PEAK #1..#64` 直接印证：θ=0…16 各档票数在 3~24 间散布，真值分档不占优。

**输入**：
- `rtl/lane/hough_acc.v`（409 行，累加器 + 峰值扫描 FSM）
- `rtl/lane/lane_fit.v`（18 KB，拟合）
- `reports/sim_lane_detect.md` §四（**整改方案 P0–P3 已列出，照做**）
- `sim/tb/tb_hough_fit.v`（判据：端点误差 ≤ 30 px）

**文件所有权**：`rtl/lane/hough_acc.v`、`rtl/lane/lane_fit.v`

**产出**：
1. 整改后的 RTL
2. `.\sim\sim.ps1 -Test hough` → `>>> RESULT: PASS`（原始输出贴进报告）
3. `reports/hough_fix_<日期>.md`：改了什么、为什么、**整改前后端点数值对比**

**判据**：`err_cnt == 0`，且 `lane` / `lane_top` 两个测试**不得回归**。

**建议**：先做 P0（±2 bin 滑窗票数和，约 40 LUT），性价比最高。

**坑**：`hough_acc` 的 `P_ACC_N = 64 × 1152 = 73728`，`P_AW = $clog2()` = 17 →
实际推断出 depth=131072 的 RAM。**改 `P_RHO_BINS` 会同时改变累加器大小**，
而它现已占 53.73% DRM18K，不要顺手放大。

> #### ✅ W1 已认领并完成（2026-09-23）
>
> **状态**：`hough` PASS（err_cnt = 0），`sim.ps1 -All` **4/4 全绿退出码 0**，
> `pds_flow.ps1` **PASS**（All Constraints Met），`rtl_lint.py` **PASS**，
> 反向验证（注入 bug → 变红 → 恢复 → 变绿）已闭环。
>
> **⚠️ 上面「根因」一段的口径已被实测推翻**：θ 铺开是**表象不是根因**。
> 用 Python 逐位复现投票算术后确认，真值 θ 档本应集中 93 票（噪声档 ≤35），
> 分离度良好；票数散布 3~24 是因为 **① 投票 RMW 读到 RAM 陈旧输出**
> （2 相引擎，寄存输出滞后 1 拍 → 票从未真正累加，模型复现出与日志一致的
> 1..64 斜坡）与 **② 扫描峰值 ρ 标号 off-by-one**（用延 1 拍的计数器给延
> 2 拍的数据标号，且最后一个 bin 从未参与比较）。
> 详见 `reports/hough_fix_20260923.md` §二；`reports/sim_lane_detect.md` §四
> 的归因请 W7 按此更新。
>
> **实际实施**：P0（±2 bin 滑窗票数和）+ P3（每侧取窗口和最大 θ 档）。
> P1 未做（误差已 8~13 px，余量 2 倍，不值 3 次乘法）；
> P2 未做（DRM18K 保持 72/134，遵守禁止放大）。
>
> **端点结果**：LEFT 305/737（期望 293/750）、RIGHT 1639/1162（期望 1627/1170）
> —— 整改前为 152/909 与 1865/1040。
>
> **资源变化**：LUT 2053→**1784**、Register 1741→**1638**、APM 12→**9**
> （P3 免除 2 次除法）、DRM18K 72 不变、WNS +6.630→**+6.760 ns**、
> 最差 hold +0.176→**+0.171 ns**（仍满足约束，W6 继续跟）。
>
> **产出文件位置**：
>
> | 类型 | 路径 |
> |---|---|
> | **主报告** | `reports/hough_fix_20260923.md` |
> | 改动 RTL | `rtl/lane/hough_acc.v`、`rtl/lane/lane_fit.v` |
> | 仿真日志（PASS 原始输出） | `reports/sim_logs/hough.log` |
> | 全量回归结果 | `reports/sim_logs/last_results.json` |
> | PDS 日志 / 时序 / 位流 | `pds/work/pds_flow.log`、`pds/work/report_timing/lane_selftest_top.rtr`、`pds/work/generate_bitstream/lane_selftest_top.sbit` |
> | 分析模型（非交付物，供追溯） | `tmp/hough_model/model_hough.py`、`tmp/hough_model/predict_fix.py` |
>
> **给后续工作流的交接说明**：
> - **W5**：`m_peak_votes` 语义已从"单 bin 票数"变为"**±2 bin 窗口和**"，
>   评估 8bit 位宽时按窗口和口径（最大 5×255，已做饱和）；
>   投票每点开销 128→**192 拍**（3 相 RMW），做时序/帧预算时按新值算。
>   `hough_acc.v` 所有权现可移交 W5。
> - **W7**：`reports/sim_lane_detect.md` §四归因需按上文更正；
>   `sim/tests.json` 中 `hough` 条目的 `known_issue` 字段已过期，建议移除
>   （该文件共享，W1 本轮未动）。
> - **W6**：最差 hold slack +0.171 ns，路径见 `.rtr`。
>
> 本轮**未改** `sim/tests.json`（无新 TB）、**未改**任何 `.fdc`、**未提交 git**。

---

### W2 · tuser 透传彻底修复 【P0】

**问题**：§3.4 的缺陷目前是在 `lane_detect_top` 里**打补丁**（行号回绕重建 SOF）。
治本做法是让四个模块真正透传/重建 `tuser`。

**输入**：
- `rtl/preprocess/gauss5x5.v`、`rtl/preprocess/sobel_3x3.v`
- `rtl/lane/canny_nms.v`、`rtl/lane/canny_hyst.v`
- `rtl/lane/lane_detect_top.v`（补丁在此，改完需移除）
- `rtl/preprocess/rgb2gray.v`（**参考实现**：`m_axis_tuser <= u2` 重建方式）
- `sim/tb/tb_lane_top_sof.v`（判据 TB）

**文件所有权**：上述 4 个模块 + `lane_detect_top.v`

**产出**：
1. 四模块正确产生 `m_axis_tuser`/`m_axis_tlast`
2. 移除 `lane_detect_top` 里的重建补丁
3. `.\sim\sim.ps1 -Test lane_top` → PASS，且 `-Test lane` 不回归
4. `reports/tuser_propagation_<日期>.md`

**判据**：
- `lane_top` PASS
- **反向验证**：把任一模块的 tuser 接回常量 → 必须变红 → 恢复 → 变绿
- `lane`（逐拍比对 mismatch = 0）**不得回归** —— 改 tuser 不应影响数据通路

**风险**：这几个模块都有行缓存，`tvalid` 的延迟不是固定拍数。
加 `tuser` 流水线时必须与 `tvalid` **严格同源对齐**（本项目纪律 #9/#10）。
**建议先读懂每个模块的 valid 生成方式再动手。**

---

### W3 · 上板验证 【P1，需要硬件】

**问题**：位流从未在真实板卡上跑过。

**输入**：`pds/work/generate_bitstream/lane_selftest_top.sbit`

**期望现象**：

| LED | 引脚 | 现象 |
|---|---|---|
| LED1 | B2 | **心跳，约 3.3 Hz**（每帧翻转 @640×480/50MHz） |
| LED2 | A2 | 亮（检测流被接收） |
| LED3 | B3 | 亮（绘制流有输出） |
| LED4 | A3 | 数据签名位（闪烁） |

**工具**：下载器实测为 **`PANGO USB CABLE II`**（D2XX/ftd2xx），
JtagServer 监听 `127.0.0.1:65420`，器件 IDCODE `0x10521899`。
供电：底板 12V → 5V，核心板 1.2/3.3/1.5/HSST_1.2。

**排障顺序**（技能 §5）：供电 → 配置通路（DONE 灯）→ 时钟（P20）→ 外设 → 引脚核对。

**文件所有权**：`reports/bringup_<日期>.md`（只写报告，不改 RTL）

**判据**：LED1 心跳 + LED2/3/4 符合预期，并附照片/视频。

**⚠️ 注意**：若 LED2/3/4 全灭但 LED1 闪，说明图案发生器在跑但流水线没出数据 ——
回到 `lane_top` 测试排查。

---

### W4 · post-synth 仿真接入 【P1】

**问题**：目前只有行为级仿真。综合后网表从未仿真过，
而 §3.4 的缺陷正是"行为级测不出、综合才暴露"的典型。

**输入**：
- `pds/impl.tcl`（需加 `gen_netlist` 或从 `synthesize/*_syn.v` 取网表）
- `sim/modelsim/libs/pango_lib`（**原语库已预编译就绪**）
- `sim/sim.ps1`、`sim/tests.json`（加新测试）
- `pds/work/synthesize/lane_selftest_top_syn.vm`（774 KB，已生成）

**产出**：
1. 网表导出流程（PDS 侧）
2. `sim/sim_lane_syn.f` + `tests.json` 新条目 `lane_syn`
3. `reports/postsyn_<日期>.md`：行为级 vs 网表级结果对比

**判据**：网表级仿真结果与行为级**一致**（同 TB 同激励）。

**坑**：
- 网表仿真必须 `vsim -L pango_lib`，否则 `Module 'GTP_xxx' not found`
- PDS 的 `pds_shell -skip_actions` 可跳过 `report_power`/`gen_netlist`，注意别误跳
- 网表里原语是 `GTP_*`，与 RTL 行为级**时序不同**，逐拍比对的拍数会变

---

### W5 · DRM18K 资源优化 【P2，**必须等 W1**】

**问题**：DRM18K 已用 **72/134（53.73%）**，而这只是 640×480 的车道线链路。

**输入**：`rtl/lane/hough_acc.v`（累加器是最大块）

**已知可优化点**（`constr/lane_detect.fdc` §7 有记录）：
- `P_RHO_BINS` 从 1152 降到 1024（需同步确认 `XD+YD ≤ 511`，即 `P_DECIM` 提到 8）
- 累加器位宽：当前 8 bit/格，可评估是否够用

**文件所有权**：`rtl/lane/hough_acc.v` ← **与 W1 冲突，必须串行**

**判据**：DRM18K 下降且 `hough` 测试（W1 完成后应为 PASS）**不回归**。

---

### W6 · hold 时序收紧 【P2】

**问题**：最差 hold slack 仅 **+0.176 ns**。50 MHz 下没事，但改变时钟或换配置后风险高。

**输入**：`pds/work/report_timing/lane_selftest_top.rtr`

**产出**：定位最差 hold 路径 → 整改 → 重跑 PDS，`reports/hold_fix_<日期>.md`

**判据**：最差 hold slack 提升，且 `All Constraints Met` 保持。

---

### W7 · 文档与知识库同步 【P2】

**已知需要更正的**：

| 位置 | 问题 |
|---|---|
| `docs/04-工作流程.md` §〇 | 称"首次提交 ⏳ 待配置 user.name/email"—— **已过期**，git 身份早已配置为 `yq <3037541748@qq.com>`，且已有多次提交 |
| `docs/04-工作流程.md` §一 | 目录骨架未含 `pds/`、`sim/modelsim/`、`constr/*.selftest.fdc` |
| `docs/04-工作流程.md` 附录 B | 技能清单只有 6 个，实际有 9 个（缺 `pangu-50k-dev` 等） |
| `docs/02-目标分类.md` | 未记录本次新增的资源/时序实测基线 |
| `reports/sim_lane_detect.md` §四 | hough 失败形态与本次实测不一致（"饱和" vs "有值但偏差大"）—— **需在 W1 完成后统一口径** |

**文件所有权**：`docs/`（除本文件）、`reports/*.md` 中的历史报告

> ⚠️ `reports/sim_lane_detect.md` 的口径问题**要等 W1 做完**再改，否则改了两边对不上。

---

### W8 · 真实视频链路接入 【P1，大工程】

**问题**：当前是内部图案发生器自测，**没有真实视频通路**：
摄像头（DVP）→ DDR3 帧缓存 → HDMI 输出，一个都没有。

**这是整个项目最关键也最大的一块**，建议单独立项。

**输入 / 参考**：
- `pds_ov5640/10_HDMI_DDR3_OV5640_test/`：**官方例程**（OV5640 + DDR3 + HDMI 全链路）
  - `impl.tcl`、`hdmi_ddr_ov5640_top.fdc`（52 KB 真实约束）、`source/rtl/` 全套
- 技能 `pangu-50k-dev`：§1.2 PDS 流程、§3 约束规范、§4 BANK 与资源、`schematics/` 32 张原理图
- `docs/05-车道线检测RTL设计说明.md`

**已知硬约束**：
- OV5640 插在 **40pin 扩展口 J8**，**必须经电平转换，切勿直连**
- HSST 通道 0/1 与 PCIe 物理共用；通道 2/3 给 SFP
- HDMI 输入/输出**共用复位网络 R17**，`W22` 是收/发双向复用脚
- I2C 从地址：MS7200 = **0x56**（SA 下拉）、MS7210 = **0xB2**（SA 上拉）
- DDR3 VCCIO 固定 1.5，`HSTL15_I`；DQS 用 `HSTL15D_I`

**⚠️ 资源预警**：DRM18K 已用 53.73%。加上 DDR3 帧缓存（乒乓 2 帧 720P）
与 AI 卷积行缓存后，**134 个 DRM18K 极可能不够**。动手前先做资源预算。

---

## 五、可用资源

### 5.1 技能（`.dsh/skills/`，共 9 个）

| 技能 | 用途 | 本次相关度 |
|---|---|---|
| **`pangu-50k-dev`** | 盘古50K 全流程、**531 行逐信号引脚表**、32 张原理图、PDS 流程、避坑 | ★★★ |
| `timing-constraints-fdc` | `.fdc` 生成与审查（主时钟/衍生时钟/跨域例外） | ★★★ |
| `rtl-module-scaffold` | Verilog 模块骨架（valid 对齐、级间打拍、延迟登记） | ★★ |
| `verilog-lint-gate` | 提交前静态自检（位宽/latch/CDC/行缓存指针） | ★★ |
| `refmodel-golden-gen` | Python 参考模型 + 导出 `$readmemh` 金标准 | ★★ |
| `kpi-dashboard` | KPI 看板（带宽/延迟/帧率/WNS/资源/功耗） | ★★ |
| `int8-weight-export` | INT8 量化 + `.mem/.coe` 导出（AI-03） | ★ |
| `yolo-edge-deploy` | YOLO 端侧部署与算力优化 | ★ |
| `github-code-reader` | 稳定读 GitHub 仓库代码 | ★ |

### 5.2 可直接复用的脚本

| 脚本 | 用途 |
|---|---|
| `sim/sim.ps1` | 仿真驱动（**新 TB 只需改 `tests.json`**） |
| `pds/pds_flow.ps1` | PDS 全流程驱动 |
| `sim/modelsim/precompile_pango.ps1` | Pango 原语库（已就绪，`-Force` 可重建） |
| `.dsh/.../pinmap_query.py` | 引脚查询 / `--dup` 查重复占用 |
| `.dsh/.../fdc_audit.py` | `.fdc` 静态审查 C1–C8 |
| `.dsh/.../csv2pcf.py` | 引脚 CSV → PCF |
| `tools/rtl_lint.py` | RTL lint |
| `tools/strip_bom.py` | 去 BOM（写 Verilog 后必查） |

### 5.3 关键参考文件

| 文件 | 内容 |
|---|---|
| `pds/README.md` | PDS 流程完整文档（约束写法、资源时序、8 条坑） |
| `sim/README.md` | 仿真流程完整文档（环境事实、8 条坑） |
| `reports/sim_regress_20260922.md` | 仿真首轮回归报告 |
| `reports/pds_impl_20260922.md` | PDS 实现流程验收报告 |
| `reports/sim_lane_detect.md` | **hough 整改方案 P0–P3 在这里** |
| `reports/lint_lane_detect.md` | RTL lint 报告 |
| `reports/metrics_lane_detect.md` | 定点精度指标（PSNR 等） |
| `docs/夜瞳异构-验证纪律与错题本.md` | **必读**：已付代价的教训，避免重踩 |
| `docs/03-关键资源与避坑清单.md` | 避坑清单 |
| `docs/05-车道线检测RTL设计说明.md` | 车道线链路设计说明 |
| `pds_ov5640/10_HDMI_DDR3_OV5640_test/` | **官方全链路例程**（impl.tcl / fdc / 源文件） |

### 5.4 证据位置

| 类型 | 路径 |
|---|---|
| 仿真日志 | `reports/sim_logs/<name>.log`（**出问题第一现场**） |
| 仿真结果 JSON | `reports/sim_logs/last_results.json` |
| PDS 全量日志 | `pds/work/pds_flow.log`（约 370 KB） |
| 时序报告 | `pds/work/report_timing/lane_selftest_top.rtr` |
| 资源报告 | `pds/work/synthesize/apm_drm_lutram_utilization.log` |
| 位流 | `pds/work/generate_bitstream/lane_selftest_top.sbit` |
| 顺序实测日志 | `tmp/pds_probe/order_{a,b}.log` |

---

## 六、协作规则

### 6.1 文件所有权表（**核心，防写冲突**）

| 文件 / 目录 | 所有者 | 说明 |
|---|---|---|
| `rtl/lane/hough_acc.v`、`lane_fit.v` | **W1**（后移交 W5） | W1↔W5 必须串行 · **W1 已完成（2026-09-23），可移交 W5；votes 语义已变为窗口和，见 §W1 尾注** |
| `rtl/preprocess/*.v`、`rtl/lane/canny_*.v` | **W2** | |
| `rtl/lane/lane_detect_top.v` | **W2** | 当前有 SOF 补丁 |
| `rtl/top/lane_selftest_top.v` | **W3/W8** | 接口变更需全员同步 |
| `rtl/video_in/`、`rtl/mem/`、`rtl/display/` | **W8** | 新建 |
| `constr/*.fdc` | **W6/W8** | 改动需 `fdc_audit.py` 过一遍 |
| `sim/tests.json` | ⚠️ **共享，见 §6.2** | |
| `sim/sim*.f`、`sim/tb/tb_*.v` | 各工作流按 TB 归属 | 新 TB 归其作者 |
| `sim/sim.ps1`、`pds/pds_flow.ps1` | **基础设施，改动需声明** | 所有工作流依赖它们 |
| `docs/`、`reports/`（历史） | **W7** | |
| `reports/<新主题>_<日期>.md` | 各工作流自己写 | 不覆盖他人报告 |

### 6.2 ⚠️ 唯一写冲突热点：`sim/tests.json`

所有新增 TB 都要在这里注册，**多 agent 同时改必然冲突**。

**规则**：
1. 改动前在提交信息/报告中**声明**："本轮向 tests.json 追加 `<name>` 条目"；
2. 只做**追加**，不重排、不改他人条目；
3. 若发生冲突，**以能通过门禁的版本为准**，另一人重加；
4. 建议：**由集成者统一合并**，其他 agent 只提交自己 TB 的 `.f` 与 `tb_*.v`，
   在报告里给出应追加的 JSON 片段。

### 6.3 统一门禁（**每个工作流完成前必跑，贴原始输出**）

```powershell
# 工程根目录
$env:PYTHONIOENCODING = 'utf-8'      # 否则 lint/约束审查脚本可能崩

.\sim\sim.ps1 -All                   # 退出码 0 才算全绿；hough 未修完前允许为 1
.\pds\pds_flow.ps1                   # 退出码 0 且 "PDS FLOW: PASS"
python tools\rtl_lint.py             # 退出码 0（改过 RTL 必跑）
python .dsh\skills\pangu-50k-dev\scripts\fdc_audit.py constr\<改过的>.fdc
```

**放行标准**：

| 阶段 | 仿真 | PDS |
|---|---|---|
| W1 完成前 | `lane`/`div`/`lane_top` PASS | PASS |
| W1 完成后 | **4/4 全 PASS**，退出码 0 | PASS |
| 任何 RTL 改动后 | 上述 + **改动模块的专属 TB** 必须 PASS | PASS |

> **改了 RTL 不跑门禁 = 未完成**。本工程已因此吃过一次亏（§3.4）。

### 6.4 集成检查点

每轮并行结束后，集成者需要：

1. 跑 §6.3 门禁，确认全绿（或明确列出失败项）；
2. 检查 `git status`，确认**没有把数据集加进来**（36.6 GB）；
3. 跑 `python .dsh/skills/pangu-50k-dev/scripts/fdc_audit.py constr/*.fdc`；
4. 跑 `python tools/rtl_lint.py`；
5. 更新 `reports/`，提交（**消息里别用中文引号**，见 §1.3 坑 #11）。

### 6.5 提交规范（`docs/04` §一）

```
[目标ID] 动词 + 对象
例：[ALG-09] 实现 hough 峰值滑窗票数和
```

分支：`main` 恒可综合；每人一条 `feat/<模块>`；**合并前必须仿真通过**。

---

## 七、快速上手：三种典型任务的开场

### 接 W1（hough 精度）

```
读 docs/06-多Agent协作任务书.md §W1，以及 reports/sim_lane_detect.md §四。
你有 rtl/lane/hough_acc.v 与 rtl/lane/lane_fit.v 的所有权。
先做 §四 的 P0 措施（±2 bin 滑窗票数和）。
完成后跑 .\sim\sim.ps1 -Test hough 与 -All，贴原始输出，写 reports/hough_fix_<日期>.md。
不要动 rtl/lane/hough_acc.v 以外模块的接口；不要改大 P_RHO_BINS（DRM18K 已占 53.73%）。
```

### 接 W2（tuser 透传）

```
读 docs/06-多Agent协作任务书.md §3.4 与 §W2。
你有 rtl/preprocess/*.v 与 rtl/lane/canny_*.v、lane_detect_top.v 的所有权。
注意：lane_detect_top.v 当前有一处行号回绕补丁，你改完要移除它。
必须先读懂每个模块的 valid 生成方式（tuser 必须与 tvalid 严格同源）。
完成后做反向验证：接回常量 -> 必须变红 -> 恢复 -> 变绿。
```

### 接 W8（视频链路）

```
读 docs/06-多Agent协作任务书.md §W8，加载 pangu-50k-dev 技能。
先做资源预算：DRM18K 已用 53.73%，DDR3 乒乓帧缓存要多少？不够就先报告再动手。
参考 pds_ov5640/10_HDMI_DDR3_OV5640_test/ 官方例程。
引脚一律用 pinmap_query.py 查，不许臆造。
```

---

## 附录 A · 一句话状态

| 维度 | 状态 |
|---|---|
| 仿真流程 | ✅ RTL 行为级可用，3/4 通过 |
| PDS 流程 | ✅ 综合到位流全通，时序收敛 |
| 集成覆盖 | ✅ 已补 `lane_top`（此前为零） |
| 车道线功能 | ❌ **精度未达标，不可用** |
| 真实视频链路 | ❌ **未开始** |
| 上板 | ❌ **未验证** |
| 资源余量 | ⚠️ DRM18K 53.73%，APM 14.29% |
| 版本控制 | ✅ 824 文件入库，36.6 GB 数据集已挡 |

## 附录 B · 本文件维护

- 工作流状态变化时**由集成者**更新 §2 快照与 §4 的优先级；
- 每个工作流完成后，把其结论**归档进 `reports/`**，本文件只留指针；
- §1.3 坑清单**持续追加**——新踩的坑写进去，别只写在个人笔记里。
