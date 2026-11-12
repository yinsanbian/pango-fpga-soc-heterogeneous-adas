---
name: pangu-50k-dev
description: 盘古50K（MES50HP / PGL50H-6IFBG484）FPGA 开发全流程与规范：PDS 2023.2-SP3 工具链命令序列、工程/产出物规范、板卡硬件资源、原理图连接关系与**逐信号引脚约束**（DDR3/HDMI/网口/SFP/PCIe/摄像头/扩展口）。当任务涉及盘古50K 板卡、PGL50H 器件、PDS 综合/布局布线/位流、.fdc/.pcf 引脚与时序约束、或需要查某个外设接在哪个引脚时使用。
---

# 盘古50K（MES50HP）FPGA 开发

> 事实来源（按权威度）：
> ① **《MES50HP开发板硬件使用手册 1V1》**（2024-07-19，38 页）—— 现行手册；
> ② 同系列 V1.0（2022-12-28，36 页）—— 经逐条比对**引脚与 1V1 零差异**（差异见 `reference/manual-1v1-delta.md`）；
> ③ 本机官方例程 `pds_ov5640/10_HDMI_DDR3_OV5640_test/` 的真实 PCF/FDC/工程日志；
> ④ 本机 PDS 实测版本：**2023.2-SP3, build 154097**（`D:\PDS23.2\PDS_2023.2-SP3-ads`）。

## 第一性原则（先读这三条，再动手）

1. **引脚不可臆造。** 任何 `LOC=` 都必须能追到 `reference/pinmap.md` 的某一行或手册某页。
   查不到就停下，用 PDS 器件视图复核，不要"猜一个像的"。
2. **约束不能自欺。** 每个 PLL 输出都要有生成时钟；每条跨域通路要么有同步器+例外约束、
   要么有异步 FIFO+`set_clock_groups`。用 `set_false_path` 掩盖真实违例＝上板必炸。
3. **工程文件是共享状态。** PDS GUI 打开工程时**禁止**并发跑 MCP/Tcl；写操作前备份 `.pds`。
   （依据：`reports/pds_pds文件改动核查_20260920.md`）

## 何时用本技能

| 触发场景 | 去哪一节 |
|---|---|
| 新建 PDS 工程 / 跑综合到出位流 | §1 流程、§2 产出物 |
| 写/审 `.fdc`、`.pcf` | §3 约束规范、`reference/pds-flow.md` |
| "XX 外设接哪个引脚？" | `reference/pinmap.md`（**531 行逐信号**，已过 FBG484 几何校验 + 与官方 PCF 零冲突）；查询用 `python scripts/pinmap_query.py <关键词>`，反查引脚用 `--pin <PIN>` |
| "这个外设怎么接的？" | `schematics/`（32 张原理图，按图号索引） |
| 怀疑引脚冲突 / 电平常错 | `python scripts/pinmap_query.py --dup`、§4 电平与 BANK |
| 板卡上电没反应、DDR3/HDMI/摄像头不工作 | §5 上板排查、`reference/pinmap.md` 外设小节 |
| 判断"这块板能不能装下这个设计" | §4 资源预算 |
| 做时序/引脚约束增量补齐 | 先加载 `timing-constraints-fdc` 技能，再用本技能的引脚表核对 |

---

## §1 开发流程（RTL → 上板）

### 1.1 环境事实（实测）

| 项 | 值 |
|---|---|
| PDS 版本 | `2023.2-SP3`，build `154097` |
| 安装路径 | `D:\PDS23.2\PDS_2023.2-SP3-ads` |
| GUI | `bin\pds.exe` |
| Tcl 后端 | `bin\pds_shell.exe`（MCP 封装：`D:\PDS23.2\pds_mcp_server.py`） |
| License | `D:\PDS23.2\License\new_pds_F4A80DA47D72.lic` |
| 器件 | `Logos` / `PGL50H` / 速度等级 `-6` / 封装 `FBG484` |

> ⚠️ 安装路径**不得含中文或空格**，否则综合莫名失败（本项目避坑清单 #1）。

### 1.2 Tcl 全流程（每阶段一条命令，顺序即依赖顺序）

真源：官方例程 `impl.tcl`。这是本机验证过的**唯一权威命令序列**：

```tcl
# 0) 先选器件，再挂文件（顺序颠倒会报找不到器件）
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484

# 1) 挂设计源 + IP(.idf) + 约束(.fdc)；路径用正斜杠
add_design "…/source/rtl/xxx_top.v"
add_design "…/source/rtl/DDR3_50H/DDR3_50H.idf"      ;# PDS IP 核是 .idf
add_constraint "…/xxx_top.fdc"

# 2) 编译（解析 + 展开 IP）
compile -top_module xxx_top

# 3) 综合：-ads 自动设计空间探索，-selected_syn_tool_opt 2 = 优化档 2
synthesize -ads -selected_syn_tool_opt 2

# 4) 布局（器件映射）
dev_map

# 5) 布线
pnr                                  ;# 老写法：place / route / route_optimize 三步
                                     ;# 新版界面对应 place / route / route_optimize

# 6) 时序报告（WNS/TNS 判据看这里）
report_timing

# 7) 生成位流；主配置时钟必须显式给，默认不是你想要的那个
gen_bit_stream -master_configuration_clock_frequency {40M}
```

**GUI 等价阶段名**（`.pds` 工程里的任务名，用于对照进度与日志）：
`synthesize/` → `dev_map/`(device_map) → `place_route/` → `report_timing/` → `generate_bitstream/`。

### 1.3 板卡与器件事实（写代码前必须知道）

| 项 | 值 |
|---|---|
| FPGA | `PGL50H-6IFBG484`，40nm，Logos 系列，工业级，484 引脚 FBG484 |
| **PDS 里的器件串** | `-family Logos -device PGL50H -speedgrade -6 -package FBG484`（**不带 I**；工具产物里只出现 `PGL50H-6FBG484`） |
| 逻辑资源 | FF **64,200** ／ LUT6 **42,800**（1 LUT6 = 1.5 LUT4） |
| 存储/算力 | DRM(18Kb) **134** ／ APM 乘法器 **84** |
| 高速 | HSSTLP **4 路 × 6.375 Gb/s** ／ PCIe Gen2 ×1 |
| 可用 IO | 296 个 IO 端口（综合报告口径） |
| DDR3 | 2× `MT41K256M16TW-107:P`（4Gbit/片）→ **32bit 总线，最高 400MHz / 800Mbps**。<br>1V1 补充兼容型号 `XCCC256M16EP-EKNAY` / `QN3B256M16H-16A`，注明"以实物为准" |
| 系统时钟 | 板载 **50MHz 单端 → P20**（`sys_clk`，例程 `create_clock -period 20.000`） |
| 其它时钟 | 27MHz 单端 → K21；125MHz **差分** → HSST_CLK_P/N = **A10/B10** |
| 配置 Flash | QSPI **128Mb**（华邦 `W25Q128JVEIQ` / 兆易 `GD25Q128EYIGR` / 芯天下 `XT25BF128FSSIGU-W`，1V1 起三家并列），3.3V |
| 供电 | 底板 **+12V** 输入 → SGM61163 转 +5V → 核心板 → EZ8303 转 1.2/3.3/1.5/HSST_1.2V |

> 板载时钟只有 50M/27M/125M 三个。**想要别的频率只能走 PLL**，并把每个 PLL 输出
> 声明为 `create_generated_clock`（见 §3）。

---

## §2 工程与产出物规范

### 2.1 目录约定（与本仓库 `docs/04-工作流程.md` 一致）

```
rtl/            手写 Verilog（★ 文件清单 = 依赖顺序，谁被谁例化按层排）
ip/ 或 source/rtl/*/  PDS IP 核（.idf 是 IP 配置，.v/.vm 是生成物，勿手改）
constr/         .fdc 时序约束（增量约束单独成文件，注明"需与例程 fdc 合并"）
gen/            生成物：.mem/.coe 权重、综合/时序报告
reports/        归档报告：timing_<日期>.rpt、资源、功耗
```

### 2.2 产出物字典（哪些必须归档）

| 文件 | 含义 | 归档 |
|---|---|---|
| `.pds` | 工程文件（含源列表与阶段状态） | 备份，但**不入版本库** |
| `.fdc` | 时序约束（`create_clock` / `set_clock_groups` / IO 属性） | ✅ 入库，改动需评审 |
| `.pcf` | 引脚锁定（`def_port {sig} LOC=…`），由 PDS 生成或手写 | ✅ 入库（引脚是设计契约） |
| `.idf` | PDS IP 核配置文件 | ✅ 入库 |
| `.sbit` | **JTAG 在线下载用位流**（`generate_bitstream/` 下） | 可选归档 |
| `.sfc` | **固化到外挂 QSPI Flash 用的位流**（日志里的 `Erase/Program/Verify Outer Flash` 读它） | 可选归档 |
| `.smsk` | 位流掩码（Verify 时按同名 `.sbit` 找，缺了报 `Mask file does not exist`） | ❌ |
| `.bgr` | 位流生成记录（含 `Create Bit File=true`） | ❌ |
| `.rtr` | 时序报告（含 `_exception.rtr`） | ✅ 抽取摘要入 `reports/` |
| `.ppr` / `.pps` | 功耗报告 | 摘要归档 |
| `.snr` / `.ccr` | 综合网表 / 约束检查结果 | ❌ |
| `_timing_summary_after_hold_fix.txt` | 各时钟 WNS/WHS 汇总 | ⚠️ **可能是旧文件**（官方例程里是 2023-03-30 的）；当前结论以 `report_timing/*.rtr` 的 `Design Summary` 为准 |
| `.log`(各阶段 `run.log`, `pds.log`) | 阶段日志，出问题第一现场 | 只留最近一次 |

### 2.3 版本控制

`.gitignore` 必备（PDS 工程目录可达数 GB）：`*.bit *.fs *.prj *.pds *.log *.wdb`、
`pds_workspace/`、各阶段产物目录（`synthesize/ device_map/ place_route/ generate_bitstream/ report_*/`）。
**例外**：`.fdc` / `.pcf` / `.idf` / 手写 RTL 必须入库。

---

## §3 约束规范（引脚 + 时序）

### 3.1 引脚锁定：两种等价写法，别混用格式

**PCF（人读友好，PDS 也可回读）：**

```
def_port {mem_dq[0]} LOC=U1 VCCIO=1.5 IOSTANDARD=HSTL15_I DRIVE=8 SLEW=FAST NONE=TRUE
def_port {sys_clk}   LOC=P20 VCCIO=3.3 IOSTANDARD=LVCMOS33 NONE=TRUE
```

**FDC（PDS 原生属性，GUI 里改引脚后写回的就是这种）：**

```tcl
define_attribute {p:sys_clk} {PAP_IO_LOC} {P20}
define_attribute {p:sys_clk} {PAP_IO_VCCIO} {3.3}
define_attribute {p:sys_clk} {PAP_IO_STANDARD} {LVCMOS33}
define_attribute {p:sys_clk} {PAP_IO_DIRECTION} {INPUT}      ;# INPUT / OUTPUT / INOUT
define_attribute {p:mem_odt} {PAP_IO_SLEW} {FAST}
define_attribute {p:mem_odt} {PAP_IO_DRIVE} {8}
define_attribute {p:mem_odt} {PAP_IO_NONE} {TRUE}            ;# 关掉内部上下拉
```

要点：
- `p:` 前缀 = 端口，`i:` 前缀 = 实例，`n:` 前缀 = 网络（如
  `define_attribute {n:cmos2_pclk} {PAP_CLOCK_DEDICATED_ROUTE} {FALSE}`）。
- 复位/使能类输出推挽用 `DRIVE=8 SLEW=FAST`；I2C 等慢速双向用 `SLEW=SLOW` + `NONE=TRUE`。
- **DDR3 的 `VCCIO` 固定 1.5，标准 `HSTL15_I`；DQS 用 `HSTL15D_I`。**
- 用 `scripts/csv2pcf.py` 从引脚 CSV 批量生成 PCF，避免手抄错位。

### 3.2 时钟约束骨架（对齐官方例程的真实写法）

```tcl
# 主时钟：板载 50MHz
create_clock -name {sys_clk} [get_ports {sys_clk}] -period {20.000} -waveform {0.000 10.000}

# 每个 PLL 输出/衍生时钟逐条声明（漏一条 = 时序假收敛）
create_generated_clock -name {pix_clk} -source [get_ports {sys_clk}] [get_nets {u_pll.clkout0}] \
    -master_clock [get_clocks {sys_clk}] -multiply_by {27} -divide_by {20}   ;# 37.125MHz = 720P30
create_generated_clock -name {cfg_clk}  -source [get_ports {sys_clk}] [get_nets {u_pll.clkout1}] \
    -master_clock [get_clocks {sys_clk}] -multiply_by {1}  -divide_by {5}    ;# 10MHz 配置域

# 外部输入时钟（摄像头 PCLK 由器件驱动）
create_clock -name {cmos1_pclk} [get_ports {cmos1_pclk}] -period {11.900} -waveform {0.000 5.950}

# 跨域：官方例程用"一个时钟一个组"的写法，等价于两两异步
set_clock_groups -name pix_clk -asynchronous -group [get_clocks {pix_clk}]
set_clock_groups -name cfg_clk -asynchronous -group [get_clocks {cfg_clk}]
```

- DDR3 相关生成时钟一律来自 DDR3 IP（`u_DDR3_50H.I_GTP_CLKDIV/CLKDIVOUT`、
  `I_GTP_IOCLKBUF_*` 等），**照抄 IP 例程约束，不要自己重算**，并配
  `set_clock_uncertainty {0.200} [get_clocks {ddrphy_clkin}] -setup -hold`。
- 有异步 FIFO 的两端**必须**登记 `set_clock_groups`；有双打拍同步器的慢速控制信号
  用 `set_false_path` 或按目的域周期给 `set_multicycle_path`（本项目 `constr/lane_detect.fdc`
  用的是后者，且注释写明了理由）。
- 同一对时钟**不要同时**写 `set_clock_groups` 和 `set_multicycle_path`（后者会失效）。

### 3.3 约束自检

```
python scripts/fdc_audit.py <你的.fdc>          # 时钟组覆盖 / 未约束时钟 / 危险 set_false_path
python scripts/pinmap_query.py --dup            # 引脚重复占用检查
```

---

## §4 电平、BANK 与资源预算

### 4.1 BANK 与电平（错一个就上不了板）

| BANK | 电平 | 约束 |
|---|---|---|
| BANK0 | **可调**（默认 3.3V，经 `VCCADJ`） | 改电压需改电源电阻；承载 LED/按键与 J5 |
| BANK1 / BANK2 | 3.3V | 普通 IO，扩展口主力 |
| BANK3 | **固定 1.5V** | 挂 DDR3，不可改 |
| HSST BANK | 差分 | 4 路 RX/TX + 1 对参考时钟（125MHz 差分晶振） |

### 4.2 资源预算（以 PGL50H 总量为分母）

| 资源 | 总量 | 官方例程实测占用（HDMI+DDR3+OV5640） |
|---|---|---|
| LUT | 42,800 | 5,417（12.66%） |
| FF | 64,200 | 5,412（8.43%） |
| DRM18K | 134 | 19.5（14.55%） |
| APM | 84 | 0 |
| IO | 296 | 136（45.95%） |

> 经验：这套"视频 + DDR3 + HDMI + 摄像头"外壳在 LUT/FF 上很宽裕，
> **真正的紧箍咒是 DRM18K(134) 和 APM(84)**——行缓存、帧缓存、卷积阵列先算这两个。
> 例程时序已达 **All Constraints Met**（WNS 最小 1.692ns @ioclk0）。

### 4.3 三条容易踩的硬件事实（都经引脚级核对）

1. **HSST 通道 0/1 与 PCIe X2 物理共用**（`MGT_TX0/RX0`=PCIe lane0，`MGT_TX1/RX1`=lane1），
   通道 2/3 给 SFP0/SFP1。→ PCIe 与 SFP 可同时用，但**不能让 SFP 去抢通道 0/1**。
2. **HDMI 输入/输出共用一根复位网络（R17）**，`W22` 还是收/发双向复用脚
   （`HD_RX_MU_MC` / `HD_TX_SC_MC`）。→ 初始化序列要同时迁就 MS7200 与 MS7210。
3. **OV5640 摄像头是插在 40pin 扩展口 J8 上的**（例程 `cmos1_*`/`cmos2_*` 与 `EX_IO_*`
   逐脚重合）。手册明令：**40pin 外接设备必须经电平转换，切勿直连**。

---

## §5 上板排查顺序（怀疑硬件时按此序）

1. **供电**：底板 12V → 5V；核心板 1.2/3.3/1.5/HSST_1.2；`POWER` 灯亮否。
2. **配置通路**：下载器实测为 **`PANGO USB CABLE II`**（D2XX/ftd2xx），
   JtagServer 监听 `127.0.0.1:65420`，器件 IDCODE `0x10521899`。
   `DONE` 灯亮否？固化（`.sfc` → QSPI）后重新上电能否自启动？
3. **时钟**：50MHz 在 P20；125MHz 差分只在 HSST 参考输入（普通逻辑用不到）。
4. **DDR3**：先跑通 DDR3 IP 自带的 example_design（`source/rtl/DDR3_50H/`），
   再看 `ddr_init_done`。Bank3 固定 1.5V，DQ/DQS 分组见 `reference/pinmap.md`。
5. **外设**：HDMI 输入/输出各是独立芯片（MS7200 收 / MS7210 发），
   I2C 从地址 **MS7200 = 0x56（SA 下拉）、MS7210 = 0xB2（SA 上拉）**——初始化不通先查这里。
6. **引脚**：拿本技能的 `reference/pinmap.md` 与工程 `.pcf` 逐条对齐（用 `pinmap_query.py --dup`）。

## §6 参考文件与脚本

| 文件 | 内容 |
|---|---|
| `reference/pinmap.md` | **逐信号引脚分配**（每外设分节；已过 FBG484 几何校验 + 与官方 PCF 零冲突 + 与 V1.0 手册零差异） |
| `reference/pinmap.csv` | 机器可查引脚库（`domain,signal,package_pin,io_standard,bank,note,source`），**以 1V1 手册为权威重新生成** |
| `reference/manual-caveats.md` | **手册疑点台账**（17 条：排版粘连、自相矛盾、与 PCF 冲突的判定结论 + 同脚多用途清单） |
| `reference/manual-1v1-delta.md` | **两版手册差异台账**：引脚 0 差异、器件型号更新、1V1 修正的 6 处排版病灶、插图裁决、桌面 DXF 定性 |
| `reference/pds-flow.md` | PDS 环境事实/阶段表/产出物字典/8 条操作红线/资源与时序基线/JTAG 固化（实测，带 file:line 证据） |
| `schematics/` | **33 张原理图/框图**（逐图取两版手册中更清晰者，按图号命名）+ `README.md` 索引与"要做什么查哪张图" |
| `scripts/build_pinmap.py` | 从手册重建文本 + 官方 PCF **确定性生成** pinmap（可复现、可审计） |
| `scripts/pinmap_query.py` | 按关键词/外设/引脚查表；`--dup` 分级查重复占用 |
| `scripts/csv2pcf.py` | 引脚 CSV → PCF，自动带 VCCIO/IOSTANDARD/DRIVE/SLEW（用法见 `scripts/example_pins.csv`） |
| `scripts/fdc_audit.py` | `.fdc` 静态审查 C1–C8：生成时钟、时钟组覆盖、滥用 false_path、多周期冲突 |

> 与本仓库既有技能的衔接：时序约束深挖 → `timing-constraints-fdc`；
> RTL 骨架纪律 → `rtl-module-scaffold`；提交前静态自检 → `verilog-lint-gate`。
