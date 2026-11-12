# 夜瞳异构（NightEye Heterogeneous）— 开源快照 2026-11-03

双 FPGA + RK3568 协同的边缘视觉感知平台。三个节点各司其职：

| 节点 | 器件 | 职责 |
|---|---|---|
| 50K | PGL50H-6IFBG484（MES50HP） | 千兆收流、DDR3 帧缓存、1080p60/30 HDMI 输出、车道几何流水 |
| 100 Pro+ | PG2L100H-6FBG676（MES2L676-100HP） | HDMI 接收/转发、帧标记（PGM1）解析、DDR 帧存储、UART 状态 |
| RK3568 | 临滴 RK3568（4 GB） | YOLOv8n RKNN 推理、帧号同帧关联、UDP 结果输出 |
| PC | Windows / Python | Dashboard 可视化、评测与证据归档 |

本仓库是**阶段性开源快照**：包含可复现的 RTL、约束、位流、上位机/板端脚本、
MCP 工具、项目技能与全部调试记录（含失败记录）。所有"未实现 / 未验证"的项在
文档中显式标注，不把方案当作实测结论。

## 目录

```
docs/                 设计说明书、实测数据表、失败记录（docs/failure_records_20261103/）
reports/figures/      说明书插图与脚本（PNG/PDF/MATLAB）
evidence/             位流证据索引（已删除工程的 sbit+smsk SHA256）
fpga/100pro/          PG2L100H：单文件展开顶层 + 约束 + 两版位流
fpga/50k/             PGL50H：分模块 RTL + 约束 + 厂商依赖 + 30fps 变体 + 位流
rk3568/               RK 板端推理/融合进程与 FPGA 发送脚本
pc/dashboard/         PC Dashboard（AVM3D 渲染与数据源）
tools/pango-mcp/      Pango PDS/ModelSim/JTAG 的 MCP 服务端（自研）
skills/               本项目使用的 9 个项目技能（PDS 约束、RTL 骨架、量化导出等）
```

## 关键位流

| 板卡 | 文件 | SHA256 | 说明 |
|---|---|---|---|
| 100 Pro+ | `fpga/100pro/bitstreams/pg100_100pro_23479887_display_ok.sbit` | `23479887…62f5b9c82c` | 实板验证可出图（50K 1080p60 源） |
| 100 Pro+ | `fpga/100pro/bitstreams/pg100_100pro_seed2_83aabfc2.sbit` + `.smsk` | `83aabfc2…7411b4c` / `c5555701…` | 交付基线（mask 成对烧写） |
| 50K | `fpga/50k/bitstreams/video_n1_uart_burst8_63dd3e16.sbit` + `.smsk` | `63dd3e16…bda498` / `c7486234…` | N1 单口 1080p60 |
| 50K | `fpga/50k/bitstreams/video_n1_uart_30fps_c668719e.sbit` | `c668719e…6ac0` | 1080p30 变体（PLL 6→12 / FDC div 4） |

## 构建与烧写要点

1. **工具链**：PDS 2025.2-SP3-EN（PG2L100H / PGL50H）、ModelSim 10.7。
2. **100 Pro+**：`fpga/100pro/src` 为单文件展开顶层（`pg100_mainline_board_top.v`），
   约束 `fpga/100pro/constraints/pg100_mainline_board_top.fdc`。
   烧写后**必须**通过 COM15 发一条 `opcode=1 (run + RGB888 confirmed)`，
   否则 HDMI 输出被 `ready_rgb` 门控关闭。
3. **50K**：`fpga/50k/rtl` 为分模块源码，`vendor/` 为工程以相对路径引用的厂商文件，
   约束 `fpga/50k/constraints/mosaic.fdc`。30fps 改法见 `fpga/50k/variant_30fps/`。
4. 已知问题（详见 docs）：
   - 100 Pro+ 重烧后 MS7200 锁 60Hz 呈抽签，需逐版实板验证；
   - 1080p60 源下捕获提交为 0/s，1080p30 源可提交；
   - `accepted_frames` 在两种源下均为 0（commit 未到达 store）。

## 许可

本项目原创代码与文档采用 **MIT License**（见 `LICENSE`）。
第三方内容（厂商 IP、HDMI 芯片配置表、含厂商 IP 的预编译位流、模型权重）
保留其原始许可，详见 `NOTICE.md`。

## 致谢与引用

算法参考：Canny (1986)、Lucas–Kanade (1981)、Hough 参数空间 FPGA 实现、
ByteTrack (2022)、Ultralytics YOLO、RKNN-Toolkit2、Pango PDS。
