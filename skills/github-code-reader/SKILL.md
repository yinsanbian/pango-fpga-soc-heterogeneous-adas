---
name: github-code-reader
description: 稳定读取 GitHub 仓库代码：镜像下载 API 树与 raw 文件（绕开 web_fetch 100KB 截断与直连超时）、GBK 编码探测转码、输出结构化仓库分析报告。当用户给出 GitHub 仓库链接要求阅读或参考代码时使用。
---

# GitHub 仓库代码读取

## 何时用

- 用户给出 GitHub 仓库地址，要求阅读/评估/参考其代码
- 需要获取仓库文件树、某个文件的内容、或 README

## 环境事实（决定策略，勿用直连）

1. **GitHub 直连在本机间歇性超时**（curl 实测 15s+，`web_fetch` 会报 `fetch failed`）。
2. `web_fetch` 对 API JSON 响应有 **100KB 截断**，大仓库树会被拦腰截断。
3. 中文 FPGA 项目源码常为 **GBK 编码**，read 工具只认 UTF-8。
4. 本机无 git CLI 在 PATH（有 `C:\Program Files\Git\cmd\git.exe` 全路径）；本机有 Python 3.13。

## 标准流程（按顺序执行）

### 步骤 1 · 取仓库文件树（绕开截断）

用 **PowerShell 下载到本地文件**，不要用 `web_fetch`：

```powershell
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# 镜像优先级：gh-proxy.com → ghproxy.net → 直连（ghfast.top 实测超时，不用）
Invoke-WebRequest -Uri "https://gh-proxy.com/https://api.github.com/repos/<owner>/<repo>/git/trees/<branch>?recursive=1" -OutFile "D:\ziguang\gen\repo_tree.json" -TimeoutSec 60 -UseBasicParsing
```

- 默认分支不是 main 就试 master。
- 下载后先用 Python 解析：统计文件数、扩展名分布、顶层目录，再决定细读哪些文件。

### 步骤 2 · 取具体文件（走 raw 镜像）

```powershell
$base = "https://gh-proxy.com/https://raw.githubusercontent.com/<owner>/<repo>/<branch>/<path>"
Invoke-WebRequest -Uri $base -OutFile "D:\ziguang\gen\ref_repo\<basename>" -TimeoutSec 45 -UseBasicParsing
```

### 步骤 3 · 编码探测后转 UTF-8（关键，中文 RTL 必踩）

read 工具遇 GBK 直接报 `invalid UTF-8 text`。用 Python 探测并转码：

```python
raw = open(path, "rb").read()
text = None
for enc in ("utf-8", "gbk"):
    try:
        text = raw.decode(enc); used = enc; break
    except UnicodeDecodeError:
        continue
if text is None:
    text = raw.decode("utf-8", "replace"); used = "utf-8(replace)"
open(path + ".utf8.txt", "w", encoding="utf-8").write(text)
```

然后 read 转码后的 `.utf8.txt`。

### 步骤 4 · 输出结构化分析报告

写 `gen/repo_analysis.txt`（UTF-8），包含：
- 仓库定位（README 摘要、项目性质）
- 自研代码 vs 官方 IP/例程 的区分（排除 `ipcore` `ip_backup` `sim_lib` `example_design` `generate_netlist`）
- 按用户目标映射：哪些文件可直接参考、哪些是噪声
- 许可证检查（LICENSE 文件）

## 避坑

- **不要在 TS 模板字符串里嵌套 PowerShell 变量**（`${env:...}` 会触发 TS 解析错误）。用 `[Environment]::GetEnvironmentVariable()`。
- 控制台输出中文会变 GBK 乱码：**结果一律写 UTF-8 文件再用 read 读回**，不要在 stdout 打中文。
- Python 脚本先写到 `tools/_*.py` 再执行，不要用 `python -c` 内联（引号转义地狱）。
- web_fetch 失败不要立刻放弃：换镜像域名重试，GitHub 直连是间歇性的，不是恒断。
- 仓库很大时先做"关键词命中"（如 `yolo|cnn|conv|npu`）再决定细读，不要全量下载。
