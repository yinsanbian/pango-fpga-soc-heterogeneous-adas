# 已删除工程副本的位流证据索引（2026-11-03）

删除原则：只保留**位流 + mask + SHA256** 作为证据，工程目录（综合/布局布线/日志）全部删除。

| 工程副本 | 位流 SHA256（前16） | 构建时间 |
|---|---|---|
| INDEX.md | `-` | - |
| final_board_20261014 | `889d64c0c88539d6` | 2026-10-13 18:25:45 |
| final_board_20261014_r7 | `ee552e5587e6fc8e` | 2026-10-14 03:22:15 |
| final_board_20261015_r8 | `94d878ffc871c0a0` | 2026-10-14 19:28:03 |
| final_board_20261015_r8_typec_uart | `62172250e123deb1` | 2026-11-02 01:41:03 |
| final_board_20261015_r8_typec_uart_B_seed3 | `120f5165828eae2b` | 2026-11-02 03:55:33 |
| final_board_20261015_r8_typec_uart_opt2 | `d0e1c343e795c00e` | 2026-11-01 20:17:38 |
| final_board_20261015_r8_typec_uart_refclkbuf | `307a85329cd0bf31` | 2026-11-02 00:48:54 |
| final_board_20261015_r8_typec_uart_refclkbuf_seed2 | `c7bf68b7c4081c97` | 2026-11-02 00:45:21 |
| final_board_20261015_r8_typec_uart_refclkbuf_seed8 | `1957daf673b52357` | 2026-11-02 00:45:18 |
| final_board_20261015_r8_typec_uart_seed2 | `7a7c49e791176535` | 2026-11-01 19:55:14 |
| final_board_20261015_r8_typec_uart_seed3 | `011622e024e8c75f` | 2026-11-01 20:02:43 |
| final_board_20261015_r8_typec_uart_seed4 | `a8cd75b80ec7647d` | 2026-11-01 20:10:19 |
| final_board_20261015_r8_typec_uart_seed5 | `e55ee8c1058f5ff3` | 2026-11-01 20:25:57 |
| final_board_20261015_r8_typec_uart_seed6 | `f1ca08ebb13ef8f0` | 2026-11-01 20:26:04 |
| final_board_20261015_r8_typec_uart_seed7 | `5ec92b0e8e6b86a7` | 2026-11-01 20:33:55 |
| final_board_20261015_r8_typec_uart_seed8 | `45c7143663486ca0` | 2026-11-01 20:34:12 |
| m2_pageprobe_pds2025_20261101_build1 | `867299594fa3a9ec` | 2026-10-31 22:13:54 |
| mosaic | `f819703d7f4a230a` | 2026-10-29 08:15:09 |
| mosaic_m2_n1_stereo_20261030_build2 | `096303c549e3e208` | 2026-10-30 04:25:41 |
| mosaic_m2_n1_stereo_20261031_m2only_attempt1 | `472a9dca5456453c` | 2026-10-31 01:52:27 |
| mosaic_m2_n1_stereo_20261101_pds2025_rerun | `cf60914b1a886478` | 2026-10-31 19:15:34 |
| pnr_1.stale_20261103_0418 | `69343aa6f47734ef` | 2026-11-03 04:08:54 |

## 保留的工程

| 工程 | 用途 |
|---|---|
| `pg100_mainline/final_board_20261015_r8_typec_uart_B` | 100Pro 工作树（位流 23479887 来源） |
| `pg100_mainline/final_board_20261015_r8_typec_uart_B_seed2` | 100Pro 交付基线 83aabfc2 + mask c5555701 |
| `pg100_mainline/board` | 100Pro 分模块 RTL（rtl/，已剥离构建产物） |
| `pg100_mainline/core_check` | 核心分模块 RTL + marker 编解码/测试（已剥离构建产物） |
| `pg100_mainline/archives` | 2026-11-03 全部 100Pro 位流存档 |
| `rx_alignment_20261023/mosaic_n1_uart` | 50K 当前源码（63dd3e16 burst8） |
| `rx_alignment_20261023/mosaic_n1_uart_30fps` | 50K 1080p30 变体源码（c668719e） |
| `rx_alignment_20261023/mes50hp` | 50K 引用的厂商源码 |
| `fpga_video/mosaic` | AGENTS.md 指向的 FPGA 主工作树 |
