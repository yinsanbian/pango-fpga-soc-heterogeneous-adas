<!-- 本文件由 dashboard/tools/gen_protocol_doc.py 从 docs/protocol_schema/*.json 生成，勿手改 -->

# 夜瞳统一协议 V1 —— 字段参考（自动生成）

- schema 目录：`docs/protocol_schema/`（`protocol.json` / `messages.json` / `enums.json`）
- magic：`0x5954`（"YT"），协议版本：v1，字节序：little-endian
- 公共头：40 字节，全部字段自然对齐，crc32 位于偏移 36（最后一字段）
- CRC：`zlib.crc32(header[0:36] ++ payload)`，标准多项式 0xEDB88320
- payload 上限：65535 字节（`payload_length` 为 uint16），超长消息必须分片

## 1. 公共头

| 偏移 | 字段 | 类型 | 字节 | 枚举 | 说明 |
|---:|---|---|---:|---|---|
| 0 | `magic` | `uint16` | 2 |  | 固定 0x5954 |
| 2 | `protocol_version` | `uint16` | 2 |  | 当前 1；接收端只接受 <= 自身版本 |
| 4 | `frame_id` | `uint32` | 4 |  | 源板采集帧号，跨板唯一锚点 |
| 8 | `timestamp_ns` | `uint64` | 8 |  | 发送端单调时钟，单位 ns；仅在同一 clock_domain_id 内可比 |
| 16 | `sequence` | `uint32` | 4 |  | 每 (source_id,message_type) 独立递增；用于丢帧/乱序判定 |
| 20 | `calibration_id` | `uint16` | 2 |  | 标定表版本；不匹配时接收端置 CALIB_MISMATCH |
| 22 | `payload_length` | `uint16` | 2 |  | payload 字节数，不含头 |
| 24 | `message_type` | `uint8` | 1 | CTRL=1 / HEALTH=2 / TIMING=3 / LANE=16 / MOTION=17 / FEATURE=18 / DEPTH=19 / LANE_TRACK=20 / OBJECT=32 / TRACK_V1=33 / ROADSTREAM=48 / ROADTHUMB=49 / UDP_VIDEO=50 |  |
| 25 | `source_id` | `uint8` | 1 | PANGU50K=0 / P100PRO_PLUS=1 / RK3568=2 / PC=3 / UNKNOWN=255 |  |
| 26 | `mode_id` | `uint8` | 1 |  | 0=camera,1=fusion,2=enhance |
| 27 | `status` | `uint8` | 1 | OK=0 / INVALID=1 / DEGRADED=2 / UNSUPPORTED=3 / STALE=4 |  |
| 28 | `invalid_reason` | `uint8` | 1 | NONE=0 / NO_INPUT=1 / NO_REF=2 / FRAME_MISS=3 / DEPTH_GATE=4 / LOW_CONFIDENCE=5 / OUT_OF_VALID_RANGE=6 / TRACK_DISABLED=7 / TRACK_STALE=8 / TRACK_ERROR=9 / INPUT_INVALID=10 / NO_DEPTH=11 / NO_TRACK=12 / AGE_TIMEOUT=13 / SEQ_GAP=14 / DT_OUT_OF_RANGE=15 / CAMERA_LOST=16 / LINK_DOWN=17 / HEARTBEAT_TIMEOUT=18 / CALIB_MISMATCH=19 / VERSION_UNSUPPORTED=20 / CRC_ERROR=21 / REPLAY_EOF=22 / NOT_PROVIDED=23 / LANE_LOST=24 / ROI_EMPTY=25 / NO_HEADING_SOURCE=26 / THERMAL_THROTTLE=27 / DEGRADED_NO_FLOW=28 | 偏离记录：母方案 §3.3 把 invalid_reason 定义在各消息体内（LANE/DEPTH/TRACK_V1）。本协议统一提到公共头，理由见 docs/interface_contract.md §2.3：Dashboard 需要一条与消息类型无关的渲染路径输出 `unavailable (REASON)`，否则每种消息都要单独写一遍。各消息体内不再重复该字段。 |
| 29 | `fragment_index` | `uint8` | 1 |  | 从 0 起 |
| 30 | `fragment_count` | `uint8` | 1 |  | 1=未分片；>1 时接收端重组超时即 DROP |
| 31 | `clock_domain_id` | `uint8` | 1 |  | 0=50K,1=100Pro+,2=RK3568,3=PC；跨域差值不得直接相减出延迟 |
| 32 | `header_reserved` | `uint8[4]` | 4 |  | 必须写 0，接收端忽略 |
| 36 | `crc32` | `uint32` | 4 |  | zlib.crc32（多项式 0xEDB88320），覆盖 header[0:36] ++ payload |

## 2. 消息体

### 0x01 CTRL

PC -> RK3568 控制命令（调试用，不参与测量）

定长部分合计 5 字节

| 字段 | 类型 | 字节 | 枚举 | 单位/定点/说明 |
|---|---|---:|---|---|
| `target_mode_id` | `uint8` | 1 |  | 0=camera 1=fusion 2=enhance |
| `gamma_en` | `uint8` | 1 |  | 0/1 |
| `enhance_mode` | `uint8` | 1 |  | 0=off 1=CLAHE 2=gamma |
| `debug_overlay_en` | `uint8` | 1 |  | 0/1 |
| `tracking_en` | `uint8` | 1 |  | 0/1 |

### 0x02 HEALTH

各板 1 Hz 心跳，携带链路错误累计值；Dashboard 健康灯、CRC/SEQ 计数只能来自本消息

定长部分合计 38 字节

| 字段 | 类型 | 字节 | 枚举 | 单位/定点/说明 |
|---|---|---:|---|---|
| `board_id` | `uint8` | 1 |  | 同 source_id |
| `module_id` | `uint8` | 1 |  | 0=video 1=ai 2=track 3=lane 4=fusion 5=link |
| `module_state` | `uint8` | 1 | OK=0 / DEGRADED=1 / FAULT=2 / OFFLINE=3 |  |
| `heartbeat` | `uint32` | 4 |  | count；该板心跳计数 |
| `crc_err` | `uint32` | 4 |  | count |
| `seq_gap` | `uint32` | 4 |  | count |
| `drop` | `uint32` | 4 |  | count；掉帧数 |
| `resync` | `uint32` | 4 |  | count |
| `tear` | `uint32` | 4 |  | count；撕裂帧数 |
| `thermal_cnt` | `uint32` | 4 |  | count；降频次数 |
| `fault_code` | `uint16` | 2 |  | 0=无故障 |
| `recovery_state` | `uint8` | 1 |  | RECOVERING 阶段序号，0=非恢复中 |
| `rate_kbps` | `uint16` | 2 |  | kbps；链路速率实测 |
| `temp_c_x10` | `int16` | 2 |  | 0.1degC；板温，1 Hz 采样 |

### 0x03 TIMING

分级耗时。duration_us 为本次单帧实测，p50/p95/max 为该 stage 的滑动窗口统计（窗口长度见 window_frames）。发送端可以不做统计而填 0 —— Dashboard 按 §9.4 自己算，不依赖这两个字段。

定长部分合计 19 字节

| 字段 | 类型 | 字节 | 枚举 | 单位/定点/说明 |
|---|---|---:|---|---|
| `stage_id` | `uint8` | 1 | CAPTURE=0 / PARSE=1 / DETECT=2 / TRACK=3 / LANE=4 / FUSE=5 / E2E=6 |  |
| `duration_us` | `uint32` | 4 |  | us |
| `p50_us` | `uint32` | 4 |  | us |
| `p95_us` | `uint32` | 4 |  | us |
| `max_us` | `uint32` | 4 |  | us |
| `window_frames` | `uint16` | 2 |  | frame；统计窗口实际帧数，未填满时小于窗口容量 |

### 0x10 LANE

50K 输出车道线。u = a*v^2 + b*v + c（v 为图像行坐标，u 为列坐标，均在 src_w x src_h 工作分辨率下）。定点偏离记录见 docs/interface_contract.md §2.4。本项目车道模型只回归**自车道中心线**，故新增 center_* 一组（偏离 D5）；left/right 保留给将来 50K 真正输出左右线的场合，无输出时 left_valid=right_valid=0。

定长部分合计 64 字节

| 字段 | 类型 | 字节 | 枚举 | 单位/定点/说明 |
|---|---|---:|---|---|
| `src_w` | `uint16` | 2 |  | px |
| `src_h` | `uint16` | 2 |  | px |
| `left_valid` | `uint8` | 1 |  |  |
| `right_valid` | `uint8` | 1 |  |  |
| `center_valid` | `uint8` | 1 |  |  |
| `lane_valid` | `uint8` | 1 |  |  |
| `left_a` | `int32` | 4 |  | px^-1；Q1.30 |
| `left_b` | `int32` | 4 |  | 1；Q16.16 |
| `left_c` | `int32` | 4 |  | px；Q16.16 |
| `right_a` | `int32` | 4 |  | px^-1；Q1.30 |
| `right_b` | `int32` | 4 |  | 1；Q16.16 |
| `right_c` | `int32` | 4 |  | px；Q16.16 |
| `center_a` | `int32` | 4 |  | px^-1；Q1.30 |
| `center_b` | `int32` | 4 |  | 1；Q16.16 |
| `center_c` | `int32` | 4 |  | px；Q16.16 |
| `center_offset_px` | `int32` | 4 |  | px；Q16.16；自车中心相对车道中心的横向偏移，右正 |
| `y_ref` | `uint16` | 2 |  | px；offset 的参考行 |
| `y_fit_min` | `uint16` | 2 |  | px；二次拟合采样带的近端（最小 v）。v < y_fit_min 处 abc 是**外推**，消费端不得据此画线 |
| `y_fit_max` | `uint16` | 2 |  | px；拟合采样带的远端（最大 v）。与 y_fit_min 一起构成 abc 的唯一有效域 [y_fit_min, y_fit_max] |
| `lane_width_px` | `int32` | 4 |  | px；Q16.16；y_ref 处左右线间距；仅 left_valid=right_valid=1 时有意义 |
| `curvature_px_inv` | `int32` | 4 |  | 1/px；Q1.30；取值为 center_a（即 x(y)=a y^2+b y+c 的 a），与 tools/lane_predict.py 冻结口径一致；不是 κ 的严格公式 |
| `confidence_score` | `uint16` | 2 |  | 1；Q0.16 |

### 0x11 MOTION

100Pro+ 光流。grid 为 80x60、每 cell 4x4 像素块的块匹配结果，ego_* 为自运动补偿参数

定长部分合计 49 字节

| 字段 | 类型 | 字节 | 枚举 | 单位/定点/说明 |
|---|---|---:|---|---|
| `ref_frame_id` | `uint32` | 4 |  | 参与光流的参考帧号 |
| `grid_w` | `uint8` | 1 |  |  |
| `grid_h` | `uint8` | 1 |  |  |
| `cell_size` | `uint8` | 1 |  | px |
| `flow_unit` | `uint8` | 1 | PIXEL_PER_FRAME_Q8_8=0 |  |
| `valid_ratio` | `uint16` | 2 |  | 1；Q0.16 |
| `ego_tx` | `int16` | 2 |  | px；Q8.8 |
| `ego_ty` | `int16` | 2 |  | px；Q8.8 |
| `ego_scale` | `int16` | 2 |  | 1；Q10.6 |
| `ego_residual` | `int16` | 2 |  | px；Q10.6 |
| `ego_valid` | `uint8` | 1 |  |  |
| `roi_motion_ratio` | `uint16` | 2 |  | 1；Q0.16 |
| `near_motion_ratio` | `uint16` | 2 |  | 1；Q0.16 |
| `far_motion_ratio` | `uint16` | 2 |  | 1；Q0.16 |
| `low_texture_ratio` | `uint16` | 2 |  | 1；Q0.16；LOW_TEXTURE 场景标签判据 |
| `conf_score` | `uint16` | 2 |  | 1；Q0.16 |
| `duration_us` | `uint32[5]` | 20 |  | us；[预处理,块匹配,自运动拟合,统计,总] |

### 0x12 FEATURE

100Pro+ 可选特征点（调试用，Dashboard 默认不渲染）

定长部分合计 6 字节（含变长字段）

| 字段 | 类型 | 字节 | 枚举 | 单位/定点/说明 |
|---|---|---:|---|---|
| `feature_count` | `uint8` | 1 |  |  |
| `features` | `record[]` | 5 |  |  |
| ↳ `features[]` | 记录 3 字段 | — | — | 每元素： |
| `features.x` | `uint16` | 2 |  | px |
| `features.y` | `uint16` | 2 |  | px |
| `features.score` | `uint8` | 1 |  | 1；Q0.8 |

### 0x13 DEPTH

100Pro+ 深度/视差。depth_status != OK 时不允许给出任何米制距离；valid 区间 200~1000 cm（方案 §6.4）

定长部分合计 14 字节（含变长字段）

| 字段 | 类型 | 字节 | 枚举 | 单位/定点/说明 |
|---|---|---:|---|---|
| `depth_status` | `uint8` | 1 | OK=0 / UNSUPPORTED=1 / LOW_CONFIDENCE=2 |  |
| `valid_ratio` | `uint16` | 2 |  | 1；Q0.16 |
| `confidence` | `uint16` | 2 |  | 1；Q0.16 |
| `depth_min_cm` | `uint16` | 2 |  | cm |
| `depth_max_cm` | `uint16` | 2 |  | cm |
| `block_w` | `uint8` | 1 |  |  |
| `block_h` | `uint8` | 1 |  |  |
| `block_size` | `uint8` | 1 |  | px |
| `block_count` | `uint16` | 2 |  |  |
| `disparity` | `int16[]` | 变长 |  | px；Q10.6；按行主序排列的 block_w*block_h 个视差 |

### 0x14 LANE_TRACK

RK 侧 lane 时间滤波结果（子方案 §7，RKD-24）。Dashboard 只显示、不计算：滤波是 RK 的职责，界面拿到什么画什么。TRACKING 才有 filtered；HOLD 是预测值（valid 语义由 header status 承担）；LOST 时应看 invalid_reason。

定长部分合计 38 字节

| 字段 | 类型 | 字节 | 枚举 | 单位/定点/说明 |
|---|---|---:|---|---|
| `src_frame_id` | `uint32` | 4 |  | 对应的 LANE 帧号，便于反查原始量 |
| `raw_offset_px` | `int32` | 4 |  | px；Q16.16；本帧原始测量，原样转贴，供界面并排对比 |
| `filtered_offset_px` | `int32` | 4 |  | px；Q16.16；alpha-beta 输出 |
| `ema_offset_px` | `int32` | 4 |  | px；Q16.16；EMA 基线（§7.1 要求保留），不做结论用 |
| `curvature_filtered` | `int32` | 4 |  | 1/px；Q1.30 |
| `lane_state` | `uint8` | 1 | TRACKING=0 / HOLD=1 / LOST=2 |  |
| `hold_frames` | `uint8` | 1 |  | 帧 |
| `dt_us` | `uint32` | 4 |  | us；本帧实测到达间隔，禁止假设 33.3 ms |
| `alpha` | `uint16` | 2 |  | Q0.16 |
| `beta` | `uint16` | 2 |  | Q0.16 |
| `seq_gap_cnt` | `uint32` | 4 |  |  |
| `reset_cnt` | `uint32` | 4 |  |  |

### 0x20 OBJECT

RK3568 YOLO 检测结果（每帧全量，不含跟踪身份）。bbox 为工作分辨率整数像素

定长部分合计 17 字节（含变长字段）

| 字段 | 类型 | 字节 | 枚举 | 单位/定点/说明 |
|---|---|---:|---|---|
| `object_count` | `uint8` | 1 |  |  |
| `objects` | `record[]` | 16 |  |  |
| ↳ `objects[]` | 记录 6 字段 | — | — | 每元素： |
| `objects.class_id` | `uint8` | 1 |  |  |
| `objects.score` | `uint16` | 2 |  | 1；Q0.16 |
| `objects.bbox_xyxy` | `int16[4]` | 8 |  | px |
| `objects.distance_status` | `uint8` | 1 | VALID=0 / NO_DEPTH=1 / OUT_OF_VALID_RANGE=2 |  |
| `objects.distance_min_cm` | `uint16` | 2 |  | cm |
| `objects.distance_max_cm` | `uint16` | 2 |  | cm |

### 0x21 TRACK_V1

RK3568 ByteTrack 跟踪结果。tracker_epoch 在每次跟踪器复位时 +1，Dashboard 必须用它判定 ID 是否可跨帧比较

定长部分合计 43 字节（含变长字段）

| 字段 | 类型 | 字节 | 枚举 | 单位/定点/说明 |
|---|---|---:|---|---|
| `tracker_epoch` | `uint32` | 4 |  |  |
| `tracking_enabled` | `uint8` | 1 |  |  |
| `track_valid` | `uint8` | 1 |  |  |
| `track_count` | `uint16` | 2 |  |  |
| `tracks` | `record[]` | 35 |  |  |
| ↳ `tracks[]` | 记录 13 字段 | — | — | 每元素： |
| `tracks.track_id` | `uint64` | 8 |  |  |
| `tracks.class_id` | `uint8` | 1 |  |  |
| `tracks.state` | `uint8` | 1 | TENTATIVE=0 / CONFIRMED=1 / LOST=2 |  |
| `tracks.observation` | `uint8` | 1 |  | 0=detected 1=predicted |
| `tracks.score` | `uint16` | 2 |  | 1；Q0.16 |
| `tracks.bbox_xyxy` | `int16[4]` | 8 |  | px |
| `tracks.last_detect_frame_id` | `uint32` | 4 |  |  |
| `tracks.age_frames` | `uint16` | 2 |  |  |
| `tracks.missing_frames` | `uint16` | 2 |  |  |
| `tracks.roi_relation` | `uint8` | 1 | NONE=0 / EGO_LANE=1 / LEFT_LANE=2 / RIGHT_LANE=3 / UNKNOWN=255 | UNKNOWN=255 表示产生端没有车道带几何、无法判定，Dashboard 必须显示 unavailable 而不是当成 0 |
| `tracks.distance_status` | `uint8` | 1 | VALID=0 / NO_DEPTH=1 / OUT_OF_VALID_RANGE=2 |  |
| `tracks.distance_min_cm` | `uint16` | 2 |  | cm |
| `tracks.distance_max_cm` | `uint16` | 2 |  | cm |

### 0x30 ROADSTREAM

50K -> RK3568 低分辨率灰度图，320x240 MONO8。满帧 76800 字节超过 payload_length(uint16) 上限，必须按 fragment_count>=2 分片（重组层属 RKD-12，本阶段只冻结字段）

定长部分合计 5 字节（含变长字段）

| 字段 | 类型 | 字节 | 枚举 | 单位/定点/说明 |
|---|---|---:|---|---|
| `width` | `uint16` | 2 |  | px |
| `height` | `uint16` | 2 |  | px |
| `pixel_format` | `uint8` | 1 | MONO8=0 / RGB565=1 / BGR888=2 / NV12=3 / JPEG=4 |  |
| `pixels` | `bytes[]` | 变长 |  |  |

### 0x31 ROADTHUMB

RK3568 -> PC 缩略图，单包发送。pixels 是**编码后**的图像字节（本阶段固定 pixel_format=JPEG），width/height 是编码前的源分辨率，供 Dashboard 反算 display 坐标。偏离 D6：母方案写的是 640x384 RGB565 裸像素，那是 491,520 B，远超 payload_length(uint16) 上限 65,535，单包根本装不下；改为 JPEG 后实测 640x360 q65 约 25~35 KB。

定长部分合计 25 字节（含变长字段）

| 字段 | 类型 | 字节 | 枚举 | 单位/定点/说明 |
|---|---|---:|---|---|
| `src_frame_id` | `uint32` | 4 |  |  |
| `width` | `uint16` | 2 |  | px |
| `height` | `uint16` | 2 |  | px |
| `pixel_format` | `uint8` | 1 | MONO8=0 / RGB565=1 / BGR888=2 / NV12=3 / JPEG=4 |  |
| `scale_x` | `uint32` | 4 |  | Q16.16 |
| `scale_y` | `uint32` | 4 |  | Q16.16 |
| `pad_x` | `int16` | 2 |  | px |
| `pad_y` | `int16` | 2 |  | px |
| `mean` | `uint16` | 2 |  | 1；Q8.8 |
| `std` | `uint16` | 2 |  | 1；Q8.8 |
| `pixels` | `bytes[]` | 变长 |  |  |

### 0x32 UDP_VIDEO

分片视频流，重组后按 pixel_format 解码；依赖公共头的 fragment_index/count 与 payload_length

定长部分合计 6 字节（含变长字段）

| 字段 | 类型 | 字节 | 枚举 | 单位/定点/说明 |
|---|---|---:|---|---|
| `channel_id` | `uint8` | 1 |  |  |
| `width` | `uint16` | 2 |  | px |
| `height` | `uint16` | 2 |  | px |
| `pixel_format` | `uint8` | 1 | MONO8=0 / RGB565=1 / BGR888=2 / NV12=3 / JPEG=4 |  |
| `data` | `bytes[]` | 变长 |  |  |

## 3. 定点格式

| 格式 | 1 LSB | 说明 |
|---|---:|---|
| `Q0.16` | 1.525878906e-05 | 0..1 概率类 |
| `Q1.30` | 9.313225746e-10 | 极小量（曲率、二次项） |
| `Q2.14` | 6.103515625e-05 |  |
| `Q4.12` | 0.000244140625 |  |
| `Q8.8` | 0.00390625 |  |
| `Q10.6` | 0.015625 |  |
| `Q16.16` | 1.525878906e-05 | 像素/系数通用 |

## 4. 枚举

### `message_type`

| 名称 | 值 |
|---|---:|
| `CTRL` | 1 |
| `HEALTH` | 2 |
| `TIMING` | 3 |
| `LANE` | 16 |
| `MOTION` | 17 |
| `FEATURE` | 18 |
| `DEPTH` | 19 |
| `LANE_TRACK` | 20 |
| `OBJECT` | 32 |
| `TRACK_V1` | 33 |
| `ROADSTREAM` | 48 |
| `ROADTHUMB` | 49 |
| `UDP_VIDEO` | 50 |

### `lane_state`

| 名称 | 值 |
|---|---:|
| `TRACKING` | 0 |
| `HOLD` | 1 |
| `LOST` | 2 |

### `source_id`

| 名称 | 值 |
|---|---:|
| `PANGU50K` | 0 |
| `P100PRO_PLUS` | 1 |
| `RK3568` | 2 |
| `PC` | 3 |
| `UNKNOWN` | 255 |

### `status`

| 名称 | 值 |
|---|---:|
| `OK` | 0 |
| `INVALID` | 1 |
| `DEGRADED` | 2 |
| `UNSUPPORTED` | 3 |
| `STALE` | 4 |

### `invalid_reason`

| 名称 | 值 |
|---|---:|
| `NONE` | 0 |
| `NO_INPUT` | 1 |
| `NO_REF` | 2 |
| `FRAME_MISS` | 3 |
| `DEPTH_GATE` | 4 |
| `LOW_CONFIDENCE` | 5 |
| `OUT_OF_VALID_RANGE` | 6 |
| `TRACK_DISABLED` | 7 |
| `TRACK_STALE` | 8 |
| `TRACK_ERROR` | 9 |
| `INPUT_INVALID` | 10 |
| `NO_DEPTH` | 11 |
| `NO_TRACK` | 12 |
| `AGE_TIMEOUT` | 13 |
| `SEQ_GAP` | 14 |
| `DT_OUT_OF_RANGE` | 15 |
| `CAMERA_LOST` | 16 |
| `LINK_DOWN` | 17 |
| `HEARTBEAT_TIMEOUT` | 18 |
| `CALIB_MISMATCH` | 19 |
| `VERSION_UNSUPPORTED` | 20 |
| `CRC_ERROR` | 21 |
| `REPLAY_EOF` | 22 |
| `NOT_PROVIDED` | 23 |
| `LANE_LOST` | 24 |
| `ROI_EMPTY` | 25 |
| `NO_HEADING_SOURCE` | 26 |
| `THERMAL_THROTTLE` | 27 |
| `DEGRADED_NO_FLOW` | 28 |

### `depth_status`

| 名称 | 值 |
|---|---:|
| `OK` | 0 |
| `UNSUPPORTED` | 1 |
| `LOW_CONFIDENCE` | 2 |

### `distance_status`

| 名称 | 值 |
|---|---:|
| `VALID` | 0 |
| `NO_DEPTH` | 1 |
| `OUT_OF_VALID_RANGE` | 2 |

### `roi_relation`

| 名称 | 值 |
|---|---:|
| `NONE` | 0 |
| `EGO_LANE` | 1 |
| `LEFT_LANE` | 2 |
| `RIGHT_LANE` | 3 |
| `UNKNOWN` | 255 |

### `track_state`

| 名称 | 值 |
|---|---:|
| `TENTATIVE` | 0 |
| `CONFIRMED` | 1 |
| `LOST` | 2 |

### `timing_stage`

| 名称 | 值 |
|---|---:|
| `CAPTURE` | 0 |
| `PARSE` | 1 |
| `DETECT` | 2 |
| `TRACK` | 3 |
| `LANE` | 4 |
| `FUSE` | 5 |
| `E2E` | 6 |

### `object_class`

| 名称 | 值 |
|---|---:|
| `CAR` | 0 |
| `PERSON` | 1 |
| `TRAFFIC_LIGHT` | 2 |
| `TRAFFIC_SIGN` | 3 |
| `TRUCK` | 4 |
| `BUS` | 5 |
| `MOTORCYCLE` | 6 |
| `BICYCLE` | 7 |
| `OTHER` | 8 |

### `module_state`

| 名称 | 值 |
|---|---:|
| `OK` | 0 |
| `DEGRADED` | 1 |
| `FAULT` | 2 |
| `OFFLINE` | 3 |

### `flow_unit`

| 名称 | 值 |
|---|---:|
| `PIXEL_PER_FRAME_Q8_8` | 0 |

### `pixel_format`

| 名称 | 值 |
|---|---:|
| `MONO8` | 0 |
| `RGB565` | 1 |
| `BGR888` | 2 |
| `NV12` | 3 |
| `JPEG` | 4 |
