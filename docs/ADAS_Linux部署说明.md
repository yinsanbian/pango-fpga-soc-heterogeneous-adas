# ADAS 可视化 —— Linux 部署说明

给的是"把 Windows 开发机上这套东西原样搬到 Linux"的最短路径。目标只有一个：
在 Linux 上打开 `http://127.0.0.1:8790/`，把视频拖进去，看到和 Windows 上一样的画面。

---

## 1. 一句话结论

代码本身**没有任何 Windows 专有依赖**（没有 `.cmd`、没有注册表、没有 Win32 API、
没有写死的字体文件）。需要改的只有三处绝对路径 —— 已经改完了，现在走
`tools/adas_paths.py` 统一解析，规则是"先看环境变量，没有再按仓库相对位置推算"。

所以 Linux 上**只要目录结构一致，不需要设任何环境变量**。

> **状态：已在 WSL2（Ubuntu 24.04.5）上端到端实测通过**，见 §9。不是"理论上可行"。
> 实测结论比预期还顺：坑 1（中文渲染）在 Linux 上**不存在**，而且 Linux 比 Windows **更快**。

---

## 2. 需要拷过去的文件（共 9 个）

运行时闭包很小。保持这个目录树即可：

```
<仓库根>/                                   ← 可以用 ADAS_ROOT 指到别处
├── traffic_yolo_deploy/deploy_rk3568/
│   ├── traffic9_postprocess.py             ← 前后处理（letterbox / DFL / NMS）
│   └── models/traffic9_split6_640.onnx     ← 检测模型 12.08 MB
└── tools/
    ├── adas_live.py                        ← 本地网页服务（入口）
    ├── adas_dash.py                        ← 仪表盘绘制 + AdasPipeline
    ├── adas_demo.py                        ← ByteTrack + 各类绘制原语
    ├── adas_paths.py                       ← 路径解析（新增）
    ├── lane_predict.py                     ← 车道回归头推理
    ├── lane_labels.py                      ← 采样行 / 形状基解码
    ├── requirements.txt
    ├── run_adas_live.sh
    └── _lane_runs/v9/lanenet.onnx          ← 车道模型 46.09 MB
```

**注意 `lane_predict.py` 不 import torch** —— 那条依赖早在 A 路线改造时就切掉了
（推理走 ONNX Runtime，形状解码在 `lane_labels.py` 里是纯 numpy）。所以部署机
**不需要装 PyTorch**，这是能搬上 Linux 的关键。

---

## 3. 装依赖

```bash
python3 -m venv .venv_linux
.venv_linux/bin/pip install -r tools/requirements.txt
```

`tools/requirements.txt` 的内容：

```
opencv-python>=5.0.0
numpy>=2.0
onnxruntime>=1.20
scipy>=1.11          # 可选
```

---

## 4. 跑起来

```bash
chmod +x tools/run_adas_live.sh          # 从 Windows 拷过去会丢执行位
./tools/run_adas_live.sh
```

或者不用脚本，直接：

```bash
python3 tools/adas_live.py --open
```

浏览器打开 `http://127.0.0.1:8790/`，拖视频进去。关掉终端就等于关服务。

`run_adas_live.sh` 会先自检依赖并打印检查结果，其中最后一行是**最要紧的那条**：

```
opencv   = 5.0.0
numpy    = 2.5.3
ort      = 1.29.0
Unicode 字体 = YES（中文能画）
```

---

## 5. 三个真的会踩的坑

### 坑 1：OpenCV 版本 —— 中文标签会全变成 `?`

仪表盘上每一处中文（「本车道中心线」「自车俯视」「本车道趋势」…）都是
`cv2.putText` 画的。**OpenCV 5.0 才带内置 Unicode 字体**：

```
cv2.getBuildInformation()  →
    Built-in Unicode font:       YES
```

4.x 的 Hershey 字体只认 ASCII，升级前整块面板会是问号。`run_adas_live.sh`
里那行自检就是专门查这个的。

好消息：这个字体是**编进库里的**，不需要 `fonts-wqy-zenhei`、不需要 fontconfig、
不需要 `matplotlib` 的中文配置。同一份 wheel，Windows 和 Linux 表现一致。

### 坑 2：onnxruntime 的架构

| 平台 | 装法 | 说明 |
|---|---|---|
| Linux x86_64 | `pip install onnxruntime` | 直接可用，性能与 Windows 同级 |
| Linux aarch64 | `pip install onnxruntime` | 有 wheel，但**先确认真的装上了**（有些发行版要 `--index-url` 指到 aarch64 源） |
| 瑞芯微 RK3568/RK3566 | **不要走这条路** | 板子要的是 **RKNN**，不是 ONNX Runtime。见第 7 节 |

装完先验一下：

```bash
python3 -c "import onnxruntime as o; print(o.__version__, o.get_available_providers())"
```

期望看到 `CPUExecutionProvider`。看到 `AzureExecutionProvider` 是正常的
（那是编译进来的云推理后端，本项目不用它）。

### 坑 3：`--ort-threads` 必须显式给

检测模型和车道模型是**两个 ONNX session 并存**。不设 `intra_op_num_threads`
时它们会互相抢线程，实测总耗时从 30 ms 涨到 **183.6 ms**（5.4 FPS）：

| `intra_op_num_threads` | 合计 | 折算 |
|---|---|---|
| 不设（默认） | 183.6 ms | 5.4 FPS |
| 2 | 61.0 ms | 16.4 FPS |
| 4 | 37.6 ms | 26.6 FPS |
| **8** | **30.3 ms** | **33.0 FPS** |

`adas_live.py` 默认就是 `--ort-threads 8`。CPU 核少就往下调
（4 核机器给 4，2 核给 2）。

---

## 6. 在服务器上跑、从自己电脑看

默认只听 `127.0.0.1`。**推荐用 SSH 端口转发**，别开 `--host 0.0.0.0`：

```bash
# 在服务器上
python3 tools/adas_live.py

# 在你自己的电脑上
ssh -L 8790:127.0.0.1:8790 user@server
# 然后本地浏览器开 http://127.0.0.1:8790/
```

理由是这条链路**没有任何鉴权**（谁连上谁能传文件、谁都能看画面），
而且它推的是 MJPEG 原图，一帧 190 KB、13 FPS ≈ **20 Mbps**，
走公网不现实，走内网也最好先想想。

真要开：`python3 tools/adas_live.py --host 0.0.0.0 --port 8790`，
请自己加反向代理 + 认证。

---

## 7. 关于"最后要上板"

这套东西现在的形态是 **PC 侧可视化**，和板上部署是两条路：

| | 现在这套 | 板上那条路 |
|---|---|---|
| 运行时 | ONNX Runtime (CPU) | **RKNN** / NPU |
| 平台 | Windows / Linux x86_64 | RK3566 / RK3568 |
| 模型 | `traffic9_split6_640.onnx` 12.08 MB FP32 | INT8 QDQ 3.33 MB（已有）、或重新量化 |
| 车道头 | `lanenet.onnx` 46.09 MB | **还没转换过，也没量化过** |
| 实测精度 | 部署域 mAP@0.5 0.6875 | **板端未测**，判据是 ≥ 0.6532 |

两件必须说清楚的事：

1. **车道回归头从未在板上跑过，也没做过 INT8 量化。** 46 MB 的 ResNet-18
   对 RK3566 的 NPU 来说是重负载，而且它现在是 FP32。
   真要上板，先做的是量化 + 在板端重测 LOSO 那套指标（当前 PC 侧
   `mean 41.3 px / p50 24.0 px`），不能直接拿 PC 的数字外推。
2. **RK3568 的 4×Cortex-A55 跑 CPU 版 ONNX Runtime 不现实。** 检测模型在
   x86 上单帧 29 ms，A55 大概要 10 倍以上；两个模型加起来会掉到 1 FPS 以下。
   板子上的出路是 NPU（RKNN），不是 CPU。

Linux x86_64 这台机器只是"把网页跑起来给人看"的载体；上板的活是另一摊。

---

## 8. 如果只是想先确认"能不能跑"

不接视频也能验：

```bash
python3 tools/adas_paths.py
```

输出（路径按你的机器变）：

```
ADAS_ROOT     = /opt/ziguang
traffic9 包   = /opt/ziguang/traffic_yolo_deploy/deploy_rk3568
检测模型      = /opt/ziguang/traffic_yolo_deploy/deploy_rk3568/models/traffic9_split6_640.onnx
车道模型      = /opt/ziguang/tools/_lane_runs/v9/lanenet.onnx
  traffic9  exists=True  ...
  det       exists=True  ...
  lane      exists=True  ...
```

三行 `exists=True` 就说明路径解析没问题，剩下的只是依赖。

批量出 mp4（不出网页）也是同一条流水线：

```bash
python3 tools/adas_dash.py \
  --video /path/to/drive.mp4 \
  --onnx   "$(python3 tools/adas_paths.py --print det)" \
  --lane-onnx "$(python3 tools/adas_paths.py --print lane)" \
  --out /tmp/adas_out --start 363 --duration 32 --write-video
```

> **别写成 `python3 -c 'import adas_paths; ...'`** —— `-c` 会把 `sys.path[0]`
> 设成当前目录，而 `adas_paths.py` 在 `tools/` 里，Linux 上会直接
> `ModuleNotFoundError: No module named 'adas_paths'`。用
> `python3 tools/adas_paths.py --print det` 这种脚本路径调用就没这个问题。

`adas_dash.py`（批量）与 `adas_live.py`（网页）走的是**同一个
`AdasPipeline` 类**，所以两边画出来的东西一定一致，不会悄悄分叉。

---

## 9. WSL2 实测记录（2026-10）

环境：Ubuntu 24.04.5 LTS / kernel 6.18.40.1-microsoft-standard-WSL2 / x86_64，
宿主是同一台 Windows 机器（i9-13980HX，`nproc` 在 WSL 里报 32，内存 7.6 GB）。

### 9.1 这台 WSL 缺什么

| 项 | 情况 |
|---|---|
| Python | 3.12.3（系统自带，够用，代码要求 ≥3.10） |
| `pip` | **没有** |
| `ensurepip` | **没有**（所以 `python3 -m venv` 不带 `--without-pip` 会失败） |
| `sudo` | 用户虽然在 sudo 组，但**需要密码** ⇒ 装不了 apt 包 |
| pypi.org | 可达，但慢（HTTP 200 用了 7.9 s） |

### 9.2 不需要 sudo 的装法（`tools/_wsl_bootstrap.sh`）

```bash
python3 -m venv --without-pip ~/.venvs/adas
curl -fsSL -o /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py      # 2.23 MB
~/.venvs/adas/bin/python /tmp/get-pip.py -i https://pypi.tuna.tsinghua.edu.cn/simple
~/.venvs/adas/bin/pip install -i https://pypi.tuna.tsinghua.edu.cn/simple \
    "opencv-python>=5.0.0" "numpy>=2.0" "onnxruntime>=1.20" scipy
```

**venv 放 `~/.venvs/adas` 而不是仓库里，是刻意的**：`/mnt/d` 是 9p 文件系统，
在上面建 venv 装包极慢；代码仍从 `/mnt/d/ziguang` 读，解释器放 ext4。
`tools/run_adas_live.sh` 的 `pick_python()` 会把这一条列进去，不用额外设环境变量。

实际装到：`opencv-python 5.0.0.93`（`opencv_python-5.0.0.93-cp37-abi3-manylinux_2_28_x86_64.whl`，73.8 MB）、
`numpy 2.5.3`、`onnxruntime 1.30.0`、`scipy 1.18.1`。

### 9.3 坑 1 在 Linux 上不成立

```
opencv   5.0.0
unicode  Built-in Unicode font:       YES
```

官方 manylinux wheel **自带 Unicode 字体**，所以中文标签不需要额外装字体、
不需要换 `PIL`。§5 的坑 1 只对"自行编译的 OpenCV"成立。

### 9.4 端到端结果

```powershell
# Windows 侧启动
wsl -e bash -lc "cd /mnt/d/ziguang && bash tools/run_adas_live.sh --port 8790"
```

| 检查项 | 结果 |
|---|---|
| 启动自检 | `python = /home/yq/.venvs/adas/bin/python`、`Unicode 字体 = YES（中文能画）` |
| 上传目录 | `/tmp/adas_live`（**没有**误建 `C:\Users\...` 目录） |
| Windows 浏览器访问 | `GET http://127.0.0.1:8790/` → **200 / 7815 bytes**（WSL2 localhost 转发生效） |
| 上传 | 9.3 MB / 0.69 s → `/tmp/adas_live/1791368473_wsl_test_clip.mp4` |
| MJPEG 推流 | 抓到 120 帧，`X-Frame: 19 / 69 / 119` 帧序连续无丢 |
| 中文渲染 | 全部正确（「本车道中心线」「自车俯视」「航点剖面」「本车道趋势」…） |
| 处理速度 | **`proc_fps 15.28`**，同帧瞬时 **16.4 FPS** |

分项耗时（p50/p95，ms）：

| | WSL2 | Windows |
|---|---|---|
| detect | 29.6 / 32.5 | 37.6 / 41.1 |
| track | 1.1 / 1.7 | 1.7 / 2.9 |
| lane | 17.1 / 19.5 | 21.7 / 23.7 |

**同一段视频、同一帧，Linux 侧快约 20~25%**（32 个逻辑核全给到 + 少了 Windows
的调度与图形栈开销）。所以"搬到 Linux 会不会变慢"这个担心可以去掉。

### 9.5 无桌面环境下 `--open` 的处理

WSL 没有桌面时 `webbrowser.open()` 会挑到 `gio`，然后由 **`gio` 子进程**往
stderr 打 `gio: http://127.0.0.1:8790/: Operation not supported` ——
那是子进程的输出，Python 的 `try/except` 抓不到。现在 `adas_live.py` 用自己的
`try_open_browser()`：Windows 走 `os.startfile`，Linux 依次试
`wslview` / `xdg-open` / `gio open`，并且把子进程的 stdout/stderr 都丢进
`DEVNULL`；一个都没有就打印"请手动打开 <地址>"。所以这条噪声已经不会再出现。

WSL 里装 `wslview`（`sudo apt install wslu`）可以让 `--open` 真的在 Windows
侧弹出浏览器；不装也不影响使用，手动点链接即可。

