# ByteTrack 落地实现方案（夜瞳异构 · RK3568 / RK3566 子板）

> 状态：**设计稿（未上板）**。本文中所有性能数字分为三类，逐条标注：
> `[已验证]` = 本仓库已有实测证据；`[设计]` = 本文决定的做法；`[待测]` = 必须上板或跑离线实验才能填的数。
> 上游约束文档：`夜瞳异构_V3.2-RK3568子板落地方案_ByteTrack_ADAS增强版.md`（V1.1，下称「方案文档」）§6.6 / §7A / RKD-36~39。
> 参考实现：ByteTrack 原始仓库 `yolox/tracker/{byte_tracker,kalman_filter,matching,basetrack}.py`（MIT），移植时须记录 commit。

---

## 0. 一页结论

**做什么：** 在已跑通的 YOLO→RKNN 检测链路后**串一个纯 CPU、无状态外溢的跟踪器**，把每帧检测框变成带稳定 ID 的轨迹，并按 `(class_id, local_id)` 编码唯一 ID 输出 `TRACK_V1`。

**三个决定：**

1. **逐类独立 tracker 实例（9 个），不共享 ID 空间。** 方案文档 §7A.2 明确「禁止一次轨迹跨 `car/person` 跳类」；逐类实例是唯一能**结构性**保证这一点的做法（掩码式类门控做不到——跨类误检会在两套池子里各生成一条轨迹）。
2. **运动模型用「工作分辨率 + 真实 Δt」，不照抄「每帧 dt=1」。** 本项目板端 NPU 帧率远低于 30 fps，且抽帧/丢包会让帧间间隔抖动。照抄会让速度项单位错乱，`track_buffer` 的物理含义也完全变掉（详见 §5）。
3. **先做 Python 版，落地顺序是「离线视频 e2e → 板端 UDP e2e → C++ 移植」。** 理由：现在 RK 端还没有连续帧入口（`traffic9_rknn.py` 只遍历静态图片 `[已验证]`），也没有轨迹叠加 RTL（`项目转向迁移方案.md` 自述缺口 `[已验证]`），直接写 C++ 会没有可视反馈、无法调参。

**一句话风险：** ByteTrack 相对 YOLO 是「低风险算法 + 高风险集成」。算法本身 300 行就能移植完；真正会翻车的是**低分框被前置阈值杀掉**、**`track_buffer` 按帧数计而板端只有个位数 fps**、以及**跨类误检导致一物两轨**这三件事。

---

## 1. ByteTrack 算法本体（移植清单）

### 1.1 状态与数据结构

```
TrackState: New=0 / Tracked=1 / Lost=2 / Removed=3

STrack（单条轨迹）
  _tlwh           首帧测量（未启用 KF 前的占位框）
  mean      (8,)  KF 状态均值 = [x, y, a, h, vx, vy, va, vh]
  covariance(8,8) KF 协方差
  is_activated    bool   —— 决定是否进入输出
  score           float  —— 最近一次关联上的检测分
  tracklet_len    int    —— 命中计数（0 表示还没被更新过）
  state / frame_id / start_frame
```

- `x, y` = 框中心；`a` = 宽高比 `w/h`；`h` = 高。**不是** xyxy，也**不是**归一化坐标。
- `next_id()` 是 `BaseTrack._count` 类级自增，**全局单调**；逐类实例化时必须把它换成带 epoch/class 前缀的分配器（§4）。

### 1.2 单帧处理流程（10 步，与参考实现一一对应）

| # | 动作 | 关键细节 |
|---|---|---|
| 1 | `frame_id += 1` | 内部帧计数，与 FPGA `frame_id` 不是同一空间 |
| 2 | 按 `track_high_thresh` / `track_low_thresh` 切三池 | `dets`=高分(>0.5)；`dets_second`=低分(0.1~0.5) |
| 3 | `tracked_stracks` 拆成 `unconfirmed`(未激活) / `tracked`(已激活) | 未确认轨迹单独走第 8 步 |
| 4 | `strack_pool = joint(tracked, lost)`，**整体 predict** | `multi_predict`：非 Tracked 态把 `mean[7]`（vh）置 0。**参考实现此处有个众所周知的笔误：只冻结了 vh，vx/vy/va 仍然外推**；本文按参考实现保留该行为（见 §5.5） |
| 5 | 第 1 次关联：`cost = 1 - IoU(pool, dets)` → `fuse_score` → 匈牙利，阈值 `match_thresh` | 匹配上：Tracked 态 → `update()`；Lost 态 → `re_activate()`（**沿用旧 track_id**） |
| 6 | 第 2 次关联：`pool` 中第 1 次未匹配且仍为 Tracked 的 → 对 `dets_second` 再做一次 IoU 匈牙利，阈值固定 **0.5** | 这是 ByteTrack 的核心创新：**用低分框把被遮挡的轨迹接回来**。不经过 `fuse_score` |
| 7 | 第 6 步仍未匹配的 Tracked → `mark_lost()` | 进入 `lost_stracks` |
| 8 | 未确认轨迹 × 第 5 步剩下的高分框：IoU 匈牙利，阈值 **0.7** + `fuse_score` | 匹配上 → `update()` 并激活（这就是「连续 2 帧确认」）；未匹配 → `mark_removed()` |
| 9 | 剩下未匹配的高分框：若 `score >= new_track_thresh` → `activate()` 分配新 ID | 未达阈值的高分框**被丢弃**，不建新轨 |
| 10 | 老化：`frame_id - track.end_frame > max_time_lost` 的 Lost 轨迹 → `mark_removed()`；然后 `remove_duplicate_stracks()`（tracked × lost 做 IoU，`pdist < 0.15` 视为重复，保留 `frame_id - start_frame` 更大者） | 输出 = `tracked_stracks` 中 `is_activated == True` 的 |

**必须理解的三个「反直觉」点**（照抄时最容易改错）：

- **`is_activated` 与 `state` 是两回事。** `activate()` 只在 `frame_id == 1` 时才置 `is_activated = True`；正常帧新建的轨迹虽然 `state=Tracked` 但 `is_activated=False`，**当帧不输出**。要等第 8 步再匹配一次才输出 → 效果等于「连续 2 帧确认」，但代码里没有 `hit_streak` 这种计数器。
- **第 9 步的阈值是 `det_thresh = track_thresh + 0.1`**（不是 `track_thresh`）。方案文档 YAML 里的 `new_track_thresh: 0.60` 正好等于 `track_high_thresh(0.50) + 0.1`，两者一致。
- **`fuse_score` 会破坏「cost 单调 = IoU 单调」的直觉**：`fuse_sim = IoU × det_score`，即低分检测对同一轨迹的代价更大。所以第 5/8 步用、第 6 步（低分池）**不能用**，否则低分框永远配不上。

### 1.3 Kalman 滤波器的精确参数（照抄，不要"调优"）

`KalmanFilter`，`ndim=4`，常数速度模型，线性观测：

```
F = I(8) ; F[i, 4+i] = dt        （dt 默认 1.0）
H = [I(4) | 0(4)]
std_weight_position = 1/20 = 0.05
std_weight_velocity = 1/160 = 0.00625
```

| 阶段 | 噪声标准差（位置 4 维 / 速度 4 维） |
|---|---|
| `initiate` | pos: `2·0.05·h`，`a` 维固定 `1e-2`；vel: `10·0.00625·h`，`va` 维固定 `1e-5` |
| `predict`（过程噪声 Q） | pos: `0.05·h`，`a` 维固定 `1e-2`；vel: `0.00625·h`，`va` 维固定 `1e-5` |
| `project`（观测噪声 R） | `0.05·h`，`a` 维固定 **`1e-1`**，`0.05·h` |

其中 `h = mean[3]`（当前估计高度），**噪声随目标尺度自适应**——这就是为什么坐标必须统一到工作分辨率，见 §6.2。

`update` 用 Joseph 形式：
```
S   = H P Hᵀ + R          (4×4)
K   = P Hᵀ S⁻¹
新的 mean = mean + (z - H·mean) Kᵀ
新的 cov  = P - K S Kᵀ
```
参考实现用 `scipy.linalg.cho_factor/cho_solve`。**可以用 `np.linalg.solve(S, (P @ H.T).T).T` 等价替换**（`D:\ziguang\tracking\bytetrack\kalman.py`），本文的做法是用纯 NumPy 实现 + 用 `scipy.linalg` 写单测交叉验证（`tests\test_kalman.py`）。

### 1.4 关联求解器与两个实现差异（**必须显式处理**）

参考实现用 `lap.lapjv(cost, extend_cost=True, cost_limit=thresh)`，然后**在赋值之后再过滤 `cost > thresh`**——注意 `cost_limit` 是在求解器内部起作用的，不是简单事后截断。Ultralytics 版改用 `scipy.optimize.linear_sum_assignment`。

**本文的做法（`D:\ziguang\tracking\bytetrack\matching.py`）：**

```python
def linear_assignment(cost_matrix, thresh):
    """与 lap.lapjv(extend_cost=True, cost_limit=thresh) 语义对齐的近似实现。"""
    # 1) 补成方阵，pad 用有限大值 BIG=1e6（绝不能用 np.inf：scipy 会报错）
    #    补边的代价 BIG > thresh，保证任何"补边匹配"都会在第 3 步被滤掉
    # 2) row_ind, col_ind = scipy.optimize.linear_sum_assignment(cost)
    # 3) 只保留 idx < n_row 且 idx < n_col 且 cost <= thresh 的配对
```
- 第 3 步的 `cost <= thresh` 过滤与参考实现 `_indices_to_matches` 完全同构；补边保证「无可行匹配」的轨迹行/列落到补边上而不会被强行配对。
- **兼容性单测**：若环境里能装上 `lap`，`tests\test_matching.py` 用随机 cost 矩阵（含全 `inf`、全超阈、行列数悬殊等边界）比对两者输出；装不上则以「行为等价性人工论证 + 与 `scipy` 一致」为准并在文档记录。
- `linear_sum_assignment` 是最小化总代价的**全局**解，而 `lapjv` 也是；但两者在**代价相等**的退化情形下选解可能不同。这会改变 ID 分配，因此 A/B 实验必须冻结求解器版本（写进 `env_fingerprint.json`）。

---

## 2. 与本项目现有链路的精确插入点

### 2.1 上游：YOLO 后处理必须改的 4 处

权威后处理在 `D:\ziguang\traffic_yolo_deploy\deploy_rk3568\traffic9_postprocess.py`（243 行）。它有 3 个副本必须同步（PC 核验 `make_precision_report.py`、旧项目约定 `rk3566_deploy\plate_preprocess.py`），因此**修改要保持向后兼容**。

| # | 现状 | 改法 | 为什么 |
|---|---|---|---|
| 1 | `postprocess(..., conf_thres=0.25, iou_thres=0.45, multi_label=True)` | 跟踪开启时用 `conf_thres = track_low_thresh = 0.10` 跑一次；关闭时用 `object_conf_thresh` | 方案文档 §7A.3 伪代码 `decode_floor = tracking_enabled ? track_low_thresh : object_conf_thresh`；`[已验证]` `traffic9_postprocess.py` 注释已警告「不能在跟踪前先按展示高阈值删光低分框」 |
| 2 | `multi_label=True` 硬编码（`traffic9_rknn.py` 与 `make_video_detections.py` 调用处都写死） | **跟踪路径必须 `multi_label=False`**；`make_video_detections.py` 增 `--multi-label` 开关（默认保持 True，避免污染已有的 mAP 口径） | `[已验证]` `multi_label=True` 时一个框可产生多条不同类检测（ultralytics 口径）。同一个物理目标同时进两个类池 → 两条轨迹 → 必然 ID 抖动 |
| 3 | 三尺度合并后一次 NMS，用 `+ cls*7680` 错开 | **不改** | `[已验证]` 逐尺度各压一次会多出 54% 重复框；错开是「行人站在车里」不被合并的唯一保证 |
| 4 | 无「检测时刻」概念 | 新增：每帧检测带 `(frame_id, ts_detect_us)`。板上取 `t_first` 与 `t_done` 的中值；离线取 `frame_idx / fps` | 方案文档 §7A.2 要求输入含 `rk_monotonic_ts_us`；KF 的速度单位需要它 |

**分流写法（保持 `OBJECT` 语义不变）：**

```python
cand = postprocess(outs, ..., conf_thres=decode_floor, multi_label=False)   # decode_floor
obj  = [d for d in cand if d.score >= object_conf_thresh]                   # → OBJECT（仅本帧真实检测）
trk  = [d for d in cand if d.score >= track_low_thresh]                      # → 跟踪输入
```
`OBJECT` **永远只含当帧真实检测**，与跟踪开关无关——方案文档 §9 表格 `rk_tracking` 行与 §7A.3 注释都要求这一点，`SAT-TRACK-BASE` 的判据是「OFF 时 OBJECT 不丢失」，所以这两条路径必须能独立开关。

### 2.2 下游：`TRACK_V1` 消息（**只定义，不在本次实现**）

方案文档 §6.6 的字段（`track_id` / `class` / `bbox` / `state` / `observation` / `last_detect_frame_id` / `missing_frames`）精确对应到现有回传协议 `D:\ziguang\rk3566_deploy\README.md:416-423`（`header 10B + box 10B`）。**注意硬约束：**

- 现有 box 是 `x1,y1,x2,y2(i16) score(u8) cls(u8)` = 10 B；`TRACK_V1` 至少要再加 state(u8) + missed(u8) + track_id。**`track_id` 用 64 位打包（§4）在 24 B/框的预算下放得下**，但若 FPGA 侧要直接解析，字段宽度必须由协议负责人冻结。
- 方案文档明确「最终消息类型号由 T00-06 协议负责人分配，本文件不硬编码编号」——**本文同样不分配编号**，实现里用 `MSG_TYPE_TRACK_V1 = None` 占位并在启动时若为 `None` 则只写本地文件/日志。
- `[已验证]` 现有回传链路（`rk3566_deploy\README.md`）实测「8/8 收到、CRC 全对、frame_id 对应正确」，可直接复用 CRC16 与组帧代码，规则：crc16 覆盖除 crc 字段本身以外全部字节。

### 2.3 不会被本方案触及的东西（明确划界）

- **FPGA 侧轨迹叠加绘制 RTL：无实现**（`项目转向迁移方案.md` 自述缺口 `[已验证]`）。因此 ByteTrack 的产物在本阶段只能进 **PC Dashboard / 离线视频**，不能进 HDMI 叠加画面。这是「先做 Python 版」的第二个理由。
- `udp_vision\frame_assembler.py` 提供的 `ReassembledFrame`（`frame_id/t_first/t_done/span_ms/complete/missing_pkts/rows_bad`）**正是跟踪器需要的输入元数据**，本次不改它。

---

## 3. 目标模块设计

### 3.1 目录布局（全部新增，不改动 `traffic_yolo_deploy` 既有脚本）

```
D:\ziguang\tracking\                       # 新增顶层包（与 opencv_lane\ 同级，可被板端单独拷贝）
  __init__.py
  bytetrack\
    __init__.py
    config.py          # @dataclass TrackerConfig；from_yaml()/to_yaml()
    kalman.py          # KalmanFilter（纯 numpy，逐位对齐参考实现）
    matching.py        # iou_distance / fuse_score / linear_assignment（§1.4）
    strack.py          # STrack / TrackState / 全局 ID 分配器
    byte_tracker.py    # ByteTracker.update(frame_id, ts_us, tlbr, scores, dt_scale)
    multi_class.py     # MultiClassByteTracker：9 个实例 + epoch + 单帧预算门控 + 复位
    reset.py           # ResetPolicy / ResetReason（来源/模式/标定/跳号/时间戳倒退）
  adapters\
    traffic9_detector.py  # 复用 traffic9_postprocess，输出 Detection 列表（PC onnx / 板 rknn 双跑）
    rknn_stream.py        # 板端连续帧入口（UDP 收帧 → 检测 → 跟踪 → 回传），依赖 udp_vision
    track_proto.py        # TRACK_V1 组帧/解帧（编号留 None 占位）
  viz\
    overlay.py            # 轨迹 ID + 拖尾 + PREDICTION 虚线（复用 traffic9_postprocess.draw 风格）
    render_tracked_video.py
  bench\
    bench_tracker.py      # track_ms P50/P95、内存、逐类轨迹数；可切 OFF/ON A/B（RKD-36）
    report_track_stats.py # IDF1/IDSW/MOTA（有真值时）+ 轨迹断裂/重复率（无真值时）
D:\ziguang\traffic_yolo_deploy\deploy_rk3568\
  tracker.yaml                       # 参数冻结点（方案文档 §7A.2 样例 + 本文默认值）
  traffic9_track.py                  # CLI：--source 目录/视频/udp，--tracker tracker.yaml
  traffic9_track_replay.py           # 从 detections.jsonl 重放（离线联调与回归，不跑 NPU）
D:\ziguang\tracking\tests\
  test_kalman.py  test_matching.py  test_iou.py  test_two_stage.py
  test_reset.py   test_id_encoding.py  test_dt_scale.py
D:\ziguang\docs\
  字节跟踪方案-ByteTrack落地.md       # 本文
  字节跟踪验收矩阵.md                 # 后续填实测数（RKD-36~39 对照）
```

### 3.2 核心接口（签名先冻结，实现照此写）

```python
# tracking/bytetrack/config.py
@dataclass
class TrackerConfig:
    track_high_thresh: float = 0.50     # 第 5 步高分池下限（= 方案文档 track_high_thresh）
    track_low_thresh:  float = 0.10     # 第 6 步低分池下限；同时是 decode_floor
    new_track_thresh:  float = 0.60     # 第 9 步建新轨门槛（= track_high_thresh + 0.1）
    match_thresh:      float = 0.80     # 第 5/8 步匈牙利代价上限
    match_thresh_low:  float = 0.50     # 第 6 步（参考实现里是硬编码 0.5，本文参数化）
    fuse_score:        bool  = True
    track_buffer_s:    float = 0.50     # 【语义变更】丢失后保留的**秒数**，见 §5.2
    track_buffer_frames: int | None = None   # 若给定则覆盖上面的秒数换算，仅用于复现参考实现
    det_stride:        int   = 1        # 检测抽帧步长；dt_scale = 本帧与上帧的检测间隔/步长
    min_confirmed_frames: int = 2       # == 参考实现 is_activated 语义；1 = 输出单帧轨（会抖）
    emit_unconfirmed:  bool  = False    # True 时输出 state=TENTATIVE 的框（display 层自行过滤）
    emit_prediction:   bool  = True     # 丢检帧是否输出预测框（必须标 PREDICTION）
    classes_tracked:   tuple[int, ...] = (0, 1, 4, 5, 6, 7)   # car/person/truck/bus/moto/bicycle
    classes_static:    tuple[int, ...] = (2, 3)               # traffic light / sign：默认不跟踪，见 §5.6
    working_size:      tuple[int, int] = (1280, 720)          # 坐标系冻结值，进 tracker_epoch
    track_ms_budget_p95: float = 5.0    # 方案文档 §7A.4 首版门禁（待板测修订）
```

```python
# tracking/bytetrack/byte_tracker.py
class ByteTracker:
    def update(self, frame_id: int, ts_us: int,
               tlbr: np.ndarray,      # (N,4) float32，已反变换到 working_size 坐标
               scores: np.ndarray,    # (N,)
               dt_scale: float = 1.0  # 相对上一次检测的帧间隔倍数，见 §5.1
               ) -> list[Track]: ...
    def reset(self, epoch: int, reason: str) -> None: ...

@dataclass
class Track:
    global_id: int          # 64 位打包，见 §4
    class_id: int
    local_id: int
    xyxy: tuple[float, float, float, float]
    score: float
    state: str              # 'TRACKED' | 'LOST' | 'TENTATIVE'
    observed_this_frame: bool   # 对应方案文档 observation 字段
    last_detect_frame_id: int
    missing_frames: int
    epoch: int
```
`Track` 的字段与方案文档 §9 表格里 `tracks[]` 的列**一一对应**，不做增删改名。

---

## 4. ID 编码与 `tracker_epoch`

方案文档两条硬要求的联立解：

- §7A.2 类别行：「若逐类 tracker 的内部 ID 重复，应编码 `(class_id, local_id)` 为展示唯一 ID」
- §7A.2 复位行：「清空 tracker，`tracker_epoch++`」「不能沿用旧 ID 作为新源对象 ID」
- §7A.4-3：复位测试要「检查每类 ID 和 `tracker_epoch`」

**编码（`tracking/bytetrack/strack.py`）：**

```python
ID_EPOCH_SHIFT, ID_CLASS_SHIFT = 40, 32
def pack_id(epoch: int, class_id: int, local_id: int) -> int:
    return (epoch << 40) | (class_id << 32) | (local_id & 0xFFFF_FFFF)
def unpack_id(gid: int) -> tuple[int, int, int]:
    return gid >> 40, (gid >> 32) & 0xFF, gid & 0xFFFF_FFFF
```
- 3 段都取回得到 `epoch`（复位代数）、`class_id`（类别，**一条轨迹终身不变**）、`local_id`（逐类自增）。位数分配：local_id 32 位（≈4.3e9 条）、epoch 24 位、class 8 位。
- **JSON 里 `track_id` 必须写成字符串**（`str(global_id)`）。64 位整数超过 JS 的 `2^53` 安全整数范围，写数字会在 Dashboard 端静默失真。
- 人类可读形式：`printf("V%02X-%u-%06X", epoch, class_id, local_id)`。

**`tracker_epoch` 递增的复位条件（与方案文档 §7A.2 复位行 + §7.4 六种强制复位对齐）：**

| 触发 | 判定 | 动作 |
|---|---|---|
| 时间戳倒退 | `ts_us <= last_ts_us` | 全清 + `epoch++`，reason=`TS_REGRESSION` |
| `frame_id` 超窗跳变 | `frame_id - last_frame_id > max_frame_gap` | 全清 + `epoch++`，reason=`FRAME_GAP` |
| `frame_id` 倒退 | `frame_id <= last_frame_id` | 全清 + `epoch++`，reason=`FRAME_REGRESSION` |
| 来源/模式/标定变化 | `(source, mode_id, calibration_id)` 变化 | 全清 + `epoch++` |
| 工作分辨率/类别集变化 | `working_size` 或 `classes_tracked` 变化 | 全清 + `epoch++` |
| 摄像头中断 | 无有效帧超过 `link_timeout_s` | 全清 + `epoch++` |
| 残帧/丢包过多 | `missing_pkts / total_pkts > partial_frame_drop_ratio` | **该帧丢弃、不 update、不清空**（单次漏帧按策略留存，但不作新观测） |
| 检测异常 | 后处理抛错/输出形状不符 | 该帧跳过，连续 `N` 帧异常则 `epoch++` 且 `unavailable(TRACK_ERROR)` |

> `max_frame_gap` 的默认值取 `ceil(max_time_lost_frames * 2)`，即**允许的最大老化窗口的两倍**；超过这个间隔时，速度外推已经把框推到画面外，继续关联只会制造错误 ID。

**`SAT-TRACK-RESET` 判据对齐：** 方案文档要求「变化后 ≤1 有效检测帧清旧 ID」。因为复位是**在同一次 `update()` 内、关联之前**执行，复位后的第一个有效检测帧就是用新 epoch 建的新 ID——天然满足 ≤1 帧。

---

## 5. 逐类门控、非均匀 Δt 与板端帧率（本项目的三个真差异）

### 5.1 差异一：帧间 Δt 不是常数

参考实现隐含 **30 fps 且每帧都检测**。本项目的现实：

- `[已验证]` 板端 NPU 单帧推理是系统瓶颈（640 档 INT8 在 x86 上 66.2 ms，见 `report\resolution_compare.md`），板端只会更慢；
- `[设计]` 检测按 `det_stride` 抽帧（PC 实验先 `det_stride=2`）；
- `[已验证]` UDP 重组会因丢包产生残帧（`udp_vision\frame_assembler.py` 的 `allow_partial` / `frame_timeout_s`），帧间隔会抖。

**做法：** `update()` 接一个 `dt_scale`（相对「一个标称检测间隔」的倍数），KF 的 `predict` 用 `F(dt_scale)` 而不是固定 `dt=1`：

```python
F = np.eye(8)
for i in range(4):
    F[i, 4 + i] = dt_scale
```
- `dt_scale = Δframe_id / det_stride`，即「实际隔了几个检测周期」。同一段视频用 `det_stride=1` 与 `det_stride=2` 跑，速度估计的**物理单位**一致，ID 应该基本一致——这就是 `test_dt_scale.py` 的判据。
- **代价**：`dt_scale=1` 时与原实现逐位等价，所以这个改动**不影响与参考实现的一致性验证**（`test_kalman.py` 用 `dt_scale=1` 对 `scipy.linalg` 版和手算值做双重交叉验证）。
- 其它 4 维（`a`、`va`）不随 dt 变化，因为宽高比是几何量、不是位移。

### 5.2 差异二：`track_buffer` 必须按**真实时间**定义，不能按帧数

这是本次移植**最容易致命的一条**。参考实现的 `max_time_lost = buffer_size`，是在 30 fps 下等于 1 秒的**帧数**。板端若是 6 fps：

- 方案文档样例 `track_buffer: 15`（帧）→ 在 6 fps 下是 **2.5 秒**盲区。一辆 60 km/h 的车 2.5 秒走 **41.7 米**，早已离开画面或变成另一个目标；此时把它「接回来」只会产生错误关联，且预测框与真实位置相差上百像素。
- 方案文档 §7A.2 自己留了口子：「`track_buffer: 15` —— 单位通常为 tracker 更新帧；**抽帧时换算真实有效老化时间**」。

**做法（`config.py`）：**

```python
@property
def max_time_lost_frames(self) -> int:
    if self.track_buffer_frames is not None:
        return self.track_buffer_frames                    # 复现参考实现用
    fps_eff = self.measured_detect_fps or 30.0             # 【待测】板端实测推理帧率
    aging_s = self.track_buffer_s                          # 默认 0.50 s
    return max(1, round(aging_s * fps_eff / self.det_stride))
```
- 生效值由 **`traffic9_track.py` 在 warmup 后实测推理帧率**回填，并把 `track_buffer_frames_effective` 写进日志与 `stats.json`——**不允许静默**。
- 文档与验收表里同时记录「`track_buffer_s`」和「折算帧数」，方案文档要求的「换算真实有效老化时间」即此。
- 参考实现的 `buffer_size = int(frame_rate / 30.0 * track_buffer)` 只在 `frame_rate=30` 时与本式一致；PC 离线实验帧率固定 29.97，可直接对齐做回归。

### 5.3 差异三：逐类实例 + 单帧预算门控

**逐类实例的代价与收益：**

| | 逐类 9 实例 | 单实例 + 类门控 |
|---|---|---|
| 跨类跳类 | **结构性不可能** | 靠 `cost` 掩码，理论上仍可能（若掩码写错/退化） |
| 跨类误检 | 会产生两条轨迹（**已知限制，见 §9**） | 同样会产生，且更隐蔽（同一 ID 池被两用） |
| 匈牙利矩阵维度 | ≤ 该类的量级（通常 ≤20） | 全部目标（可能 100+） |
| 开销 | 9 次 `predict` + 9 次小 `linear_sum_assignment` | 1 次中等规模 |

**门控（`multi_class.py`）：** 每帧累计 `track_ms`，若某类本帧跟踪耗时超过 `track_ms_budget_p95`，对该类**降低更新频率**（隔帧更新，`dt_scale` 相应放大）而不是整体关闭——保证 `TRACK_V1` 仍持续输出、`unavailable` 只在真正故障时出现（方案文档 §7A.4-4：不能让跟踪阻塞主检测线程）。

### 5.4 逐类实例的实现纪律

- 参考实现里 `BaseTrack._count` 是**类级**变量，`STrack.shared_kalman` 是**静态**实例。逐类实例化时两者都会变成跨类共享状态 → **必须改为每类持有自己的 ID 计数器与 Kalman 实例**（`KalmanFilter` 无状态，共享也无害，但仍以显式持有为准，避免以后有人往里加状态）。
- 第 10 步的 `remove_duplicate_stracks` **只在同类内做**。不做跨类去重（理由见 §9 风险表）。
- 输出时按 `global_id` 排序，保证同一帧的输出顺序稳定（便于 A/B diff）。

### 5.5 保留参考实现的两个「不完美」行为

**不要顺手"修好"它们**，否则与论文/参考实现的 A/B 结果无法对齐：

1. `STrack.predict()` 只把 `mean[7]`（vh）置 0，`vx/vy/va` 仍外推（原意应该是四个速度全冻结）。
2. `remove_duplicate_stracks` 用 `pd < 0.15`（IoU > 0.85）判重复，且用 `frame_id - start_frame` 比较「谁更久」。

两者都记为 **`known_deviation_of_reference`**，写进 `tracker.yaml` 的注释；若 A/B 显示它们是 IDSW 主因，再开 `strict_freeze_velocity: bool` 与 `dedup_iou: float` 两个开关做对照实验，**而不是默认改掉**。

### 5.6 `traffic light` / `traffic sign` 是否跟踪（方案文档要求「单独论证」）

**决定：默认不跟踪（`classes_static=(2,3)`），只做「存在性判定」，与方案文档 §8 的 `TRAFFIC_SIGNAL` 规则一致。**

理由：
1. `[已验证]` 这两类在 320 档的 mAP@0.5 只有 0.36 / 0.42（`report\full320.md`），在 640 档 FP32 是 0.53 / 0.45（`resolution_compare.md`），远低于 car 的 0.94。低分池里这两类会充斥误检，`fuse_score` 会把它们塞给任何邻近轨迹。
2. 方案文档 §7A.4-2 明确「BDD100K 官方 MOT **只评估前 8 类**；`traffic_light/sign` 不计入 MOT 对照」——跟不跟都不进指标，却会污染指标。
3. 语义上红绿灯是**静态设施**（相对路面的运动来自自车），对它做恒速模型跟踪没有物理意义；真要「信号灯状态持续判定」，应该用 `lane`/`ego` 坐标系而不是图像坐标系。

**留出的口子：** `classes_static` 只是默认值；若后续要做「同一信号灯多帧确认」，把它挪进 `classes_tracked` 即可，代码路径完全相同。此时**必须**同时报告跨类重复率（§9）。

---

## 6. 与方案文档 §7A 的逐条对照

| 方案文档要求 | 本文落地 | 状态 |
|---|---|---|
| §7A.2 输入：`frame_id, rk_monotonic_ts_us, class_id, xyxy, score` | `ByteTracker.update(frame_id, ts_us, tlbr, scores)` + `MultiClassByteTracker` 按 class 分发 | `[设计]` |
| §7A.2 坐标统一 1280×720；不混用 320×240 | `working_size` 冻结进 epoch；反变换用 `scale_boxes()`，**反变换后**才进 KF | `[设计]` |
| §7A.2 高低分池，不能提前删低分框 | `decode_floor = track_low_thresh`；`postprocess(conf_thres=decode_floor, multi_label=False)` | `[设计]`，需改 `traffic9_postprocess.py` 调用处 |
| §7A.2 逐类 + `(class_id, local_id)` 编码 | 9 个实例 + `pack_id(epoch, class, local)` | `[设计]` |
| §7A.2 每检测帧一次 update，按 `frame_id` 递增；相机间不共享 | `MultiClassByteTracker` 每实例一份；`source` 进 epoch | `[设计]` |
| §7A.2 `TENTATIVE → CONFIRMED → LOST → REMOVED`；预测标 `PREDICTION` | `Track.state` 映射 + `observed_this_frame`；`emit_prediction` 输出的框在 `overlay.py` 里画虚线 | `[设计]` |
| §7A.2 复位 + `tracker_epoch++` | §4 的 8 条复位条件 | `[设计]` |
| §7A.3 `decode_floor` 随 `tracking_enabled` 切换 | `traffic9_track.py` 的 `--tracker` 开关驱动 | `[设计]` |
| §7A.3 「正式 RK 端优先 C++ 轻量移植，同进程」 | 本次先 Python；C++ 移植的触发条件是 §10 阶段 4 的门禁结果 | `[设计]`，**偏离**：见 §10 |
| §7A.4 首版性能门禁 P95 ≤ 5 ms（待板测修订） | `track_ms_budget_p95 = 5.0` + `bench_tracker.py` 报 P50/P95 | `[待测]` |
| §7A.4 `rk_tracking_YYYYMMDD.md` 证据文件 | 落 `docs\字节跟踪验收矩阵.md` | `[设计]` |

---

## 7. 分阶段落地计划

| 阶段 | 产物 | 完成判据 | 依赖 |
|---|---|---|---|
| **P0 离线算法自证** | `tracking\bytetrack\*` + 6 个单测 | ①`dt_scale=1` 时 KF 与 `scipy.linalg` 参考版逐位一致（rtol 1e-10）；②`linear_assignment` 与 `lapjv`（若可装）在同批随机矩阵上输出一致；③两阶段关联在合成序列上恢复遮挡轨迹；④复位 8 条各有单测 | 纯 numpy/scipy |
| **P1 离线视频 e2e（可视化 + A/B）** | `traffic9_track.py`、`render_tracked_video.py`、`traffic9_track_replay.py` | ①同一段视频 OFF/ON，`OBJECT` 框**完全一致**；②出带 ID 的 mp4；③`track_ms` P50/P95 曲线 | **需先补逐帧/隔帧检测数据（§8.1）** |
| **P2 板端 UDP e2e** | `adapters\rknn_stream.py` | ①UDP 收帧→检测→跟踪→回传闭环；②`frame_id` 一致率 ≥ 99.5%（方案文档 §5.3 PASS 判据）；③残帧跳过策略生效（日志可见） | RK3566/3568 板 + 已转好的 `.rknn` |
| **P3 指标与鲁棒性** | `report_track_stats.py` + `docs\字节跟踪验收矩阵.md` | RKD-36~39 逐项 PASS/FAIL/BLOCKED；无轨迹真值时至少给出「IDSW 上界估计 + 轨迹断裂数 + 短时遮挡恢复率」 | P1/P2 |
| **P4（可选）C++ 移植** | C++ 版 `byte_tracker` | **仅当** P2 实测 `track_ms` P95 超预算，或要与 RKNN C API 同进程；否则 Python 版直接交付 | P2 |

**P0 可以立刻开工，不需要 GPU / 不需要板子 / 不需要等待数据补齐。**

---

## 8. 验证与实验设计

### 8.1 先补数据：现有离线数据**不能**验证低分池

`[已验证]` `D:\ziguang\traffic_yolo_deploy\video_report\_run\detections.jsonl`（1596 行，`{"f":0,"t":0.0,"n":11,"d":[[cls,score,x1,y1,x2,y2],...]}`）**不适合验证 ByteTrack**，三个原因缺一不可：

| 问题 | 现状 | 影响 |
|---|---|---|
| `conf=0.30` 截断 | 低于 0.30 的框根本没落盘 | `track_low_thresh=0.10` 的低分池为空 → **第 2 阶段关联永远不会触发** → 等于跑了个残缺版 ByteTrack |
| `det_stride=10`（3 fps） | 帧间隔 0.33 s | 60 km/h 车一帧位移可达 5.5 m；KF 速度项对应「每 10 帧」的位移，恒速模型误差巨大 |
| `multi_label=True` | 一框可多类 | 同一个目标进两个类池 → 人为制造 ID 抖动 |

**补数据方案（二选一，速度差 ~10×）：**

- **A 重跑全帧（15 fps，用于最终指标）**：`det_stride=2` → 15960/2 = 7980 次推理，x86 onnxruntime 640 档约 30 ms/帧（`[已验证]` `report\resolution_compare.md` 的 29.4 ms 是 FP32、66.2 ms 是 INT8）+ letterbox/NMS，估计 **1.5~3 小时**（`[待测]`，以实测为准）。
- **B 只重跑低分通道（快，用于先验证机制）**：保持 `det_stride=10`，但 `conf=0.05`、`multi_label=False`，牺牲时序密度换取「低分池是否真的存在」这个关键结论。

命令（两种都用同一个脚本，只需加 `--multi-label` 开关）：

```powershell
python D:\ziguang\traffic_yolo_deploy\video_report\make_video_detections.py `
  --video <原视频> --onnx D:\ziguang\traffic_yolo_deploy\runs\traffic9_640_full\weights\traffic9_split6_640.onnx `
  --out D:\ziguang\traffic_yolo_deploy\track_run\det_stride2 `
  --imgsz 640 --conf 0.05 --iou 0.45 --det-stride 2 --img-stride 0 --multi-label false
```
> `[设计]` `--img-stride 0` 需要给 `make_video_detections.py` 加一个「不存图」的分支（现在 `img_stride` 为 0 会除零/每帧存图）。这是 P1 的第一个小改动。

**`--conf 0.05` 的代价必须量化**：低阈值会让 NMS 后候选数暴增，`stats.json` 里要新增 `score_hist` 与 `n_candidates_per_frame` 分位数（P50/P95/max）。若 P95 候选数超过 `max_det=300`，说明 `max_det` 已经成为新的截断点，**必须调大并重跑**——否则低分池又被 `max_det` 悄悄截断了（这是 §0 说的「低分框被前置阈值杀掉」的第二种形态）。

### 8.2 A/B 矩阵

| 实验 | 变量 | 必须报告的指标 |
|---|---|---|
| `E1` 跟踪关闭基线 | `tracking_enabled=false`，`conf=object_conf_thresh` | `OBJECT` 框数/帧、`decode_ms/nms_ms/pipeline_ms` P50/P95 |
| `E2` 跟踪开启 | 同 E1 视频与模型，`tracking_enabled=true` | **`OBJECT` 必须与 E1 逐框完全一致**（这是回归断言，不是指标）；`track_ms` P50/P95；端到端 FPS、CPU/RSS |
| `E3` 低分池消融 | `track_low_thresh ∈ {0.05, 0.10, 0.20, 0.30}` | 每条轨迹的**低分恢复次数**（第 6 步匹配计数）、IDSW、轨迹断裂数。**这一列直接反驳/证实「低分关联有效」** |
| `E4` 老化时间消融 | `track_buffer_s ∈ {0.2, 0.5, 1.0, 2.5}` | IDSW、错误恢复次数（恢复后与真值 IoU < 0.3 的恢复） |
| `E5` 抽帧一致性 | `det_stride ∈ {1, 2}`，`dt_scale` 开/关 | 同一目标 ID 在两条流水线里的一致率。**验证 §5.1 的 dt_scale 是否真的把速度单位归一了** |
| `E6` 求解器一致性 | `linear_assignment` 实现（scipy vs lapjv） | 逐帧 ID 分配差异条数。差异 > 1% 则必须冻结求解器并记录 |

`E3` 是本方案**最有信息量的一列**：如果提高 `track_low_thresh` 不改变 IDSW，说明低分池根本没起作用（要么模型低分框太少、要么被 `max_det`/NMS 截断），此时应按 §0 的风险处理，而不是继续调参。

### 8.3 一次性实现的自检脚本

```powershell
# 1) 算法正确性
python -m pytest D:\ziguang\tracking\tests -q
# 2) 单帧跟踪耗时（含 9 类分派）
python D:\ziguang\tracking\bench\bench_tracker.py --det-jsonl <detections.jsonl> --repeat 3 --warmup 100
# 3) 从落盘检测重放（不跑 NPU，秒级迭代）
python D:\ziguang\traffic_yolo_deploy\deploy_rk3568\traffic9_track_replay.py `
  --det-jsonl <detections.jsonl> --tracker D:\ziguang\traffic_yolo_deploy\deploy_rk3568\tracker.yaml `
  --out D:\ziguang\traffic_yolo_deploy\track_run\replay1
# 4) 端到端视频 + ID 可视化
python D:\ziguang\traffic_yolo_deploy\deploy_rk3568\traffic9_track.py `
  --video <原视频> --onnx <traffic9_split6_640.onnx> --imgsz 640 --conf 0.05 `
  --tracker D:\ziguang\traffic_yolo_deploy\deploy_rk3568\tracker.yaml `
  --out D:\ziguang\traffic_yolo_deploy\track_run\e2e1 --render
```

---

## 9. 风险登记（每条都带处置，不只列现象）

| 风险 | 严重度 | 依据 | 处置 |
|---|---|---|---|
| **① 低分框在 INT8 下退化**：640 档 INT8 的分数分布可能被压到 0/1 附近，0.10~0.30 区间稀疏 → 第 2 阶段关联无输入 | **高** | `[已验证]` 320 档 INT8 使 9 类里 6 类掉点（`report_full320.md` 逐类数据），说明 INT8 确实在动分数分布；但**没有**分数直方图的实测证据 | `E3` 消融 + `stats.json` 新增 `score_hist`；若确证退化，则 `decode_floor` 改用 **FP32 `.rknn`**（方案文档已给回退路径：`do_quantization=False`），或对分数做单调重标定后再进跟踪 |
| **② 板端 fps 远低于 30**：`track_buffer` 帧数 → 实际盲区数秒 | **高** | `[已验证]` 640 INT8 在 x86 已 66.2 ms；`[已验证]` 板端是 4×A55 | §5.2 的秒数语义 + warmup 实测回填 + 日志明示；`E4` 消融确定 `track_buffer_s` |
| **③ 跨类误检 → 一物两轨**（car 被同时检出 truck） | 中 | `[已验证]` `multi_label=True` 时一框可产生多条不同类检测；`nms_numpy` 按类错开是**有意**设计 | **不修**（跨类去重会让同一物理目标的 ID 在不同帧间跳类，违反 §7A.2）；改为**度量并上报**：`report_track_stats.py` 统计「同类间 IoU>0.5 且类别不同的并存轨迹对数」与轨迹长度。跟踪路径用 `multi_label=False` 已经把这个问题压到最小 |
| **④ 匈牙利求解器差异改变 ID** | 中 | §1.4：`lapjv(cost_limit)` ≠ `linear_sum_assignment` 的补边写法在退化情形下可能不同解 | 兼容性单测 + `env_fingerprint.json` 冻结版本 + `E6` 量化差异 |
| **⑤ 逐类 9 实例的 Python 开销超 5 ms 预算** | 中 | `[待测]`；A55 单核比 x86 慢 2~4× | 先测再决定；超预算时的顺序是：①合并小类 ②隔帧更新（`dt_scale` 补偿）③C++ 移植（P4） |
| **⑥ 跟踪与 UDP 收包线程争 CPU** | 中 | `[已验证]` `udp_vision\udp_receiver.py` 注释明确警告收包线程不能被阻塞；720P 需 43k 包/s、单核约 15% | 跟踪**必须**在收包线程之外的消费者线程里跑（`on_frame` 回调或队列消费者），方案文档 §7A.3 伪代码的「同进程」不等于「同线程」；实现里显式断言不注册 `on_frame` 直通跟踪 |
| **⑦ 跟踪帧与 `LANE`/`MOTION` 帧不同源** | 中 | 方案文档 §5.3 PASS 判据要求 `frame_id` 一致率 ≥ 99.5% | 跟踪只接受带 `frame_id` 的 NPU 帧；`frame_id` 不匹配时输出 `TRACK_STALE`，不做任何跨源补齐（方案文档 §7A 明文禁止「用另一相机视频偷偷补充」） |
| **⑧ 无真值 → IDF1/MOTA 无法计算** | 中 | `[已验证]` 现有素材是普通行车记录视频，无 MOT 标注；方案文档 §7A.4-2 要求 BDD100K MOT 或**自行合法标注** | P3 先交付无真值指标（IDSW 上界、断裂数、短时遮挡恢复率、跨类重复率），把「自标注 300~500 帧片段」列为独立任务，不阻塞主链路 |
| **⑨ 与 `traffic9_postprocess.py` 三副本同步** | 低 | `[已验证]` 该文件被 PC 核验与旧项目共同依赖 | 只**新增**关键字参数（`multi_label` 已有、`conf_thres` 已有），默认值一律不变；改完必须重跑 `make_precision_report.py` 确认 mAP 与冻结值一致（`[已验证]` 640 档官方口径 0.6398 / 0.4590） |
| **⑩ HP60/器件口径混淆（RK3568 vs RK3566）** | 低 | `[已验证]` `rk3566_deploy\README.md` 写 **RK3566**（4×A55@1.8G，4GB），方案文档全篇写 **RK3568**；A55 架构同但 NPU 算力不同 | 所有性能数字标注实测器件；`stats.json` 写 `device: "rk3566"|"rk3568"|"x86"`；不跨器件外推 TOPS/fps |

---

## 10. 与方案文档的两处已知偏离（需用户/评审确认）

1. **「正式 RK 端优先 C++ 轻量移植」（§7A.3）→ 本文先做 Python 版。**
   理由：①RK 端现在没有连续帧入口（`traffic9_rknn.py` 只遍历静态图片 `[已验证]`），C++ 版会同时引入「接口设计 + 语言迁移 + 无可视化」三重风险；②FPGA 轨迹叠加 RTL 不存在 `[已验证]`，C++ 版没有可用的展示出口；③方案文档自己留了「首版可先在 PC 用 Python 验证检测框/ID 行为」的口子。**触发 C++ 移植的条件写进 P4：`track_ms` P95 超预算，或需要与 RKNN C API 同进程。** 若评审坚持 C++ 优先，则 P0 的单测与 `tracker.yaml` 参数语义仍可 1:1 复用，返工成本主要在 `kalman.py`/`matching.py` 的语言翻译。

2. **`track_buffer` 的单位从「帧」改成「秒」**（`track_buffer_s`）。
   理由见 §5.2。方案文档原文写的是 `track_buffer: 15 # 单位通常为 tracker 更新帧；抽帧时换算真实有效老化时间`——本文把「换算」这一步**前置到配置语义里**，`track_buffer_frames` 保留为显式覆盖项以便复现参考实现。这不改变方案文档的验收判据，只改变参数的表达方式。

**Open questions（需要确认后才能冻结参数）：**
- Q1：板端实测推理帧率是多少？（决定 `det_stride`、`max_time_lost_frames`、以及 640 档是否可行）
- Q2：`OBJECT` 的展示阈值 `object_conf_thresh` 是否就是现有报告的 0.30？（决定 `decode_floor` 与高分池的距离，进而决定两阶段是否真的分得开）
- Q3：`TRACK_V1` 的消息类型号与 `track_id` 字段宽度由谁冻结（T00-06 协议负责人）？
- Q4：是否有合法的连续视频可用于自标注 MOT 真值？（决定 P3 能否给出 IDF1/MOTA，而不只是上界估计）
- Q5：目标器件最终是 RK3566 还是 RK3568？（决定性能预算与 NPU 单核算力口径）

---

## 11. 参考实现原文记录（供 C++ 移植时逐位对齐）

本方案对照的源码（MIT）：
`yolox/tracker/byte_tracker.py`、`kalman_filter.py`、`matching.py`、`basetrack.py` @ `ifzhang/ByteTrack` main 分支。

**参数语义映射表（三个命名体系，最容易配错的地方）：**

| 参考实现（原生） | Ultralytics（`bytetrack.yaml`） | 方案文档 YAML | 本文 `TrackerConfig` | 生效位置 |
|---|---|---|---|---|
| `args.track_thresh` | `track_high_thresh` | `track_high_thresh: 0.50` | `track_high_thresh` | 第 2 步切高分池 |
| 硬编码 `0.1` | `track_low_thresh` | `track_low_thresh: 0.10` | `track_low_thresh` | 第 2 步切低分池 + `decode_floor` |
| `args.track_thresh + 0.1` | `new_track_thresh` | `new_track_thresh: 0.60` | `new_track_thresh` | 第 9 步建新轨 |
| `args.track_buffer`（帧） | `track_buffer`（帧） | `track_buffer: 15`（帧） | `track_buffer_s`（秒）**偏离** | 第 10 步老化 |
| `args.match_thresh`（默认 0.8） | `match_thresh` | `match_thresh: 0.80` | `match_thresh` | 第 5/8 步 |
| 硬编码 `0.5` | 同上（复用） | — | `match_thresh_low` | 第 6 步 |
| `args.mot20`（False） | — | — | `fuse_score: true` | `fuse_score` 开关（`mot20=True` 表示**不**融合分数） |
| `frame_rate=30`（构造参数） | — | — | `measured_detect_fps` **待测** | `buffer_size` 换算 |
| `KalmanFilter()`（静态共享） | 同 | — | 每类独立持有 | 关联预测 |

**两阶段关联的三个阈值（0.8 / 0.5 / 0.7）在参考实现里只有 0.8 是可配的，另外两个是字面量。** 本文把 0.5 提为参数 `match_thresh_low`、0.7 保持字面量（因为它是「未确认轨迹延续」的判据，方案文档未涉及），若需调参必须同步修改本文档与 `tracker.yaml` 注释。
