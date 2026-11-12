# 第三方内容与许可说明（NOTICE）

本仓库的原创代码、文档与脚本采用 MIT 许可（见 LICENSE）。以下内容**不属于**本项目的 MIT 授权范围，
按各自原始来源的许可使用：

## 1. 厂商 FPGA 工具与 IP（紫光同创 Pango / 盘古）
- `fpga/100pro/src/pg100_mainline_board_top.v` 与 `fpga/50k/rtl` 中例化的 DDR3 IP、`GTP_PLL_E3`、
  `GTP_CLKBUFG` 等原语，其实现与仿真模型由 PDS 工具链提供，**不在本仓库内**。
- `fpga/100pro/bitstreams/*.sbit|*.smsk`、`fpga/50k/bitstreams/*.sbit|*.smsk` 为 PDS 生成、
  含厂商 IP 的预编译位流，仅用于本项目复现与测试；再分发/商用前请自行确认厂商许可。
- 使用本仓库构建需要合法的 PDS 授权（PDS Lite 对 PGL50H 免授权）。

## 2. 开发板厂商示例（小眼睛科技 MES2L676-100HP / MES50HP）
`fpga/50k/vendor/mes50hp/` 下的
`video_mode_control.v`、`ms7200_ctl.v`、`ms7210_ctl.v`、`ms72xx_ctl.v`、
`i2c_com.v`、`iic_dri.v`、`power_on_delay.v`
来自板卡厂商提供的 HDMI 回环示例工程，本项目仅作**构建依赖**保留（工程以相对路径引用），
其版权与许可归原厂所有，不随本仓库的 MIT 授权。

## 3. 模型与数据集
- 本仓库**不包含**任何训练权重（`.pt/.rknn/.onnx`）。`README` 中提到的 YOLOv8n 检测模型
  基于 Ultralytics（AGPL-3.0），使用/分发其权重需遵守 AGPL-3.0。
- 演示与评测使用的 nuScenes / BDD100K 数据**未包含**在本仓库，需按各自数据集许可自行获取。

## 4. 算法与论文参考
Canny (1986)、Lucas–Kanade (1981)、Hough 参数空间 FPGA 实现、ByteTrack (2022)、
OpenCV 文档等仅作算法参考，列于设计说明书参考文献。

## 5. 隐私处理
仓库内的示例配置已把内网地址、用户名与本地密钥路径替换为占位值
（`192.168.1.100`、`user@`、`~/.ssh/id_ed25519`）。
