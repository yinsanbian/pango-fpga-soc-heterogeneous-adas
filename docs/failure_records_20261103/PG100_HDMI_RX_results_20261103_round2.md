# PG100 HDMI RX 第二轮调试结果与证据（2026-11-03 04:10）

板卡：PG2L100H（100Pro），输入源：50K N1 HDMI / PC HDMI，工具链：PDS 2025.2-SP3-EN
UART：COM15（PGC2/PGS2），JTAG：cdt_js/cdt_cfg @65420

---

## 1. 本轮最重要的三个结论

### 结论 A：像素相位=x0（相位0）已被硬证据锁定，解码器已恢复
在 `pg100_hdmi_capture` 第 20 行（`active_lines==20`）对 `rgb_in` 的 x=0..63 做 64 位白像素移位采样，
上传到 PGS2 w5/w6（bit63=最早= x0）：

```
实测: 1100110000111100001100111100110011000011001111000011001100111100
期望: 1100110000111100001100111100110011000011001111000011001100111100   (逐位相同)
```
期望值 = PGM1 编码器 `white_pixel = x[1] ? ~data_bit : data_bit`、每 bit 4 像素、从 x=0 起，
SYNC 0xD391C5A7 的前 16 bit（0xD3,0x91）的 Manchester 展开。

⇒ 捕获侧 x/y 与源光栅严格对齐；之前改成 `mx = x - 1`（相位1）是错的（会切开 2px 半格）。
解码器已恢复为与 `board/rtl/pg100_frame_marker_decode.v` **逐字节一致**
（`in_region = x<1152 && y>=8 && y<24`，`mx = x`），`diff` 为空。
对应位流 `2f66ce56…`（01:28），时序 All Constraints Met（WNS +0.383 ns / TNS 0）。

### 结论 B：提交门每帧都拒绝；PC 源能过、50K 源不能
在 `23479887`（02:18 构建）上通过 130 位握手邮箱读出：

| 输入源 | cap_commit | discard | bad_id | pxdrop | accepted |
|---|---|---|---|---|---|
| 50K N1（1080p60） | **0** | 30.3/s | 30.3/s（随丢弃） | 30.3/s | 0 |
| PC（EDID 1080p30） | **~5.3/s** | ~25/s | ~25/s | ~25/s | 0 |

- `rejected_identity` 恒 0 且 `accepted` 恒 0 ⇒ **publish 从未发生**，问题在提交门之前/处，
  不是身份校验拒绝（`pg100_mainline_board_top.v` 里 rejected 只在 publish_valid 时计数）。
- 同一块板、同一根线、同一时刻，仅换输入源就出现 commit ⇒ **提交门对源时序敏感**。
- PC 源仍 83% 丢弃，说明除了源差异外还有第二个因素。

### 结论 C：新构建的位流会让 MS7200 完全无输入（RX 全黑）
诊断位流 `69343aa6`（04:08，把原始 RX 引脚计数与 HDMI 配置状态映射到状态字）读数：

```
rxv=0 (无 VS)   rxh≈500~1000/0.5s(噪声)   rxd≈32.4 kHz(DE 上升)
freq_value=0x00  freq_tries=99  freq_forced=1  freq_state=5
flags=0x87F（ddr_init_done/cpd_lock/hdmi_config_ready/video_ready/link/rgb/run 均为 1）
capture: frame_cycles=0 active_lines=0 line_cycles=0 vs=0 bad_frame=0 reason=0
```

- 状态字 flags 与正常态**完全一致**，但捕获域一个 VS 都没有。
- MS7200 对 0x209E 的读**有 ACK 且返回 0** ⇒ 芯片在线、I2C 读通路正常，但**测不到输入**。

**位流 A/B 对照（每次烧写后 25~30 s 再发 opcode=1，再采样；输入源不变）**

| 位流 | SHA256 前8 | 构建时间/方式 | 结果 |
|---|---|---|---|
| B | `23479887` | 02:18 **PDS GUI** | ✅ 捕获活（discard 30.3/s） |
| C | `cb766e9d` | 02:40 MCP | ❌ 全 0 |
| D | `10be8ec7` | 03:08 MCP | ❌ 全 0 |
| D' | `10be8ec7` 重烧 | — | ❌ 全 0 |
| E | `f3bb14cf` | 03:29 MCP | ❌ 全 0 |
| E2 | `9cb6896b` | 03:46 MCP | ❌ 全 0（PC 源同样为 0） |
| B 重烧 | `23479887` | 03:47 | ✅ 又活（180→407，30.3/s） |
| F | `69343aa6` | 04:08 MCP | ❌ 全 0（但可读出上面那组 RX 原始计数） |

⇒ 6/6 与位流严格相关，且 E2 相对 B 只改了提交门限两个常数，与 HDMI RX 初始化无关。
B 恰好是唯一由 **PDS GUI** 产生的位流；其余均为 `pds_shell -project … -run gen_bit_stream`。

---

## 2. 关键代码事实（供复核）

### 2.1 HDMI 配置 FSM 的 0x209E 频率门（`pg100_hdmi_config`）
```
FREQ_RD: if(done) begin
    dbg_freq_value<=read_value;
    if(success && read_value[1:0]==2'b10) begin
        reading<=0;index<=9'd304;retry<=0;state<=PREPARE;      // 成功也跳 304
    end else if(freq_tries>=16'd99) begin
        freq_forced<=1;dbg_freq_forced<=1;reading<=0;index<=9'd304;state<=PREPARE;
    end else begin
        freq_tries<=freq_tries+1'b1; ... wait_count<=32'd2700000;state<=FREQ_GAP;
    end
```
- ROM 条目 300..303 是 `0x209C..0x209F ← 0x00`（清测量寄存器），**两条路都跳过**，故该门不改变视频寄存器写入内容，只改变"等 10 s 还是立即继续"。
- 因此 `forced=1` **不是**全黑的原因（但它是一个假阴性门：已证明有有效 1080p60 时该寄存器仍可能读 0）。
- 对照：`B_seed2`（已知可用交付版）**没有这个频率门**，直接写完整张表。

### 2.2 捕获提交门（`pg100_hdmi_capture`，当前）
```
if (!bad_frame && !overflow &&
    active_lines>=1000 && active_lines<=1088 &&
    frame_cycles>=2000000 && frame_cycles<=2800000) commit
else discard
```
- `bad_frame` 目前**只**由 `overflow` 置位（其余条件均已降级为 reason 位）。
- `overflow` = `pixel_storage_overflow` ← line CDC 的 `pixel_control_overflow`（PCLK 域）。
- `frame_skip = rate60_sync[2]`，`rate60 = (measured_edges > 400)`，是"pclk≈148.5MHz 档"的判据，
  **不是**帧率判据；`edges` 为 1 ms 窗口计数（1080p60≈580，1080p30≈290）。
- 帧抽稀（`frame_skip`）**只减帧数、不减单帧像素率**：被抓的那一帧仍是 124 Mpixel/s。

### 2.3 EDID
`hdmi_config_rom.vh` 中 EDID 为 **128 字节 RGB1080p30-only**（vendor 原样）。
⇒ 合规源（PC）会输出 1080p30；50K N1 是固定 1080p60 发生器，不看 EDID。
实测 DE 上升 ≈32.4 kHz（≈1080p30 的 33.75k 行频），与 EDID 推断一致。

---

## 3. 已排除项

| 假设 | 排除依据 |
|---|---|
| 解码器相位错 | 64 位原始像素探针逐位匹配（结论 A） |
| 身份校验拒绝导致 accepted=0 | rejected_identity 恒 0；publish 从未发生 |
| marker 条带不在输入上 | 探针在第 20 行 x0..63 采到完整条带 |
| 50K 无 HDMI 输出 | 换 PC 源同样跑；B 位流下两种源都能捕获 |
| 邮箱位宽/参数化导致读 0 | 改回 B 位流的 130 位显式结构后仍读 0，且 A/B 对照可复现 |
| 0x209E 假阴性门 | 两条路都跳过 300..303，写入内容相同（见 2.1） |
| DDR 初始化失败 | flags bit0/bit1 恒 1；无 recovery 增长 |

---

## 4. 待验证的假设（按可能性排序）

**H1（最高）：单帧像素带宽打满导致 overflow，从而 bad_frame 恒真。**
- 支持：50K=1080p60（124 Mpixel/s）→ 0 commit；PC=1080p30（62 Mpixel/s）→ 有 commit。
- 但 PC 仍有 83% 丢弃，说明还有第二个因素，需实测 `bad_frame/overflow` 才能定论。
- 验证方法：把 `bad_frame`（VS 锁存值）和 overflow 粘滞计数映射到状态字后读取。

**H2：PC 实际并非 1080p30（或 50K 并非标准 1080p60），几何窗口不匹配。**
- 需要 `frame_cycles / active_lines / line_cycles` 的实测值（前两次遥测构建都因 H3 而全 0）。

**H3：新构建位流使 MS7200 无法锁定输入（本报告结论 C）。**
- 这是当前**最阻塞**的问题：所有新构建都黑屏，导致任何新遥测都读不到捕获数据。
- 可能方向：PLL/复位释放与 MS7200 上电时序的竞态；或 PDS 实现差异影响 MS7200 复位/HPD。
- 关键未读信号：`i2c_failure_code`、`i2c_retry_count`（typec_uart 里有，但本工程 UART 由
  `pg100_local_control` 驱动，TYPC 周期帧不在线上，需另映射）。

**H4：MCP `pds_shell -run gen_bit_stream` 与 GUI 构建存在实现差异。**
- 6/6 相关性支持；但两者命令等价（都是从 `-run` 入口），需要一次 GUI 构建交叉验证。

---

## 5. 建议的下一步（优先级）

1. **先解决 H3**：让任意新构建都能上电。
   - 最小验证：请用 PDS GUI 对当前源码构建一次，烧写后看 `rxv` 是否非 0。
   - 若 GUI 构建正常 → 固化 GUI 构建流程用于交付；若同样失败 → 说明与构建方式无关，
     需在 MS7200 复位/I2C 上加可观测点（把 `i2c_failure_code`/`i2c_retry_count` 映射到状态字）。
2. **再解决 H1/H2**：在能上电的位流里暴露 `bad_frame`、overflow 粘滞位、`frame_cycles`、`active_lines`。
3. 交付版恢复：w5/w6/w11–w18 回到协议原义；`0x209E` 门降级为纯遥测（不跳过 300..303 也可，
   但建议照 `B_seed2` 直接写全表，去掉 10 s 空等）。
4. `ddrphy_sysclk → phy_dq_sysclk_0` 的 −0.015 ns 单端点违例：交付前需重跑 PnR 清掉。
5. 明暗判定：光流仍**没有任何证据**，不得声称可用。

---

## 6. 本轮位流清单（archive 目录 `fpga100/pds/pg100_mainline/archives/`）

| 时间 | SHA256 | 说明 |
|---|---|---|
| 01:28 | `2f66ce56…` | 相位0解码器，无探针（时序全通） |
| 02:18 | `23479887…` | **唯一能上电 RX 的位流**（GUI 构建，130 位邮箱） |
| 02:40 | `cb766e9d…` | 322 位参数化邮箱（遥测全 0） |
| 03:08/03:29/03:46 | `10be8ec7… / f3bb14cf… / 9cb6896b…` | 显式宽度/载荷交换/放宽门限，均黑屏 |
| 04:08 | `69343aa6…` | 原始 RX 计数 + 配置状态诊断（黑屏，但读到结论 C） |

---

# 补录：04:10–05:00 追加实验（构建可复现性问题 + 源差异）

## A. PC 源确认
- Windows 侧枚举：`PGG | PG100-1080P | active=True`，支持模式 **1920x1080@30**
  （`WmiMonitorListedSupportedSourceModes`），桌面布局 DISPLAY2 = 1920x1080。
- ⇒ PC 确实在向 100Pro 输出 **1080p30**（与 ROM 里 1080p30-only 的 EDID 一致）。

## B. 旧交付位流（11-02 `83aabfc2`，seed2）在 PC 源下是活的
```
pixel_drops 0 → 140（11.6/s）   accepted=0 completed=0 rejected=0 dropped=0  flags=0x87F
```
捕获域在跑（有帧被丢），说明 RX 锁上了。对比同一时刻新构建全黑 ⇒ **不是环境/线缆/源的问题**。

## C. 构建可复现性：RX 能否上电与位流强相关（8 黑 / 2 活）
新增实验全部为黑屏：
- 清空 `prj_tasks`（syn_1/pnr_1 整份移走）后全新建：`36334b58` ❌
- 分阶段构建（`-run dev_map` → `-run pnr`，等价 GUI 逐任务）: `4927b78f` ❌
- 之前：`cb766e9d` `10be8ec7`(×2) `f3bb14cf` `9cb6896b` `69343aa6`(×2) ❌
活着的只有：`23479887`（02:18 GUI 构建）、`83aabfc2`（11-02 seed2）
- 工程 seed 固定为 2；工具版本两版都是 `Fabric Compiler 2025.2-SP3-EN<231170>`。
- E2(`9cb6896b`) 相对 B(`23479887`) **只改了提交门限两个常数**，却一个活一个黑 ⇒ 不能用源码差异解释。

⇒ 结论：**RX 上电/配置对实现结果敏感（边际），当前无法用"重建一次"复现可用位流**。
交付必须"一版一验"，并保留已验证位流存档。

## D. 黑屏态的确切特征（诊断位流 `69343aa6`）
```
rxv=0（无 VS）   rxd≈32.4 kHz（DE 上升沿，≈1080p30 行频）   rxh 噪声
freq_value=0x00  freq_tries=99  freq_forced=1  freq_state=5(FINISH)
pclk 存在（pixel_clock_good=1，由 pclk/512 心跳在 1ms 窗口计数 270..630 判定）
I2C probe（向 0x2B/0x59 的 reg 0x0003 写 0x5A 再回读）通过 ⇒ init_done=1，写通路正常
```
⇒ 芯片在线、I2C 可写、有像素时钟，但**不出 VS**（像处于自由运行/未锁状态）。

## E. overflow 的真实语义（更正）
`pg100_pixel_line_cdc`：
- `overflow`（送进 capture 的 `pixel_storage_overflow`）= **commit 元数据 FIFO(8 深) 溢出**，
  即 `commit_valid && !control_ready`（第 5182 行），不是像素 FIFO 溢出。
- 像素 FIFO 溢出走 `s_status_overflow`，只影响 `dropped_frames` 计数，不进 `overflow`。
- `bad_frame` 现在只由 `overflow` 置位 ⇒ 若 commit FIFO 不溢出，捕获不会因 overflow 丢帧。

## F. 源速率差异（最重要的产品级线索）
| 位流 | 源 | 结果 |
|---|---|---|
| `23479887` | 50K 1080p60 | commit **0/s**，discard 30.3/s |
| `23479887` | PC 1080p30 | commit **5.3/s**，discard 25/s |
| `83aabfc2` | PC 1080p30 | 捕获丢弃 11.6/s（⇒ 约 18/s 提交） |

⇒ 30 Hz 源可以提交，60 Hz 源完全不能。**帧抽稀（frame_skip）只减帧数、不减单帧像素率**，
抓到的 60 Hz 帧仍是 124 Mpixel/s 灌进 CDC/store。
若该假设成立，50K 链路必须让源出 30 Hz，或让 100Pro 真正支持 60 Hz 输入。

## G. 建议（更新）
1. **立刻冻结**可用位流 `83aabfc2`（板上是它）；交付只认"上电 + RX 锁定"实测通过的位流。
2. 排查 60 Hz 失败：需要一版"能上电 + 带几何遥测"的位流——目前新构建 0/8，
   建议先用 seed2 源码做基线再叠加最小遥测，并做多次构建抽签直到上电，再读 `frame_cycles/active_lines/bad_frame`。
3. 若要根治"重建即黑屏"：在 `hd_rx_de/hs/vs/rgb*` 上补 `set_input_delay`（当前 FDC 完全没有输入延时约束），
   并考虑在 DE 看门狗触发时对 MS7200 做**硬复位 + 重配**（当前只重跑 I2C，不拉 rstn_out）。
4. 50K 链路若要尽快验收：优先确认 50K 是否能出 1080p30；否则需在 100Pro 内加真正的 60→30 帧率转换（含带宽）。

---

# 当前硬件状态（2026-11-03 05:25 留档）

| 板卡 | 当前位流 | SHA256 | 烧写时间 |
|---|---|---|---|
| 50K (PGL50H) | N1 交付版 60fps `video_n1_uart.sbit` | `4a3d6fdd…` | 05:22:44 |
| 100Pro (PG2L100H) | seed2 交付版（60Hz 稳定显示） | `83aabfc2…` | 05:24:58（done bit=1） |

- 50K 30fps 试验版存档：`D:/ziguang/release/n1_uart_20261103_30fps/`
  （`c668719e…`，含 README.md 说明改动/构建/验证/回退）。
- 30fps 试验结论：100Pro 捕获丢弃率 60fps=30.3/s → 30fps=11.7/s（≈PC 1080p30 的 11.6/s），
  帧率切换生效；但 `accepted/dropped/rejected` 仍全 0，卡点转移到
  「capture→CDC→store 的 SOF/tag 握手」（`owner_valid / capture_tag 匹配` 段）。
- 100Pro 重新烧写后 `video_ready=0`（MS7200 无像素时钟），需确认 50K→100Pro 的 HDMI 连接后再复测。
- 更正：50K 的交付/在用位流是 **`video_n1_uart_burst8.sbit`（63dd3e16，mask c748）**，
  05:22 曾误烧 `video_n1_uart.sbit`（4a3d6fdd），05:34:20 已用 burst8 覆盖并 verify 通过。
- 100Pro 于 05:24:58 重烧 seed2（83aabfc2）后 `video_ready=0`（无像素时钟），
  与"重烧后 RX 上电边际"现象一致，待 KEY0 逻辑复位或再次重烧验证。
- **恢复记录（05:52）**：100Pro 烧回 **02:18 构建 `23479887`**（无 mask）后，
  用 50K 60Hz（burst8 `63dd3e16`）源 **RX 锁定、画面恢复**：
  `video_ready=1`、capture commit **0/s**、discard **30.0/s**、bad_id 随丢弃增长、
  `accepted/dropped/rejected` 仍全 0（T13 状态不变）。
- 同一会话内 seed2（`83aabfc2`+mask `c5555701`）多次重烧：PC 1080p30 源可锁，
  50K 1080p60 源反复锁不上（LED1 灭）⇒ **重烧后 RX 能否锁 60Hz 仍是抽签**，
  交付前一律以实板"上电 + 60Hz 锁定"实测为准；`23479887` 是本次验证可用的 60Hz 版本。
