# 官方 vs 当前 freq_rec 判定逻辑差异

- 日期：2026-11-03
- 官方源码：`D:/pg100pro/盘古100Pro+开发板（MES2L676-100HP）配套资料/2_Demo/2_10_hdmi_loop.rar` 内 `2_10_hdmi_loop/2_10_hdmi_loop/source/ms7200_ctl.v`
- 当前工程：`D:\worktress\11f1\ziguang\fpga100\pds\pg100_mainline\final_board_20261015_r8_typec_uart_B\pg100_mainline_board_top.v`

## 1. 官方 freq_rec 的逐字节拼装（源码证据）

STA_RD 状态按 `dri_cnt` 读四个寄存器（`ms7200_ctl.v`，STA_RD 的地址选择）：

```
dri_cnt 0 -> 0x209C
dri_cnt 1 -> 0x209D
dri_cnt 2 -> 0x209E
dri_cnt 3 -> 0x209F
```

`freq_rec` 的拼装（`ms7200_ctl.v`，STA_RD 的 `byte_over` 分支）：

```
9'd0 : freq_rec <= {freq_rec[31:8],  data_out};              // 0x209C -> [7:0]
9'd1 : freq_rec <= {freq_rec[31:16], data_out, freq_rec[7:0]}; // 0x209D -> [15:8]
9'd2 : freq_rec <= {freq_rec[31:24], data_out, freq_rec[15:0]}; // 0x209E -> [23:16]
9'd3 : freq_rec <= {data_out, freq_rec[23:0]};               // 0x209F -> [31:24]
```

因此：

```
freq_rec[7:0]   = 0x209C
freq_rec[15:8]  = 0x209D
freq_rec[23:16] = 0x209E
freq_rec[31:24] = 0x209F
```

**结论：`freq_rec[17:16]` = `0x209E[1:0]`。当前实现只读 `0x209E` 并检查 `read_value[1:0]==2'b10`，寄存器与位映射是正确的（不是 0x209D 或别的字节）。**

## 2. 官方 freq_ensure 的判定语义

`ms7200_ctl.v`：

```
// assign freq_ensure = (freq_rec_1d[17:16]==2'b00) && (freq_rec[17:16] == 2'b10);
...
else if(state_n == STA_RD && dri_cnt == 9'd2 && busy_falling &&
        (freq_rec_2d[17:16]==2'b00) && (freq_rec_1d[17:16] == 2'b10))
    freq_ensure <= 1'b1;
```

`freq_rec_1d/2d` 是 `freq_rec` 在 clk 下的两级延迟（`freq_rec_1d <= freq_rec; freq_rec_2d <= freq_rec_1d;`）。检查点在 `dri_cnt==2` 的 `busy_falling`：

- 此时 `freq_rec` 正在装入 `0x209E` 字节；
- `freq_rec_1d` 是装入前一拍的值（其中 `[17:16]` 对应上一轮 `freq_rec` 的 bit17:16，即上一次采样/上一字节组合结果）；
- `freq_rec_2d` 再早一拍。

官方要求看到 `00 -> 10` 的**状态变化**，而不是单次等于 `10`。

## 3. 当前实现 vs 官方：差异表

| 项目 | 官方 `ms7200_ctl.v` | 当前 `pg100_hdmi_config` | 差异/影响 |
|---|---|---|---|
| 初始化写入 | 索引 0–299，共 300 条 | 索引 0–299，共 300 条 | 一致 |
| 表后等待 | `WAIT` 状态 `delay_cnt==10,000,000`（50MHz 下 200ms） | `FREQ_WAIT` 使用 `SETTLE_CYCLES=9,450,000` clk27 = 350ms | 数值不同；350ms 更长，理论上不引入竞争；需实测确认 |
| 频率读取寄存器 | 0x209C/0x209D/0x209E/0x209F 四字节 | 只读 0x209E | 映射正确（见 §1），但未验证四字节整体序列 |
| 频率判定 | `00 -> 10` 变化（`freq_rec_2d/1d`） | 单次 `0x209E[1:0]==2'b10`，失败每 100ms 重试，100 次后强制 | 语义不完全等价；单次 `10` 在稳定锁定时应成立，但官方的 `00->10` 可能用于排除读取瞬态/旧值 |
| 读回校验 | 只看 freq；scratch 0x0003=0x5A 在 CONECT | probe 0x0003=0x5A；freq 失败仅计数 | 一致（均未逐条读回 360 条写） |
| 使能序列 | `0x1010=01, 0x1024=00, 0x0200=00, 0x1024=70, 0x0200=07, 0x0215=01, 0x0215=00` | 索引 304–310，完全相同的 7 条 | 一致 |
| 使能条件 | 仅当 `freq_ensure` 为真才进入 SETING | 频率失败 100 次后**强制**进入索引 304 | **不等价**：强制使能不代表 RX 已验证锁定 |
| 后续 | 进入 MS7210 配置（`ms72xx_ctl` 顺序） | 索引 311–359 继续写 MS7210 | 顺序一致（需核对 360 条总表完整性） |
| 完成标志 | `init_over` 在 SETING 第 7 条后置位 | `init_done` 在写完 360 条后置位 | 语义不同：官方以“使能序列完成”为完成，我们以“全部表完成”为完成 |
| 复位 | 板级 G25 低有效；官方未在 ctl 内单独复位 RX | G25 由 `pg100_board_reset` 在每次配置后拉低约 100ms | 一致（共享复位） |

## 4. 实测数据与判读

19:41 烧写（`02ad9819…`），19:42 连续 8 次读取：

```
w29 freq_value = 0x00      // 0x209E 读回 0x00
w30 freq_tries = 99        // 达到强制阈值
w31 freq_state = 0x5       // FINISH；hdmi_init_failed=0
w36 vs_cap = 0
w34 captured = 0
w37 = 0x3                  // ready_rgb=1, pixel_rst_n=1
```

判读（按新方案的证据规则）：

- `0x209E=0x00` 说明 `freq_rec[17:16]` 没有出现 `10`；**但新方案要求先确认位映射和读取有效性，不能据此单独断言“无 TMDS”**。
- 位映射已确认正确（§1）；I2C 读取路径由 probe 0x0003=0x5A 证明可用；但 0x209E=0 仍可能是“无输入频率测量”或“该寄存器在未使能前不更新”。
- 需要阶段 2 的 pclk 域原始 `VS/HS/DE` 计数来回答“RX 是否真的输出同步信号”。

## 5. 最小补丁建议（不等同已验证）

1. 频率判定改为与官方一致：连续采样 0x209E，检测 `[1:0]` 从 `2'b00` 到 `2'b10` 的变化，而不是单次等于 `10`。
2. 将“强制使能”单独标记 `forced=1 / init_valid=0`，不得当作初始化成功。
3. 增加四字节遥测（0x209C–0x209F），确认 `freq_rec` 整体值（例如 148.5MHz 是否对应 0x00024414）。
4. 增加 pclk 域 `rx_vs_rise/rx_hs_rise/rx_de_rise/rx_de_high` 计数 + 一致快照，用数据判断层级。
5. 保留 08:25 成功版本的线索：目前位流已被覆盖，需要从备份/历史构建中恢复，否则无法做 A/B 回归。
