# 阶段 E/F 验收证据（Dashboard + 协议 + 回放链路）

> 本文只记录**能复现的东西**：命令、输出、数字、截图。凡是没做到的，第 5 节单独列，不混进结论。
> 生成时间：2026-10-19。全部在本机 `D:\ziguang` 上跑出。

## 1. 一条命令复现整套

```powershell
$py = "D:\ziguang\.venv_gpu\Scripts\python.exe"
& $py -X utf8 dashboard\tests\test_protocol.py          # 协议 codec/向量/确定性
& $py -X utf8 dashboard\tests\test_dashboard.py         # 消费者判定/渲染
& $py -X utf8 dashboard\tests\test_lane_track.py        # lane alpha-beta 状态机（RKD-24）
& $py -X utf8 dashboard\tools\export_log.py --frames 600 --out dashboard\data\replay\adas_replay.ndjson
& $py -X utf8 dashboard\tools\verify_log.py --log dashboard\data\replay\adas_replay.ndjson
& $py -X utf8 dashboard\tools\eval_lane_track.py --json dashboard\data\replay\lane_track_eval.json
& $py -X utf8 dashboard\app.py --headless --shots 3 --view 3
```

WSL（Ubuntu 24.04，只有标准库也能跑协议层）：

```bash
cd /mnt/d/ziguang && python3 -X utf8 dashboard/tests/test_protocol.py    # 147/147
```

## 2. 实测数字

| 指标 | 实测值 | 来源 |
|---|---|---|
| 协议断言 | **147 / 147** | `tests\test_protocol.py` |
| 消费者断言 | **39 / 39**（11 组） | `tests\test_dashboard.py` |
| Lane 跟踪断言 | **20 / 20**（7 组） | `tests\test_lane_track.py` |
| 测试向量 | 33 条（6 类：normal/invalid/bad_crc/version/out_of_order/duplicate） | `testdata\vectors\` |
| 回放帧数 / 消息数 | 600 帧 / 4200 条（7 条/帧） | `export_log.py` 输出 |
| 回放时长 | 20.02 s @ 29.97003 fps | 日志 header |
| 导出日志体积 | 68,681,026 B（缩略图 33,576,053 B） | `adas_replay_summary.json` |
| 导出耗时 / 推理帧率 | 39.41 s / **15.22 fps**（ONNX CPU） | 同上 |
| 定点钳位次数 | **0** | 同上 |
| 车道偏移范围 | −36.43 … +18.53 px（600 帧） | 同上 |
| 接收校验 | 4200 成功 / **0 丢弃**（crc 0、version 0）/ 缺口 0 / 重复 0 / 乱序 0 | `verify_log.py` |
| 渲染吞吐 | view2 **92.1 fps**（10.86 ms/帧）；view3+浮层 51.1 fps | 见 §3.4 计时脚本 |
| 解码投递吞吐 | 36,278 条/s（4200 条 0.12 s） | 同上 |
| 缩略图单包 | 800x450 q75：均 56.0 KB，最大 58.8 KB，**上限 65,500 B 内，0 次降质** | D6 实测 |

## 3. RKD 逐条

### RKD-27 Dashboard 骨架与来源标记

- 实现：`dashboard\app.py:54 run()`（回放投递 + 按键）、`dashboard\ui\screen.py:483 Screen.render()`（画布入口）、`dashboard\ui\screen.py:118 _header()`（横幅与 `system_mode`）。
- 来源标记：横幅常驻 `REPLAY · 回放数据，非在线测量`，`source = REPLAY`；`source_id` 字段值是 `PC`，`clock_domain_id=3`，写进每条报文的公共头（`export_log.py:65 _header()`），日志首行 header 另注明"不是板端抓包"。
- 禁止写死测量值：界面每个数字都来自 `Snapshot.latest[typ]["payload"]`；`tests\test_dashboard.py` 的 `t_render_empty` 断言"一条消息都没有"时仍能渲染且全为 `unavailable`。
- 证据：`data\shots\view2_f00000.png`（正常）、`data\shots\selftest_health.png`（只有 HEALTH 时的空状态）。

### RKD-28 三种演示视图

- 实现：`screen.py:483 render(view=...)`，`view>=2` 才画目标（`screen.py:162 _camera()` 内分支），`view>=3` 才出深度行（`screen.py:332 _depth_line()`）。
- 视图切换不改健康状态：`tests\test_dashboard.py` 的 `t_render` 记录切视图前后的 `frames_ok/dropped/crc_err/system_mode`，断言**完全不变**（本次新增的第 39 条断言）。
- 证据：`view1_f00000.png` / `view2_f00000.png` / `view3_f00000.png` 三张同帧不同视图。

### RKD-29 字段与统计

- 车道卡片（`screen.py:266 _card_lane`）：`lane_valid`/`center_valid`/`center_offset_px`/`curvature_px_inv`/`confidence_score`；`lane_width_px` 因左右线不存在显示 `— unavailable(NO_LEFT_RIGHT)`。
- 目标卡片（`screen.py:291 _card_obj`）：`object_count`、`track_count`（确认/丢）、`tracker_epoch`、前 4 个目标（类名/置信度/框）。
- 链路卡片（`screen.py:343 _card_link`）：收包、CRC 错、序号缺口/丢帧、重复/乱序、HEALTH 明细。
- 版本块（`screen.py:363 _card_ver`）：协议版本、calibration_id、clock_domain_id、到达延迟、位流/模型 SHA256（无数据时 `unavailable(NOT_PROVIDED)`）。
- 统计：P50/P95 由 `state\stats.py:12 Window` 算，卡片与曲线图右侧同步显示；同帧率 `screen.py:378 _strip()`；温度曲线 `screen.py:432 _temp_line()`（右轴 0–100 ℃，虚线）。
- 跨板总延迟：**默认不显示**（本阶段无此测量，界面无该字段）。
- 缺口：MOTION / FEATURE 两组字段未上屏——生产者不发这两类消息，硬画就是假数据。

### RKD-30 降级与恢复演示（§10.3 十项注入）

- **未完成**。已完成的是可自动化的部分：过期满 400 ms → `unavailable(STALE)`（`t_stale`）、坏 CRC → 丢弃且不污染状态（`t_crc`）、序号缺口 2 帧（`t_seq`）、重复帧（`t_seq`）、`system_mode` 五态迁移与恢复期 12 帧（`t_mode`）。
- 未完成的是 §10.3 的**十项故障注入矩阵**（拔线/断流/时钟漂移/板端重启等）与 `SAT-FAILOVER` 证据表：这些需要板端或至少可注入的传输层，本阶段只有回放，注入等于伪造现场，故不做。

### RKD-31 演示模式门禁

- 规则写法：`dashboard\state\model.py:144 status_word()` 是唯一判定入口——没收到 → `("unavailable","NOT_PROVIDED")`；过期 → `("unavailable","STALE")`；`status != OK` → 原因码直出。`screen.py:77 _status()` 把它折成 bool，界面只认这个。
- 断言：`t_stale`（过期后必须 unavailable，且**值仍留在快照里**——由状态而不是删值来兜底）、`t_invalid_status`（`LANE_LOST` 原样上屏）、`t_crc`（坏帧不进 `latest`、不进统计）。
- 不显示 0 / 不显示上一帧值：`t_render_empty` + `selftest_health.png`（整屏 `unavailable`，没有任何 `0` 被当成测量值）。
- 不把回放当在线：横幅 + 日志 header 双重标注。

## 4. 协议侧的两个关键偏离（数据见 `docs\interface_contract.md`）

- **D2**：LANE 系数若按母方案 Q8.8，296 帧标注里 **87.8%（260/296）** 的二次项 `|a|` 小于半个 LSB（1.953e-3）会被量化成 0；`c` 范围 −19016…22617，Q8.8 int16 只能表示 ±128，**溢出 176 倍**。最大量化误差折算到 v=720 处为 **1002.96 px**，改 Q1.30 后同一位置 **2.41e-4 px**。故 `a=Q1.30`、`b/c=Q16.16`。
- **D6**：ROADTHUMB 若按母方案 640x384 RGB565 裸像素 = 491,520 B，是 `payload_length`（uint16）上限的 7.5 倍，单包物理不成立；改 JPEG 后 800x450 q75 实测 56.0 KB，单包可送。

## 5. 没做到 / 没验证的（照实列）

1. RKD-30 的十项注入与 `SAT-FAILOVER` 证据表——没有板端，注入即造假，留到接入真链路后做。
2. RKD-32 30 分钟长稳——需要板端最高负载，本阶段只测了 PC 侧回放吞吐（92 fps 渲染 / 15.2 fps 推理）。
3. HEALTH / DEPTH / MOTION / FEATURE 四类消息**只有协议与渲染路径，没有真实数据**；温度曲线用合成 HEALTH 帧做自检（`selftest_health.png`），图里明确是 0–100 ℃ 轴上的 47.6 ℃，不是实采。
4. LIVE 通道未接：`Snapshot.feed(bytes)` 与传输无关，接 UDP 只是把字节喂进来，但没有板端抓包可对照，所以没写。
5. 车道叠画只在 `[y_fit_min, y_fit_max]`（本例 612…709 px）内画，画面里是一小段——这是模型的真实拟合域，向外延伸就是外推画假线，故意不画。
6. RKD-24 已闭环到"界面显示"，但**滤波器只有 Python 参考实现**：上板要按同一参数（α=0.35/β=0.05/死区 2 px/max_hold 5）写 C++ 版本，并用同一批向量对拍。这是重写，不是移植。

## 6. RKD-24 Lane 时间跟踪（本轮新增，已闭环到界面）

实现：`dashboard\state\lane_track.py`（`LaneTracker.push()` 是唯一入口）、评估 `dashboard\tools\eval_lane_track.py`、断言 `dashboard\tests\test_lane_track.py`。

**闭环方式（协议 D7）**：滤波属于 RK 侧，界面不许自己算（§9.1），而原有消息集里没有 RK 发的车道消息。因此新增 `LANE_TRACK`(0x14)：生产者扮演 RK 侧跑滤波、逐帧发结果，Dashboard 只显示。复导后日志 **4800 条 = 8 条/帧**（新增的正是 LANE_TRACK），接收 4800/4800、零丢弃；界面"车道 LANE"卡片显示 `seq 599 · RK 滤波 TRACKING`、`center_offset_px −2.44` 与 `filtered_offset_px −4.14` 并排，相机上同时画原始（黄）与滤波后（绿）中心线，差值标 `滤波 −1.70 px`。

参数按 §7.2 冻结：α=0.35、β=0.05、死区 2 px、`max_hold=5`、`dt` 用实测到达间隔。EMA(α=0.35) 作为基线并行跑（§7.1 要求必须有）。

**真实回放 600 帧（逐帧 offset）**

| 系列 | mean\|Δ\| px | p95\|Δ\| px | max\|Δ\| px | 相对 raw |
|---|---|---|---|---|
| raw | 0.616 | 1.724 | 2.564 | — |
| alpha-beta | 0.527 | 1.477 | 2.229 | **−14.5%** |
| EMA 基线 | 0.458 | 1.243 | 1.944 | **−25.6%** |

**这段数据上 EMA 更平滑，alpha-beta 没赢**。原因可查：本段 `max|Δ raw| = 2.56 px`，根本没有阶跃，alpha-beta 的恒速预测没有发挥空间；它换来的是阶跃跟随（见下）。

**合成阶跃 50 px（第 10 帧起）**

| 指标 | alpha-beta | EMA |
|---|---|---|
| 到 90%（45 px） | **4 帧** | 6 帧 |
| 峰值过冲 | 56.67 px（+13.3%，第 8 帧） | 无（单调） |
| 收敛进 ±1 px | **31 帧（约 1.0 s）** | 9 帧 |

补充归因：把 §7.2 的低增益死区关掉，同样阶跃的收敛从 31 帧降到 20 帧；即**死区贡献了约 11 帧的稳定尾巴**。参数是冻结值，本文只报现象，不擅自改。

**状态机**：HOLD 只在 `valid=0` 单帧丢线时出现、且 `valid=False`（预测不算测量）；连续 5 帧后转 `LOST` 且 `reason=AGE_TIMEOUT`；跳号（含乱序）、`dt>2×标称`、`calibration_id/mode_id` 变化都立即清零并重新 seed——四条都有断言。

## 7. WSL 适配性检验（Ubuntu 24.04 / Python 3.12）——已全项跑通

目的：确认"不用板子也能验的部分"在 Linux 上不塌，并且数字与 Windows **逐项一致**。

**先说 pip 的事**（易误会）：WSL 里 `python3 -m pip` 报 `No module named pip` **不是权限问题**，
是两个发行版行为叠加：① Ubuntu 24.04 默认不装 `python3-pip`（独立包）；② 系统 Python 带
PEP 668 的 `EXTERNALLY-MANAGED` 标记，即使装上 pip，直接 `pip install` 到系统环境也会被拒绝。
`apt install python3-pip python3-venv` 那一步才需要 sudo 密码。本轮为避免动系统 Python，走了用户态：

```bash
curl -sS -o /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py
python3 /tmp/get-pip.py --user --break-system-packages
python3 -m pip install --user --break-system-packages pillow numpy opencv-python-headless
# 中文字体：不用 root 也能拿（下 deb 再解包）
cd /tmp && apt-get download fonts-wqy-microhei && dpkg-deb -x fonts-wqy-microhei*.deb ~/fonts-local
export ADAS_FONT=~/fonts-local/usr/share/fonts/truetype/wqy/wqy-microhei.ttc
```

**结果**

| 检查项 | Windows (Py3.13) | WSL Ubuntu 24.04 (Py3.12) |
|---|---|---|
| `test_protocol.py` | 147/147 | **147/147** |
| `test_dashboard.py` | 39/39 | **39/39** |
| 喂完整日志 | 4800 条 / 0 丢弃 / 缺口 0 / 重复 0 | **4800 / 0 / 0 / 0** |
| DETECT P50 / LANE / TRACK | 27.98 / 17.20 / 2.83 ms | **27.98 / 17.20 / 2.83 ms** |
| LANE_TRACK@599 filtered / raw | −4.1367 / −2.4399 px | **−4.1367 / −2.4399 px** |
| 同帧率 | 100% | **100%** |
| 渲染一帧（真实日志） | `view2_f00599.png` | `wsl_view2.png`（字形来自 wqy-microhei） |

**顺手修掉的跨平台缺陷**

1. 生成器写文件没锁换行：Windows 把 `\n` 翻成 `\r\n`，同一批向量两平台 sha256 不同。三处写文件加
   `newline="\n"` 后，两平台逐文件哈希一致（`bad_crc.ndjson` = `53544db6c244`）。
2. `ui/text.py` 原来硬编码 `C:/Windows/Fonts/msyh.ttc`，Linux 上直接崩。改成按候选列表找字体
   （支持 `ADAS_FONT` / `ADAS_FONT_BOLD` 覆盖），**找不到就明确报错**，不静默画方框。

**仍然没验的**

- 板子上的 Python 是 3.10（Ubuntu 22.04），本机 3.13、WSL 3.12。已用 `ast.parse(feature_version=(3,10))`
  扫过全部 21 个文件（语法兼容），但**没有在真 3.10 解释器上跑过**。
- WSL 是 x86_64，ARM64 上的数值/性能未验（numpy 在 ARM 上的浮点结果应当一致，但没有证据）。

## 8. 截图索引

| 文件 | 内容 |
|---|---|
| `dashboard\data\shots\view1_f00000.png` | Mode 1 Basic（无目标框） |
| `dashboard\data\shots\view2_f00000.png` | Mode 2 Intelligent |
| `dashboard\data\shots\view3_f00000.png` | Mode 3 Fused（DEPTH 缺失行） |
| `dashboard\data\shots\view2_f00599.png` | 第 599 帧（回放末帧） |
| `dashboard\data\shots\detail\view2_f00000.png` | D 键原始字段浮层 |
| `dashboard\data\shots\selftest_health.png` | 合成 HEALTH 帧：空状态 + 温度曲线（自检，非实采） |
