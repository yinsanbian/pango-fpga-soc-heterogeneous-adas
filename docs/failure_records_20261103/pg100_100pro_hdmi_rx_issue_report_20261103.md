# PG100 100Pro HDMI RX / 采集 / PGM1 问题报告

- 日期：2026-11-03
- 对象：盘古 100Pro（PG2L100H-6IFBG676，B 工程 `final_board_20261015_r8_typec_uart_B`）
- 上游：盘古 50K（PGL50H-6IFBG484，`video_n1_uart_burst8.sbit`）
- 来源：RK3568（`user@192.168.1.100`）通过 eth1 直连 50K（10.10.20.1 ↔ 10.10.20.2），UDP 5000 发送两路 960×540 RGB565（ch2 前视、ch3 后视，带 PGM1 marker）
- 视频链：50K HDMI OUT（1080p60）→ 100Pro HDMI IN（MS7200）→ 100Pro FPGA 直通 + 采集 → 100Pro HDMI OUT → USB 采集卡 → PC（OBS / OpenCV）
- 调试口：100Pro PGC2 = COM15；50K N1 状态 = COM16；JTAG = `cdt_js.exe -port 65420` + `cdt_cfg.exe`

## 0. 结论摘要

100Pro 的采集核心逻辑已经跑通过（08:25 位流：`captured≈30fps`、`frame_cycles=2,474,999`、`active_lines=1080`），但当前有两个未收敛的问题：

1. **MS7200 HDMI RX 在 FPGA 重配置后随机锁不上**：`vs_pin` 60Hz、`vs_cap=0`、无 DE/有效数据，直通输出黑屏；同一 RTL 同一接线，重烧多次“有时锁、有时不锁”。
2. **RX 锁定时采集仍大量丢帧，PGM1 身份校验失败**：`discarded≈30/s`，`bad_identity` 增长，`good_identity=0`；50K 输出顶部的 PGM1 条带疑似相对 100Pro 解码窗口（y=8..23）下移。

## 1. 构建与版本

| 项目 | 值 |
|---|---|
| PDS | 2025.2-SP3-EN（`D:\PDS23.2\PDS_2023.2-SP3-ads\pango\PDS_2025.2-SP3-EN-ads`） |
| 100Pro 工程 | `D:\worktress\11f1\ziguang\fpga100\pds\pg100_mainline\final_board_20261015_r8_typec_uart_B\pg100_mainline_board_top.pds` |
| 当前烧写位流 | 18:58 诊断版，SHA256 `58b055b25a03cd6794e1e04be6e33c35417238ba011f720ff675c71d270a960e` |
| 当前 SMSK | SHA256 `5d7b6560cda8ae2df32e6ca2dd7ec0e34552048e27bd9b352b56922c64d7a81c` |
| 当前诊断版时序 | `TNS=-15070ps, WNS=-468ps`（异步调试 CDC 引入；`Some Constraints Violated`） |
| 已知干净版时序 | B60 干净版 `All Constraints Met`：hdmi_pclk +0.649ns、DDR +0.477ns、PHY DQ +0.002/+0.757ns |
| 50K 位流 | `video_n1_uart_burst8.sbit`，SHA256 `63dd3e1610e255c6330bf3cf5cf2b30651aea2fe292b7f05286cce39b11da498` |
| 50K SMSK | `c7486234...`（来自 `mosaic_n1_uart/prj_tasks/pnr_1/generate_bitstream/mes50hp_mosaic_top.smsk`） |
| RK 发包 | `/home/neardi/fpga_send/send_raw_pgm1.py --front videos/input_front_40534313_1792470582.rgb565 --rear videos/input_rear_39397166_1792470582.rgb565 --fps 20 --batch 8`，实测约 12–15fps |

## 2. 已确认正常的事实

- [x] 50K 收流正常（COM16）：
  - 例：`RAW=0x07F5FB29 GOOD=0x07F5FB19 REJ=0x10 FCS=0 PBAD=0 HDR=0x10 IP=0x0A UDP=0 BANK=0 BEAT=0xFE9F32A0 FRM=0x33 DROP=0x1CBE9`
  - `RAW/GOOD/BEAT` 持续增长。
- [x] 50K HDMI 输出正常：
  - 采集卡直插 50K OUT 可看到完整 2×2 拼屏 + 顶部 PGM1 条带（用户两次确认，并有截图）。
- [x] 100Pro 直通输出曾正常：
  - 17:07 前后 OpenCV 从采集卡抓到正确彩色拼屏（`probe9_1.png`）。
- [x] 100Pro 采集曾完全正常（08:25 位流）：
  - `pclk_edges=580`（148.5MHz，1ms 窗口）
  - `vs_pin≈vs_cap≈60Hz`
  - `frame_cycles=2,474,999`（精确 CEA 2200×1125）
  - `active_lines=1080`
  - `captured` 约 30fps 增长
  - `discarded=0`
- [x] 修复了一个确定的综合问题：
  - `wire vrise=vs_in && !vs_d;` 被 PDS 提升到 capture 模块之外（netlist 出现 `.vrise(\capture/vrise)`），某些 seed 下采集永远看不到 vrise：`vs_pin` 增长、`vs_cap=0`。
  - 把边沿判断内联进 always 块后，16:51 / 17:07 版本恢复。

## 3. 故障清单

### I1. MS7200 HDMI RX 在 FPGA 重配置后随机锁不上（最高优先级）

**现象**

- 重烧 100Pro 后，部分次数：
  - `vs_pin`（clk27 域对 `hd_rx_vs` 的上升沿计数）≈60Hz 正常增长；
  - `vs_cap`（pclk 域 capture 内 vrise 计数）=0；
  - `captured=0`、`discarded=0`；
  - 100Pro HDMI 输出黑屏（采集卡 1920×1080 帧 mean≈0–1；用户也确认 OBS 无信号）。
- `state=0x87f`：`ddr_init=1、cpd_lock=1、hdmi_config=1、video_ready=1、link_gigabit=1、rgb_confirmed=1、run=1`。
- `pixel_clock_good=1` 要求 1ms 窗口内 270–630 个 pclk 边沿，说明 TMDS 时钟存在；但无有效 DE/VS 数据。

**关键证据：同一接线、同一 50K 源、仅重烧位流**

| 时间 | 位流 | 结果 |
|---|---|---|
| 18:28 | 回退 marker 窗口（无一次性重初始化） | RX 锁定：`vs_pin 2204→2354`、`vs_cap 2203→2353`、`disc 70→84`、`bad_identity 2→4` |
| 18:43 | 加 commit_reason 诊断 | RX 未锁：`vs_pin 2160→2406`、`vs_cap=0`、`cap=disc=0` |
| 18:58 | 改 DE 活动看门狗 | RX 未锁：`vs_cap=0`（等待 20s 后仍为 0） |

**已尝试的恢复手段**

- VS 空闲 2s 看门狗 → 无效：RX 解锁时 VS 可能自由跑，看门狗永不触发。
- 上电 8s 强制重初始化一次 → 用户反馈“最新位流不显示”，会破坏已锁状态。
- DE 活动 1s 看门狗 + `init_done` 门控（当前 18:58 版）→ 仍无效。
- 100Pro 冷启动 + 带源重烧 → 仍失败。
- 直接重烧（不冷启动）→ 有时成功、有时失败。

**待判断**

- MS7200 的正确初始化/恢复序列（HPD、EDID、RX 复位、等待 TMDS 稳定、I2C 配置时序）。
- 为什么重配置会随机失败：I2C 配置与 TMDS 源之间的竞争？`pg100_hdmi_config` 中 `SETTLE_CYCLES=9,450,000`（350ms）是否足够/过长？

### I2. 采集提交全被丢弃（RX 锁定时）

**现象（18:28 版，RX 已锁）**

- 时序正常：`frame_cycles` 精确、`vs_cap` 正常，但 `captured` 基本不涨，`discarded` 约 30/s 增长。
- `bad_frame=1` 间歇出现，`bad_reason=0x28`：
  - bit3 = DE 起点结构异常（`line_seen || active_lines>=HEIGHT || !hs_seen`）；
  - bit5 = 帧/行计数 clamp（`frame_cycles>=2,600,000` 或 `line_cycles>=HTOTAL+64`）。
- 多数采样 `reason=00、bad_frame=0` 但仍在丢帧 → 提交条件中的 `!de_in && !de_d`、`active_lines∈[1078,1088]` 或 `frame_cycles∈[2.4M,2.6M]` 失败。

**已加入但尚未读到有效数据的诊断**

- 18:43 版加入 `commit_reason[3:0]`：
  - bit0 = VS 边沿时 `de_in||de_d`
  - bit1 = `active_lines` 超出窗口
  - bit2 = `frame_cycles` 超出窗口
- 该版 RX 未锁，未获得有效值。

### I3. PGM1 身份校验失败（能提交时）

**现象（17:07 版，少量帧提交）**

- `good_identity=0`，`bad_identity=6→15` 持续增长。
- 50K 输出顶部确实有 PGM1 条带（用户截图 + 采集卡实帧）。
- 从采集卡 640×360 内容看，条带位于内容第 4–10 行，换算到 1080p 约 y=12–31；而 100Pro 解码窗口固定为 `x<1152 && y∈[8,24)`。
- 曾把窗口放宽到 `y<40`（17:22 版），随后出现显示异常/黑屏（见 I4），已回退。

**待判断**

- 应在 RK 端调整 marker 的 y/左右分段，还是在 100Pro 端放宽解码窗口更稳妥。
- PGM1 条带经过 50K 拼屏后是否被缩放/裁剪（2px cell 是否仍为 2px）。

### I4. 宽 marker 窗口构建导致显示异常

**现象**

- 17:22 版仅改解码器 `in_region`（`y<40`），烧写后 100Pro 输出变黑/偏绿；回退到 `y=8..23`（18:27 版）后画面恢复正常（用户发过正常彩色截图；本报告附带的正常图）。
- 纯解码窗口的改动理论上不影响直通/颜色，怀疑是 PDS 2025 新 seed 的布局/时序或优化副作用。
- 诊断位流本身有 `WNS≈-203～-468ps、TNS≈-13.6～-15.1ns`（异步调试 CDC 导致；非最终交付版）。

### I5. 50K 的 FRM/DMA 计数冻结（是否相关待判断）

- COM16：`FRM=0x33`、`DMA=0x1CBE9`、`DROP=0x1CBE9` 长时间不变，而 `RAW/GOOD/BEAT` 持续增长。
- 50K HDMI 直连采集卡画面正常，因此这些计数器含义不明，暂不作为故障判据。

## 4. 诊断接口与寄存器

### 4.1 100Pro PGC2（COM15，115200）

- `command(opcode=4)` → 16 字节 ACK（PGA2）+ 176 字节 PGS2。
- PGS2：40 个 big-endian word，从偏移 12 开始。
- 当前诊断映射（18:58 版）：

```
w0  : profile = 2
w1  : native_clock_hz = 125000000
w2  : 状态位 {native_clk_good, fault, recovering, busy, export, run,
              rgb_confirmed, link_gigabit, video_ready, hdmi_config, cpd_lock, ddr_init}
w3  : accepted_frames
w4  : completed_frames
w5  : dropped_frames
w6  : superseded_frames
w7  : rejected_frames
w8  : recovery_events
w9-14 : completed_points / read_bytes / active_cycles
w15-31: 读/写/网络计数
w32 : frame_cycles（capture 域，vrise 时锁存）
w33 : active_lines（capture 域，vrise 时锁存）
w34 : captured_frames
w35 : discarded_frames
w36 : vs_cap（capture 域 vrise 计数）
w37 : {commit_reason[3:0], bad_reason[7:0], overflow, bad_frame, ready_rgb, pixel_rst_n}
w38 : good_identity_frames
w39 : bad_identity_frames
```

`bad_reason` 位定义：

```
bit0: de_in && (vs_in || hs_in)
bit1: HS 边沿时 de_in || de_d
bit2: 行宽 != WIDTH（DE 结束）
bit3: DE 起点结构异常（line_seen || active_lines>=HEIGHT || !hs_seen）
bit4: line_cycles 超出 HTOTAL±64
bit5: frame_cycles / line_cycles clamp
bit6: 帧起点 de_in
bit7: overflow
```

`commit_reason` 位定义：

```
bit0: VS 边沿时 de_in || de_d
bit1: active_lines 超出 [HEIGHT-2, HEIGHT+8]
bit2: frame_cycles 超出 [2,400,000, 2,600,000]
```

### 4.2 50K N1 状态（COM16，115200，周期文本）

```
N1 RAW=... GOOD=... REJ=... FCS=... PBAD=... HDR=... IP=... UDP=...
   BANK=... BEAT=... FRM=... DROP=...
N2 S4DP=... S5DP=... DMA=... DAW=... DWD=... DRAN=... CYCL=...
```

### 4.3 采集卡抓帧

- OpenCV DirectShow 枚举：card 曾为 index 1（1920×1080）；OBS 运行时设备被占用。
- 抓到的 1080p 帧中，实际内容可能只在左上角 640×360（采集卡/驱动行为），但可判断有无信号与大致画面。

## 5. 时间线（2026-11-02）

| 时间 | 事件 |
|---|---|
| 05:43 | B60 干净版构建，`All Constraints Met` |
| 06:54 | 调试/容差版烧写 100Pro |
| 07:02–07:05 | 50K 复位后重烧 `video_n1_uart_burst8.sbit`，校验通过 |
| 08:25 | 看门狗版烧写，采集完全正常（`captured≈30fps`） |
| 16:51 | 内联 vrise 后采集恢复（`fc=2,474,999`、`disc` 增长） |
| 17:07 | bad_reason/放宽致命检查版，少量提交（`cap=1`、`bad_identity` 增长） |
| 17:22 | 放宽 marker 窗口（y<40），显示异常/黑屏 |
| 17:37 | 加 8s 一次性重初始化，仍异常 |
| 18:13 | 去掉一次性重初始化（窗口仍宽），`vs_cap=0` |
| 18:27/18:28 | 回退 marker 窗口，RX 锁定、采集恢复、显示正常 |
| 18:43–18:58 | 加 commit_reason、改 DE 看门狗；两次重烧 RX 均未锁 |

## 6. 代码位置与关键修改

- 100Pro 顶层（PDS 实际编译源）：[pg100_mainline_board_top.v](file:///D:/worktress/11f1/ziguang/fpga100/pds/pg100_mainline/final_board_20261015_r8_typec_uart_B/pg100_mainline_board_top.v)
- 回退点：`pg100_mainline_board_top.v.bak_before_vsdiag`
- 镜像 RTL（供参考）：
  - `D:\worktress\11f1\ziguang\fpga100\rtl\video\pg100_hdmi_capture.v`
  - `D:\worktress\11f1\ziguang\fpga100\rtl\video\pg100_hdmi_frontend.v`
  - `D:\worktress\11f1\ziguang\fpga100\rtl\control\pg100_board_reset.v`
  - `D:\worktress\11f1\ziguang\fpga100\rtl\transport\pg100_frame_marker_decode.v`
- 50K 工程：`D:\worktress\01e6\ziguang\fpga_video\diagnostics\rx_alignment_20261023\mosaic_n1_uart`
- 烧写脚本：[program.tcl](file:///C:/Users/yq/AppData/Local/Temp/pango_B_60fps/program.tcl)

关键修改：

1. 60Hz 适配：`pg100_board_reset` 窗口 `MIN_EDGES=270、MAX_EDGES=630`；`frame_skip` 60→30 抽帧。
2. `pg100_hdmi_capture` 内联 `vs_in && !vs_d` / `hs_in && !hs_d`，避免 PDS 提升 vrise 导致的假死。
3. 提交窗口：`active_lines∈[HEIGHT-2, HEIGHT+8]`、`frame_cycles∈[2.4M, 2.6M]`。
4. `pg100_frame_marker_decode` 的 `in_region` 当前为原始 `x<1152 && y∈[8,24)`。
5. RX 看门狗当前为 DE 活动 1s + `init_done` 门控（18:58 版），未验证有效。

## 7. 给 Claude 的问题

1. **MS7200 初始化/恢复**：FPGA 重配置后随机锁不上（pclk 有、`init_done=1`、无 DE/VS）。正确的 HPD/EDID/RX 复位/I2C 配置序列是什么？是否需要先拉低 HPD、等待 TMDS、再配置？
2. **随机性来源**：同一 RTL、同一接线、仅重烧位流，成功/失败交替出现。I2C 配置与源之间的竞争如何消除？`SETTLE_CYCLES=9,450,000`（350ms）是否合理？
3. **PDS 综合风险**：`wire vrise=vs_in&&!vs_d` 被提升到模块外导致采集假死，是否说明该写法在 PDS 2025 下有已知风险？还有哪些类似写法需要改写？
4. **PGM1 适配位置**：条带经 50K 拼屏后疑似下移（约 y=12–31）且可能缩放。改 RK marker 的 y/分段，还是放宽 100Pro 解码窗口？宽窗口构建导致显示异常是否只是 PDS seed 噪声？
5. **50K 计数器**：`FRM=0x33、DMA=0x1CBE9` 冻结但 N1 GOOD 增长，这些计数在该位流里代表什么？是否说明 50K 显示的是冻结帧？
6. **提交判据**：采集提交条件（行数/帧长/DE 门）在 50K 输出上大量失败，是否应把提交判据完全交给 PGM1 身份 + 光栅完整性，而不是时序硬门限？

## 8. 当前状态与建议下一步

- 当前 100Pro 运行 18:58 诊断位流（DE 看门狗 + commit/bad reason 诊断），RX 未锁，采集为零。
- 50K 收流正常，HDMI 直连采集卡画面正常。
- 最近一次确认显示正常：18:27 位流（marker 窗口 y=8–23、无一次性重初始化）。
- 最近一次确认采集正常：08:25 位流（`captured≈30fps`）。

建议下一步（按优先级）：

1. 先解决 RX 锁定的确定性问题（HPD/复位/配置序列），再做采集/PGM1 调优。
2. 在 RX 锁定的位流上读取 `commit_reason`，收敛丢帧原因。
3. 用 50K 输出实帧（全分辨率）核对 PGM1 条带的实际 y 与 cell 宽度，再决定 RK 端还是 100Pro 端适配。
4. 最终交付前用干净版（去掉调试 CDC）重构建，确认 `All Constraints Met`，并更新 deliverables 与功能清单。
