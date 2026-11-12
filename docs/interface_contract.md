# 夜瞳统一协议 V1 —— 接口契约

> 状态：**已冻结 V1**（2026-10-19）　适用：50K ↔ RK3568 ↔ PC Dashboard 全链路
> 字段级参考：`docs/protocol_schema/PROTOCOL_FIELDS.md`（脚本生成，勿手改）
> 机器可读定义：`docs/protocol_schema/protocol.json`、`messages.json`、`enums.json`
> 唯一实现：`dashboard/protocol/schema.py`（通用编解码）、`dashboard/protocol/receiver.py`（链路计数）

这份文档只写**语义**，不重复字段表。字段表、偏移、定点比例、枚举值一律以 JSON 为准；
本文若与 JSON 冲突，以 JSON + 生成文档为准，并视为本文的 bug。

---

## 1. 传输形态

| 场景 | 载体 | 分帧方式 |
|---|---|---|
| LIVE（板间） | UDP 单报文 = 1 帧 | 报文边界即帧边界；禁止在一帧内塞两帧 |
| LIVE（大图） | UDP 分片 | 公共头 `fragment_index/fragment_count`，`payload_length ≤ 65535` |
| REPLAY（本机答辩） | ndjson，每行 `{"hex": "...", ...}` | 行边界即帧边界 |

硬约束：

- 公共头 **40 字节**，字段全部自然对齐，`crc32` 固定位于偏移 36。FPGA 侧按 4 字节字搬移即可。
- 字节序 **little-endian**，无隐式 padding。
- `payload_length` 是 **uint16**，上限 65535 字节。`ROADSTREAM`（320×240 MONO8 = 76800 B）与全分辨率 `UDP_VIDEO` **必须分片**，分片重组属 RKD-12，本阶段只冻结字段。
- 接收端 `decode()` 对"多余字节"直接判 `LENGTH_MISMATCH`。流式（TCP/文件）读取必须先分帧，不得把两帧拼一起喂进去。

## 2. 公共头语义

### 2.1 序号与时钟域

`sequence` 按 **(source_id, message_type, clock_domain_id)** 三元组各自独立递增。
不是全局帧号 —— 用全局序号会让三种消息互相"制造丢帧"。接收端判定：

| 条件 | 判定 | 处理 |
|---|---|---|
| `seq == last + 1` | OK | 接收，更新 last |
| `seq == last` | DUPLICATE | 不更新 last，计入 `duplicate` |
| `seq > last + 1` | SEQ_GAP | 接收，计入 `seq_gap += 1`、`missing += seq-last-1` |
| `seq < last` | OUT_OF_ORDER | 接收（数据仍有效），计入 `out_of_order` |

`timestamp_ns` 是**发送端单调时钟**，只在同一 `clock_domain_id` 内可比。
跨域延迟只能用 PC 侧 `arrival_ns - 上一跳 arrival_ns` 或板内已算好的 `TIMING.duration_us`，
**禁止**把 50K 的 `timestamp_ns` 与 RK3568 的 `timestamp_ns` 相减当延迟（两边上电时刻不同）。

### 2.2 CRC 与错误分类

`crc32 = zlib.crc32(header[0:36] ++ payload)`，计算时 `crc32` 字段本身不参与（写 0 后算或不参与等价）。

接收端错误码（`dashboard/protocol/schema.py::ProtocolError.code`）：

| 错误码 | 触发 | 计入 | Dashboard 表现 |
|---|---|---|---|
| `BAD_MAGIC` | 头 2 字节 ≠ 0x5954 | `dropped` | 链路异常，不显示数据 |
| `VERSION_UNSUPPORTED` | `protocol_version > 1` | `version_err` | 显示 `unavailable (VERSION_UNSUPPORTED)` |
| `CRC_MISMATCH` | CRC 不符 | `crc_err` | 丢弃整帧，不进入任何统计 |
| `LENGTH_MISMATCH` | 帧长 ≠ 头+payload，或字段越界 | `dropped` | 同上 |
| `TRUNCATED` | 不足 40 字节 | `dropped` | 同上 |
| `UNKNOWN_TYPE` | 未定义 `message_type` | `dropped` | 同上 |
| `FIELD_RANGE` | 编码侧数值越界 / 枚举未定义 | — | 发送侧 bug，直接抛异常 |

**丢弃的帧不得进入 P50/P95、FPS、字段显示**。丢帧只体现在 `crc_err / seq_gap / drop` 计数上，
这条是 SAT-DASH-FIELD「unavailable 100%、写死值 0 处」的判定基础。

### 2.3 版本兼容

- 接收端接受 `protocol_version ≤ 本地版本`；高于本地直接 `VERSION_UNSUPPORTED`，**不允许按旧布局猜字段**。
- 同一版本内只允许"追加枚举值"和"使用保留位"，不允许改字段顺序/位宽/定点。
- 破坏性修改 → `protocol_version += 1`，且 PC 端必须同时支持 n-1 才允许发布（RKD-35 回退方案）。

### 2.4 偏离记录（相对母方案 §3.3 / 子方案 §9.5）

偏离必须记录，否则下次评审会被当成实现错误。

**D1 — `invalid_reason` 从消息体提到公共头。**
母方案把 `invalid_reason` 分别定义在 LANE / DEPTH / TRACK_V1 内。本协议统一放公共头偏移 28。
理由：Dashboard 需要一条**与消息类型无关**的渲染路径输出 `unavailable (REASON)`；若留在消息体内，
每种消息都要各写一遍取因逻辑，且 OBJECT / MOTION 这类没定义该字段的消息无法表达"本帧无效"。
影响：消息体内不再重复该字段，节省 1~2 B/帧。

**D2 — LANE 多项式系数改为按系数分别定点（a=Q1.30，b/c=Q16.16），而非方案原文 Q8.8。**
实测依据（`tools\_lane_labels\labels.jsonl`，296 帧人工标注，`abc` 字段）：

| 系数 | 观测范围 | Q8.8（int16，LSB=3.906e-3）后果 |
|---|---|---|
| `a` | −0.0436 … +0.0475，中位 \|a\|=3.03e-4 | **87.8% 的帧 \|a\| < 半个 LSB → 被量化为 0**，二次项整项丢失 |
| `b` | −64.5 … +58.6 | 可表示（int16 Q8.8 范围 ±128），但余量仅 2 倍 |
| `c` | −19016 … +22618 | **溢出**：Q8.8 只能表示 ±128，`c` 超出 176 倍 |

若按 Q8.8 存储，`a` 的最大量化误差 1.93e-3 折算到 `v=720` 处会造成 **约 1003 px** 的列坐标误差；
改用 Q1.30 后同样位置的误差是 **2.4e-4 px**。方案原文的 Q8.8 应是为归一化坐标写的，与本项目
"像素坐标 + 以图底为参考"的参数化不匹配。结论：Q8.8 会系统性丢掉曲率信息，属于"用零值冒充测量值"，
违反方案 §9.6 自身的禁令，故不允许按原文字段实现。

**D3 — `payload_length` 保持 uint16，超长消息分片，而不是改成 uint32。**
理由：头长固定 40 B 且 4 字节对齐，是 FPGA 侧一次突发搬移的前提；改 uint32 会改动已冻结的头布局。
代价：`ROADSTREAM` 满帧必须 2 片，重组逻辑进 RKD-12。

**D4 — Dashboard 渲染后端沿用 OpenCV 合成画布，而非子方案 §9.5 冻结的 PySide6。**
理由：本机 `.venv_gpu` 未安装 PySide6 / PyQt5，答辩现场要求离线可跑；现有
`tools/adas_dash.py` 的 OpenCV 画布已实测约 15 FPS，且零新增依赖。此偏离只影响"用什么画"，
不影响 §9.2 三视图、§9.3 字段、§9.6 交互的任何验收项。若后续必须交付 Qt 版本，
`dashboard/ui` 之下的渲染层是按"数据快照 → 视图"分层的，替换渲染器不改数据层。

**D5 — `LANE` 增加 `center_valid/center_a/center_b/center_c` 一组并新增 `y_fit_min`。**
理由：本案车道模型只回归**自车道中心线**，没有左右线输出；母方案 §3.3 只定义左右线，若不增字段，
只能把中心线伪装成左右线（语义造假：`lane_width_px` 会变成"中心线到中心线"，恒为 0）。
`y_fit_min` 是拟合采样带的近端：`abc` 只在 `v ∈ [y_fit_min, y_ref]` 内是拟合值，超出即外推。
实测踩过：Dashboard 用 `v ∈ [0.42h, y_ref]` 画曲线，曲线冲出画面——不是渲染 bug，是**协议缺了有效域**。

**D6 — `ROADTHUMB.pixels` 改为编码后的 JPEG（新增 `pixel_format=JPEG`），而不是裸 RGB565。**
理由：640x384 RGB565 = 491,520 B，是 `payload_length`(uint16) 上限 65,535 的 7.5 倍，**单包在物理上
不可能成立**；母方案这一条自相矛盾。JPEG 实测：800x450 q75 平均 56.0 KB、最大 58.8 KB，单包可送；
若某帧超 65,500 B，导出端自动降质重编（记录 `thumb_fallback` 次数），绝不分片。
代价：接收端要解码（PC 侧 `cv2.imdecode`，约 3 ms/帧），且 `scale_x/scale_y` 语义变为
"源分辨率 / 解码后分辨率"，用于把 bbox 反算回 1280x720。

**D7 — 新增 `LANE_TRACK`（0x14）承载 RK 侧的 lane 时间滤波结果。**
理由：§9.3 把 `filtered_offset_px`、`lane_state` 列在"`LANE` + RK 滤波"一行，但冻结的消息集里
没有任何一条由 RK 发出的车道消息——`LANE` 是 50K 的原始量。若让 RK 就地改写 `LANE`，会与 50K
的 `LANE` 抢同一个 `(source,type)` 序号通道，`latest` 也分不清谁写的；若让 Dashboard 自己算，
又直接违反 §9.1「界面不得生成任何测量值」。故独立一条消息，`source_id=RK3568`，与 `LANE` 同帧成对出现。
字段：`src_frame_id`、`raw_offset_px`、`filtered_offset_px`、`ema_offset_px`、`curvature_filtered`、
`lane_state`(TRACKING/HOLD/LOST)、`hold_frames`、`dt_us`（实测间隔，不假设 33.3 ms）、`alpha`、`beta`、
`seq_gap_cnt`、`reset_cnt`。
语义：`HOLD` 时 `filtered_offset_px` 是**预测值**，界面必须标"（预测）"；`LOST` 时 header 置
`INVALID` + 原因码（`AGE_TIMEOUT`/`SEQ_GAP`/`DT_OUT_OF_RANGE`/`CALIB_MISMATCH`），payload 数值全 0。

## 3. 无效值语义（`unavailable` 的唯一来源）

规则只有一条，全项目共用：

> **`status != OK` 时，该帧 payload 内所有数值字段不具语义，接收端必须整体丢弃 payload，只保留
> `status` + `invalid_reason` + `frame_id`。**

因此 Dashboard 渲染 `— unavailable (REASON)` 时，`REASON` 只能来自公共头，不能来自 payload
里的任何一个数字。这条规则同时禁止"上一帧值继续显示"：无有效帧时保持 unavailable，
直到下一帧 `status == OK`。

`status` 取值语义：

| status | 含义 | 数值字段 |
|---|---|---|
| `OK` | 本帧测量有效 | 可显示 |
| `INVALID` | 本帧有数据通路但结果无效（如车道丢失） | 必须忽略 |
| `DEGRADED` | 有降级但仍有可用部分（如 `ego_valid=0` 时光流仍可用） | 仅 `invalid_reason` 指明的那部分不可用 |
| `UNSUPPORTED` | 该板/该配置不支持此测量（如未接深度相机） | 必须忽略 |
| `STALE` | 数据是旧帧重发 | 必须忽略，且不得刷新时间戳 |

`DEGRADED` 是唯一允许"部分可用"的状态，因此它的依赖关系必须由 `invalid_reason` 精确表达
（例：`DEGRADED` + `DEGRADED_NO_FLOW` 表示自运动补偿不可用、`valid_ratio`/运动比仍有效）。

## 4. 各消息的有效前提

| 消息 | 数值可用前提 | 不满足时的 reason |
|---|---|---|
| LANE | `lane_valid=1` 且 `status=OK`；单边缺失看 `left_valid/right_valid` | `LANE_LOST` |
| MOTION | `status=OK`；`ego_*` 另需 `ego_valid=1` | `NO_REF` / `DEGRADED_NO_FLOW` |
| DEPTH | `depth_status=OK` 且 `valid_ratio>0`；距离只在 200~1000 cm 有效 | `DEPTH_GATE` / `NO_DEPTH` / `LOW_CONFIDENCE` |
| OBJECT | 列表本身即测量；距离需 `distance_status=VALID` | `NO_DEPTH` / `OUT_OF_VALID_RANGE` |
| TRACK_V1 | `track_valid=1` 且 `tracker_epoch` 与上一帧一致才允许比较 ID | `TRACK_DISABLED` / `TRACK_STALE` |
| HEALTH | 总是有效；`module_state` 是唯一健康真值 | `HEARTBEAT_TIMEOUT` / `LINK_DOWN` |
| TIMING | `window_frames>0` 才能显示 P50/P95 | `NOT_PROVIDED` |

深度与距离的口径固定：**无深度只给像素，不给米制**（方案 §6.4）。`distance_status != VALID` 时
`distance_min_cm / distance_max_cm` 必须写 0，且 Dashboard 显示 `— unavailable (NO_DEPTH)`
而不是 `0 m`。

## 5. 与 Dashboard / 验收的接口

| 验收项 | 依赖本契约的部分 |
|---|---|
| SAT-DASH-FIELD | 字段覆盖 100%（每个显示字段都能追溯到某条消息的某个字段）；source 横幅常驻；unavailable 100%；写死值 0 处 |
| SAT-FRAME-SRC | 用 `frame_id` + `sequence` 判定完整率（≥99.5% PASS / 90~99.5% DEGRADED / <90% FAIL） |
| SAT-LANE-TRACK | `tracker_epoch` 变化即判定跟踪器复位，ID 不允许跨 epoch 比较 |
| SAT-FAILOVER | 注入方式即"伪造符合本契约的帧 + 故意篡改 CRC/序号/版本"，见 `dashboard/testdata/vectors/` |
| SAT-TRACK-RESET | 六种强制复位必须都能在帧序列上被观测到（`TRACK_V1.tracker_epoch` 递增） |

## 6. 变更流程（改字段必须走这条）

1. 改 `docs/protocol_schema/*.json`；
2. `python dashboard/tools/gen_protocol_doc.py` 重新生成 `PROTOCOL_FIELDS.md`；
3. `python dashboard/testdata/gen_vectors.py` 重新生成测试向量；
4. `python dashboard/tests/test_protocol.py` 必须仍全绿（当前 147 条断言）；
5. 在本文 §2.4 追加偏离/变更记录，写清理由与影响面。

## 附录 A：复现命令

```powershell
cd D:\ziguang
# 协议自检（打印头布局与各消息定长）
& D:\ziguang\.venv_gpu\Scripts\python.exe -X utf8 dashboard\protocol\schema.py
# 字段文档重生成
& D:\ziguang\.venv_gpu\Scripts\python.exe -X utf8 dashboard\tools\gen_protocol_doc.py
# 向量重生成 + 全量测试
& D:\ziguang\.venv_gpu\Scripts\python.exe -X utf8 dashboard\testdata\gen_vectors.py
& D:\ziguang\.venv_gpu\Scripts\python.exe -X utf8 dashboard\tests\test_protocol.py
```

## 附录 B：偏离 D2 的复现数据

```powershell
& D:\ziguang\.venv_gpu\Scripts\python.exe -X utf8 -c @"
import json
A=[json.loads(l)['abc'][0] for l in open(r'tools\_lane_labels\labels.jsonl',encoding='utf-8')]
q=1/256
print('|a|<half LSB 比例', sum(abs(a)<q/2 for a in A)/len(A))
print('max |a|', max(abs(a) for a in A))
"@
# 输出：|a|<half LSB 比例 0.8783783783783784；max |a| 0.0475322
```
