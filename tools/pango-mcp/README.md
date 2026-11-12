# Pango MCP 本地重建版

这是根据 [pango-mcp 公开文档和工具接口](https://glama.ai/mcp/servers/Renkos1/pango-mcp/schema)独立编写的本地 MCP stdio 服务，供 Codex 调用 Pango Design Suite、ModelSim 和本机 FPGA 文档。原仓库源码已不可获取；本项目不是原仓库的源码恢复，也不宣称与原版全部 45 个工具兼容。

当前实现 30 个工具。只依赖 Node.js 18.17 或更新版本，无须 `npm install`。服务启动时不会运行 PDS、ModelSim 或连接板卡。

## 配置

把路径写到安装目录之外的环境文件，例如 `C:\Users\<you>\.codex\pango-mcp.env`：

```text
PANGO_MCP_PDS_2025=D:\PDS23.2\PDS_2023.2-SP3-ads\bin\pds_shell.exe
PANGO_LICENSE_FILE=D:\PDS23.2\License\new_pds_F4A80DA47D72.lic
PANGO_MCP_MODELSIM_HOME=D:\modelsim\win64
PANGO_MCP_MODELSIM_LICENSE=D:\modelsim\win64\LICENSE.TXT
```

`PANGO_MCP_PDS_2025` 是原文档使用的变量名；本重建版可用它指定 PDS 2023.2-SP3。模型仿真许可证路径只说明已配置文件位置，实际授权是否可用需要运行厂商工具才能确认。

在 Agent 的 MCP 配置中注册。Codex 的 TOML 例子：

```toml
[mcp_servers.pango]
command = 'node'
args = ['<解压目录>\src\index.mjs']
cwd = '<解压目录>'
startup_timeout_sec = 30
tool_timeout_sec = 3600

[mcp_servers.pango.env]
PANGO_MCP_ENV_FILE = '<用户配置目录>\pango-mcp.env'
```

将 `<解压目录>` 和 `<用户配置目录>` 替换成目标机器的实际路径。Claude Code、Claude Desktop 和 Cursor 可使用 `examples/portable.mcp.json` 中的 `mcpServers` 结构；VS Code 使用 `examples/vscode.mcp.json`。各客户端的配置格式略有区别，详见 `INSTALL.md`。

可选：设置 `PANGO_MCP_CONFIG_FILE` 为一个 JSON 文件路径，提供 `boards` 对象。每个板卡配置需要准确的 `family`、`device`、`speedgrade`、`package`，可选 `pins` 和 `clkFreqMhz`。代码不内置板卡型号或引脚。

## 工具

| 类别 | 已实现工具 |
| --- | --- |
| 环境、日志和波形 | `fpga_env`, `fpga_capabilities`, `fpga_assert`, `fpga_wave`, `fpga_log_extract`, `fpga_sim` |
| PDS 工程和构建 | `fpga_project_info`, `fpga_pds_reports`, `fpga_pds_run`, `fpga_pds_compile`, `fpga_pds_batch`, `fpga_pds_create_project`, `fpga_pds_create_blink_project`, `fpga_pds_register_fic`, `fpga_pds_scan` |
| ModelSim | `fpga_msim_compile`, `fpga_msim_sim`, `fpga_msim_do`, `fpga_msim_exe`, `fpga_msim_view`, `fpga_msim_doc_search` |
| 本机资料检索 | `fpga_primitive_lookup`, `fpga_ip_lookup`, `fpga_doc_search` |
| 离线配置文件 | `fpga_gen_sfc`, `fpga_gen_multi_file`, `fpga_gen_chain_file`, `fpga_jtag_gen_svf`, `fpga_ila_generate_fic` |
| PDS 受限命令 | `fpga_exe` |

`fpga_sim` 使用 Icarus Verilog。本机未发现 `iverilog` 和 `vvp` 时会返回明确错误；已有 ModelSim 可通过 `fpga_msim_sim` 使用。`fpga_pds_scan` 是只读 JTAG 链扫描，但仍需要连接板卡。`fpga_pds_register_fic` 只接受本机核对过的 PDS 2023.2-SP3 工程格式，并要求 `.fic` 指向该工程已生成的综合网表。`fpga_ila_generate_fic` 不验证信号网名是否真的存在于综合网表。

原版文档中的 SRAM/SPI 烧录、裸机 FT2232 JTAG、片上 ILA 抓取、远程主机和 knowledge vault 尚未重建。这些入口不出现在工具列表中。自定义 ModelSim Tcl 工具 `fpga_msim_do` 对非简单命令要求 `confirm:true`。

## 使用边界

PDS 构建和 ModelSim 仿真会运行用户提供的工程、HDL 和厂商程序，并可能在工程目录产生文件。日志结果同时检查退出码和厂商错误行；PDS 比特流阶段还检查新生成的输出。缓存位于工程目录内。当前已核对 MCP 握手、工具目录、本机路径和现有 `.pds` 的只读解析；尚未执行 PDS 编译、ModelSim 仿真、配置文件转换或任何板卡操作。
