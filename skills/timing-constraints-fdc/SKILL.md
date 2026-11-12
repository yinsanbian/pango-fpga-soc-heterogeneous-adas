---
name: timing-constraints-fdc
description: 为紫光同创 PDS 生成并审查 .fdc 时序约束：主时钟、PLL 衍生时钟、生成时钟关系、IO 延时、跨时钟域 set_clock_groups/set_false_path、例外路径。用于 SYS-01 早期约束介入，避免时序分析结果失真。
---

# PDS 时序约束（.fdc）生成与审查

服务于 `docs/04-工作流程.md` §六 与避坑 #16/#17/#18（目标 ID：**SYS-01 → SYS-02/03**）。

## 何时用

- **W6 起就要写**，不是 W13 才补（避坑 #16：后期补约束 = 大量违例 + 高返工成本）
- 新增时钟域、新增跨域通路、新增外部接口时**增量更新**

## 本项目时钟域盘点

| 时钟 | 来源 | 频率 | 用途 |
|---|---|---|---|
| `clk_25m` | 板载晶振 | 25 MHz | 配置/慢速逻辑 |
| `clk_pixel` | PLL 衍生 | 74.25 / 148.5 MHz | 1080P 像素时钟 |
| `clk_dvp` | OV5640 PCLK | ~84 MHz | 摄像头采集域 |
| `clk_ddr` | PLL 衍生 | 400 MHz（示例） | DDR3 控制器 |
| `clk_sys` | PLL 衍生 | 100 MHz | 图像处理流水线 / 软核 |
| `clk_hdmi` | PLL 衍生 | 依分辨率 | HDMI TMDS |

> ⚠️ **每个 PLL 输出都必须显式声明为生成时钟**，否则时序分析"看似收敛，实则不收敛"（避坑 #17）。

## 约束模板骨架

```tcl
# ============ 1. 主时钟 ============
create_clock -name clk_25m -period 40.000 [get_ports clk_in]

# ============ 2. PLL 衍生 / 生成时钟 ============
create_generated_clock -name clk_sys   -source [get_pins <pll>/CLKIN] -divide_by 1 -multiply_by 4 [get_pins <pll>/CLKOUT0]
# 每个 PLL 输出逐条声明，不可遗漏

# ============ 3. 外部输入时钟（DVP PCLK 由摄像头驱动）============
create_clock -name clk_dvp -period 11.900 [get_ports cam_pclk]

# ============ 4. IO 延时 ============
set_input_delay  -clock clk_dvp -max 4.000 [get_ports cam_data*]
set_input_delay  -clock clk_dvp -min 1.000 [get_ports cam_data*]
set_output_delay -clock clk_pixel -max 3.000 [get_ports hdmi_data*]

# ============ 5. 跨时钟域例外 ============
# 异步 FIFO 两端（两个域不再做时序关联）
set_clock_groups -asynchronous -group [get_clocks clk_dvp] -group [get_clocks clk_sys]
set_clock_groups -asynchronous -group [get_clocks clk_sys] -group [get_clocks clk_ddr]
# 已在 RTL 中用双打拍同步器处理的慢速控制信号
set_false_path -from [get_clocks clk_sys] -to [get_clocks clk_dvp]

# ============ 6. 异步复位 ============
set_false_path -from [get_ports rst_n]

# ============ 7. 伪路径 / 多周期（谨慎，须有理由）============
# set_multicycle_path 2 -setup -from ... -to ...
```

## 审查要点

- [ ] **每个 PLL 输出都有 `create_generated_clock`** —— 逐个数，别漏
- [ ] 每条跨域通路**要么有同步器 + `set_false_path`，要么有异步 FIFO + `set_clock_groups`**，二者必居其一
- [ ] `set_false_path` **不得滥用**去掩盖真实违例（这是自欺欺人，上板必炸）
- [ ] `set_multicycle_path` 必须写理由注释，说明为何该路径可放宽
- [ ] 约束文件纳入版本控制，**改动需在周会同步**（约束 bug 极难定位）

## 验收

- [ ] PDS 时序报告 **WNS/TNS ≥ 0**（SYS-02 720P 保底，SYS-03 1080P 目标）
- [ ] 报告中的时钟列表与上表**逐条对得上**（对不上说明有隐藏未约束时钟）
- [ ] 报告存 `reports/timing_<日期>.rpt`

> 若 W13 仍有负 slack → 触发 **R6**：降频换余量 / 插入流水级 / 放宽非关键约束（03 文档避坑表）。
