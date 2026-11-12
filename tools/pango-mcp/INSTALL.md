# 导入和配置

压缩包内有两种分发方式：

- `pango-mcp-local.mcpb` 是 MCP Bundle，可在支持 MCPB 的客户端（例如 Claude Desktop）中导入。导入时按需选择本机的 `pds_shell.exe`、PDS license 文件、ModelSim `bin` 目录和 ModelSim license 文件。MCPB 规范正在推广中，其他客户端未必能导入 `.mcpb`。
- `pango-mcp-portable.zip` 是通用源代码包。解压后用 Node.js 18.17+ 启动 `src/index.mjs`，并按相应客户端配置文件登记 stdio 服务。

## 通用客户端配置

1. 解压到一个固定目录，例如 `C:\tools\pango-mcp`。
2. 安装 Node.js 18.17 或更新版本。服务无 npm 依赖，不需要安装 node_modules。
3. 复制 `pango-mcp.env.example` 到 MCP 目录之外的位置，例如用户配置目录，并替换 PDS、ModelSim 和 license 路径。
4. 将 MCP 服务配置添加到 Agent。Claude Code、Claude Desktop 和 Cursor 可从 `examples/portable.mcp.json` 的 `mcpServers` 部分开始；VS Code 使用 `examples/vscode.mcp.json`；Codex 使用 `examples/codex.config.toml`。

示例中的路径是占位符。所有本机的绝对路径都必须改成目标机器上的位置。配置完成后重启或刷新 Agent 的 MCP 工具目录，并调用 `fpga_env` 检查路径。

## 其他 Agent 的 stdio 配置

大多数本地 MCP 客户端都可以启动 stdio 服务。基本配置值如下：

```json
{
  "command": "node",
  "args": ["C:/path/to/pango-mcp/src/index.mjs"],
  "env": {
    "PANGO_MCP_PDS_2025": "C:/path/to/PDS/bin/pds_shell.exe",
    "PANGO_LICENSE_FILE": "C:/path/to/PDS/license.lic",
    "PANGO_MCP_MODELSIM_HOME": "C:/path/to/ModelSim/win64",
    "PANGO_MCP_MODELSIM_LICENSE": "C:/path/to/ModelSim/license.dat"
  }
}
```

各 Agent 的配置文件层级和属性名称可能不同；只需把上面的 `command`、`args`、`env`、`cwd` 值放入它支持的本地 stdio MCP 配置中。请不要把真实 license 文件内容放进配置或压缩包；这里只需要传文件路径。

## 手动运行

PowerShell 示例：

```powershell
$env:PANGO_MCP_PDS_2025 = 'C:\path\to\PDS\bin\pds_shell.exe'
$env:PANGO_LICENSE_FILE = 'C:\path\to\PDS\license.lic'
$env:PANGO_MCP_MODELSIM_HOME = 'C:\path\to\ModelSim\win64'
$env:PANGO_MCP_MODELSIM_LICENSE = 'C:\path\to\ModelSim\license.dat'
node .\src\index.mjs
```

MCP stdio 服务会等待 Agent 通过标准输入/输出进行协议通信；直接运行后看不到命令行提示属于正常情况。不要在同一个终端手动输入自然语言。
