# 原理图 / 框图索引（盘古50K MES50HP）

本目录的 33 张图来自**两版官方硬件手册**，从 PDF **内嵌对象按原始分辨率抽出**（不是截图）。

> **构成**：26 张主图**逐图取两版中像素更多的一版**（14 张取 1V1、12 张沿用 V1.0）
> ＋ 1V1 独有的 7 张（封面、DDR3 框图 4 张局部、DDR3 参考电压局部、底板尺寸局部）。
> 裁定记录与逐图尺寸见 `../reference/manual-1v1-delta.md` §5。
>
> **注意**：1V1 手册的**图注与插图整体错位一位**（图注在图上方/下方不统一），
> 故不能用"图注在哪个插图后面"来命名插图；本目录的命名经**页位顺序对齐 + 像素尺寸核对**。
>
> ⚠️ 手册的"原理图"是**关键网络连接示意**（含器件位号、网络名、上下拉/隔直电容），
> **不是完整 PCB 网表**。要逐网络追线仍需向厂商索取完整原理图。
> 桌面上的两个 `.dxf` 是 **PADS 导出的 PCB 版图**，同样不含网表（见文末）。

## 一、按图号索引

| 图号 | 文件 | 1V1 手册页 | 内容要点 |
|---|---|---|---|
| 图1-1 | `fig1-1_开发系统功能框图.jpg` | p5 | 核心板+底板整体功能框图（V1.0 版，3500×2040，最清晰） |
| 图2-1 | `fig2-1_logos系列FPGA命名规则.jpg` | p8 | PGL50H-6IFBG484 型号字段含义 |
| 图2-2 | `fig2-2_125MHz有源差分晶振原理图.png` | p9 | U7 有源差分晶振 → `HSST_CLK_P/N = A10/B10`，给 HSST 参考时钟 |
| 图2-3 | `fig2-3_50MHz有源单端晶振原理图.jpg` | p9 | U9 单端 50MHz → `FPGA_GCLK_50M = P20`（系统时钟） |
| 图2-4 | `fig2-4_27MHz有源单端晶振原理图.jpg` | p10 | U13 单端 27MHz → `FPGA_GCLK_27M = K21` |
| 图2-5 | `fig2-5_PGL50H与DDR3连接框图.png` | p10 | PGL50H ↔ 2×DDR3（16bit×2 → 32bit，接 BANK3） |
| — | `fig2-5b~2-5e_*` | p9-10 | 1V1 新增：DDR3 框图的分块/标注局部（"16bit×2" "BANK3" "32bit"） |
| 图2-6 | `fig2-6_DDR3参考电压及上拉跟随电压原理图.jpg` | p11 | DDR_VDDQ=1.5V / VTT=0.75V / VREF=0.75V，ZQ 240Ω 下拉 |
| — | `fig2-6b_DDR3参考电压原理图_局部.png` | p11 | 1V1 新增局部 |
| 图2-7 | `fig2-7_QSPI_Flash电路图.png` | p13 | QSPI Flash 连接（1V1 版 1105×603，**V1.0 缺此图**） |
| 图2-8 | `fig2-8_核心板电源树.jpg` | p20 | +5V → EZ8303 四路（+3.3/1.5/HSST_1.2/+1.2V），VCCADJ 可调 |
| 图2-9 | `fig2-9_核心板尺寸结构图.jpg` | p21 | 核心板 50×58mm，4×80Pin 板对板连接器位置 |
| 图3-1 | `fig3-1_RTL8211网口连接示例.jpg` | p23 | RTL8211 PHY ↔ PGL50H（RGMII；1V1 版 1142×679 更清晰） |
| 图3-2 | `fig3-2_PGL50H_HSST光纤连接框图.jpg` | p25 | HSST TX/RX ↔ 2 路 SFP（隔直电容耦合） |
| 图3-3 | `fig3-3_USB-UART原理框图.jpg` | p27 | CP2102 USB-UART 框图（V1.0 版 3463×2060） |
| 图3-4 | `fig3-4_USB-UART电路.png` | p27 | CP2102 具体电路（**V1.0 缺此图**） |
| 图3-5 | `fig3-5_JTAG连接座原理图.jpg` | p28 | 10pin JTAG，**信号上有保护二极管**（防带电插拔） |
| 图3-6 | `fig3-6_HDMI_Receiver(MS7200)连接示意图.png` | p29 | MS7200 HDMI 输入（I2C 从地址 **0x56**，SA 下拉） |
| 图3-7 | `fig3-7_HDMI_Transmitter(MS7210)连接示意图.png` | p31 | MS7210 HDMI 输出（I2C 从地址 **0xB2**，SA 上拉） |
| 图3-8 | `fig3-8_用户按键电路图.png` | p33 | 8 用户按键（低有效）+ 1 重加载按键（经延时复位芯片到 RSTN） |
| 图3-9 | `fig3-9_LED灯电路原理图.jpg` | p33 | 8 用户 LED（高电平点亮）+ POWER/INIT/DONE |
| 图3-10 | `fig3-10_EEPROM设计示意图.png` | p34 | 24LC02（2Kbit）IIC |
| 图3-11 | `fig3-11_SDCARD电路.jpg` | p35 | MicroSD（SPI + SD 模式，3.3V） |
| 图3-12 | `fig3-12_40pin扩展IO原理图.png` | p36 | J8 40pin：5V×1 / 3.3V×2 / GND×3 / IO×34 |
| 图3-13 | `fig3-13_PMOD座连接原理图.jpg` | p37 | J12 PMOD 12pin（BANK2，3.3V） |
| 图3-14 | `fig3-14_12V转5V原理图.jpg` | p38 | SGM61163：+12V → +5V（底板输入级） |
| 图3-15 | `fig3-15_5V转3.3V原理图.png` | p38 | SGM61032：+5V → +3.3V（外设接口） |
| 图3-16 | `fig3-16_扩展底板尺寸结构图.jpg` | p38 | 底板结构尺寸（V1.0 版 1369×820） |
| — | `fig3-16b_扩展底板尺寸结构图_局部.png` | p38 | 1V1 新增局部 |
| — | `cover_手册封面.png` | p1 | 1V1 封面（含厂商联系方式：support@meyesemi.com / QQ 群 808770961） |

## 二、按"要做什么"反查

| 我要… | 先看 |
|---|---|
| 确认某外设连接关系 | 对应 `fig3-x` |
| 查引脚号 | `pinmap.md` / `pinmap.csv`（图里也可能标了网络名与器件脚号） |
| 算功耗/上电顺序 | `fig2-8` 电源树 + `fig3-14/3-15` |
| 排查 DDR3 不初始化 | `fig2-5`、`fig2-6` + `pds-flow.md` 的 DDR3 IP 例程 |
| 排查 HDMI 不显示 | `fig3-6`（收）/ `fig3-7`（发）；先核对 I2C 从地址 0x56 / 0xB2 |
| 排查 JTAG 连不上 | `fig3-5` + `pds-flow.md` §6 驱动/虚拟网卡 |
| 新增外部模块接哪 | `fig3-12`(40pin) / `fig3-13`(PMOD) + `pinmap.md` 对应小节 |

## 三、桌面 `dxf/` 的定性（易误用，务必先读）

| 文件 | 实际是什么 | 能用来做什么 / 不能做什么 |
|---|---|---|
| `MES50HP-V1.0.dxf` | PADS PowerPCB ASCII 导出的**核心板 PCB 版图**（图层：`BOARD_OUTLINE_00` / `PADS_TOP` / `DRIL_PLTE_THRU_*` / `PART_TOP_2DLINE_*`），133 颗元件 | ✅ 机械尺寸、元件布局、接插件位置<br>❌ **不含网络连接关系**，不能替代网表 |
| `Mespcie_Base_Board_V1.1-9-13.dxf` | 同上，**底板**版图 | 同上 |

> 查"某信号接哪个引脚"仍以 `pinmap.md` / `pinmap.csv` 为准。
> ⚠️ 已尝试抽取位号/型号：坐标与型号可读，但**位号文本不全**（PADS 把位号放在块属性里），
> 需要完整 BOM 请直接向厂商索取。方法脚本见仓库 `tmp/pads_dxf_extract.py`。

## 四、再生成方式（可复现）

```
# 1) 版面重建两版手册文本（逐字坐标重排）
python tmp/pangu_pdf_extract2.py     # V1.0  -> tmp/pangu_manual.txt
python tmp/pangu_v11_extract.py      # 1V1   -> tmp/pangu_manual_v11.txt

# 2) 抽插图并按图号裁决清晰度
python tmp/compare_manual_figs.py    # 列出 1V1 全部插图
python tmp/align_and_merge_figs.py   # 页位对齐 + 像素尺寸比对
python tmp/build_skill_schematics.py # 生成最终图集

# 3) 重新生成引脚库（默认即以 1V1 为权威）
python ../scripts/build_pinmap.py
```
