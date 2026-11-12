# rk_deploy —— 板端 YOLO ↔ AVM3D 接口

方向固定为：**板端 YOLO 检测 → PC AVM3D 渲染**。板端不把原始视频推给 PC 做推理，
PC 也不通过 SSH 拉结果；两者只交换冻结的 40 B 协议报文。

```text
板端 front 相机（或 2x2 atlas 的 front 格）
        │  RKNN / PC ONNX 替身
        ▼
FrameDetections（bbox 在 front 标定坐标，SIM=640x360）
        │  OBJECT(0x20) / TRACK_V1(0x21)
        ▼
UDP 7000 ──► AVM3D BoardSource ──► AvmProtocolStore
                                      │
                                      ▼
                          同 frame_id 匹配 → 3D 窗口 HUD / 前视 inset 画框
```

## 1. 必须遵守的契约

| 项 | 约定 |
|---|---|
| `frame_id` | 必须与 AVM3D 当前视频帧一致；板端不得另起一套帧号 |
| `bbox_xyxy` | **AVM3D 标定里 front 相机的图像坐标**。SIM 标定是 640x360；不是 atlas 的 1280x720，也不是 YOLO 网络输入 640x640 |
| `score` | Q0.16，0..65535；编码前裁到 0..1 |
| `class_id` | 0..255，与 `traffic9_postprocess.CLASSES` 一致 |
| `source_id` | `RK3568`（板端/PC 替身都用它，明确是“板端来源模拟”） |
| `clock_domain_id` | 2（RK3568）；`timestamp_ns` 是发送端单调时钟，不跨域相减 |
| `calibration_id` | 与 AVM3D 加载的标定一致（SIM=7301），便于排查错配 |
| 距离字段 | 无深度时 `distance_status=NO_DEPTH, min=max=0`，不伪造米制 |
| 坐标缩放 | 板端负责把检测框缩放到 front 标定坐标；AVM3D 不再做二次缩放 |

`OBJECT` 没有 `camera_id`（G0-02 未冻结）。因此 AVM3D 只在**前视 inset 画 2D 框**，
不会把框投到 3D 碗面；面板上明确标注 `G0-02：OBJECT 无相机通道映射，只画 2D 框`。
要把框贴到 3D 地面，必须先给 `OBJECT` 增加相机通道映射，不能用配置文件猜。

## 2. 文件

| 文件 | 作用 |
|---|---|
| `dashboard/vision/contract.py` | Detection/FrameDetections/Track + Q0.16/int16 + OBJECT/TRACK_V1 编解码 |
| `dashboard/vision/transport.py` | UDP 发送/接收；接收复用 40 B 协议 Receiver |
| `dashboard/vision/backends.py` | `FakeBackend` / `OnnxBackend` / `RknnBackend`，同一 `infer()` 接口 |
| `rk_deploy/app/yolo_sender.py` | 板端/PC 替身发送器：读 atlas front 格 → 检测 → UDP |
| `rk_deploy/app/board_yolo_udp.py` | RK3568 无窗口实板发送器；fast 后处理 + 可选 START 握手 |
| `rk_deploy/app/pc_launcher.py` | 一键启动器：选视频、上传/缓存、板端推理、PC 窗口 |
| `rk_deploy/app/receive_detections.py` | 不开 AVM3D 时的 UDP 调试接收器 |
| `dashboard/avm3d/data/board/board_config.yolo.example.json` | AVM3D `BoardSource` + `metadata.udp_port=7000` 示例 |

PC ONNX 后端复用 `tools/adas_dash.py::AdasPipeline.detect()`，没有第二份推理实现；
板端 RKNN 的 fast 路径仍复用 `traffic9_postprocess.py` 的输出顺序、`scale_boxes` 和
NMS 口径，只把 DFL 改成“先筛候选锚点再 softmax”。`--verify-post N` 会与参考实现
逐框比对，前处理/后处理仍必须与 PC 对拍。

## 3. 跑起来（PC 替身，无需板卡）

```powershell
$py = "D:\ziguang\.venv_gpu\Scripts\python.exe"

# 终端 1：AVM3D 开 BOARD 源，metadata 监听 7000
& $py -X utf8 dashboard\avm3d\app.py --source board `
    --board-config dashboard\avm3d\data\board\board_config.yolo.example.json `
    --view 2 --wait-ms 1000 --frames 1 --shots 1 `
    --out-dir reports\yolo3d_interface

# 终端 2：fake 替身（确定性框，证明链路；没有模型也能跑）
& $py -X utf8 rk_deploy\app\yolo_sender.py --backend fake `
    --video dashboard\avm3d\data\replay\avm_sim_4up.mp4 --layout atlas `
    --calib dashboard\avm3d\calib\sim_calibration.json `
    --host 127.0.0.1 --port 7000 --fps 20 --frames 1

# 真实 PC ONNX 替身（前视 640x360 输入）
& $py -X utf8 rk_deploy\app\yolo_sender.py --backend onnx `
    --onnx traffic_yolo_deploy\deploy_rk3568\models\traffic9_split6_640.onnx `
    --video <front_640x360.mp4 或 atlas 视频> --layout atlas `
    --calib dashboard\avm3d\calib\sim_calibration.json `
    --host 127.0.0.1 --port 7000 --fps 20 --frames 1 --conf 0.25
```

AVM3D 的 `verified=false` 时横幅保持 `BOARD BLOCKED`，这是故意的：接口通了不等于
真实板端 LIVE。只有板端真链路、真实标定、AVM1/帧表、source_map 都核验后才改 `verified`。

## 4. 板端 RKNN

```bash
python3 rk_deploy/app/yolo_sender.py --backend rknn \
  --model rk_deploy/model/traffic9_split6_640.rknn \
  --video /dev/video0 --layout single \
  --host <PC_IP> --port 7000 --fps 20
```

上板前必须确认：

1. 模型是 split6 六输出，输出顺序与 `traffic9_postprocess.py` 一致；
2. `rknnlite` 版本、`init_runtime` 的 core mask；
3. `to_uint8_nhwc_bgr` 的 BGR 通道约定（当前 RKNN 转换配置是 BGR→RGB + mean/std）；
4. 同一帧在 PC ONNX 与 RKNN 上逐框对拍（IoU/分数/类别），不能只看 mAP；
5. 前端取帧分辨率是 640x360，或发送前缩放到 front 标定坐标。

板端包需要带：`dashboard/protocol/schema.py`、`dashboard/vision/`、
`traffic9_postprocess.py`。缺任一文件时 `RknnBackend` 会报明确错误码，不会静默换后端。

## 5. 测试

```powershell
& $py -X utf8 rk_deploy\tests\run_all.py
```

覆盖：契约往返/量化钳位、OBJECT/TRACK_V1 进 AVM3D `AvmProtocolStore`、
坏 CRC 丢弃、Fake 确定性、PC 上 RKNN 必须明确不可用、ONNX 坐标 640x360。
Linux/WSL 只跑契约：

```bash
wsl -e bash -lc 'cd /mnt/d/ziguang && python3 -X utf8 rk_deploy/tests/test_contract.py'
```

## 6. 当前状态

- 已打通：PC 替身与 RK3568 实板 → UDP 7000 → AVM3D 同帧匹配 → 单路窗口画框；
  板端 15 fps 目标下整片 1852 帧 1852/1852 `MATCHED`，PC 车道/弯向本地计算。
- 未做：RKNN 模型版本统一（toolkit 2.3.2 vs runtime 1.6.0）；PC ONNX 与 RKNN
  同批帧逐框对拍；板端 ByteTrack（TRACK_V1）；3D 碗面目标定位（G0-02）；
  真实 AVM 标定与 LIVE 门禁。以上都不能用“画面有框”代替验收。
- 四路 3D 阶段 A：四个本地源文件现场拼 1280×720；前/后都上传板端，仅前向 YOLO；
  前向 inset 车道；nuScenes 30 帧 30/30 MATCHED。
- 长稳：完整素材 1852 帧 / 123.6 s 已跑完；更长的 30 min 级 soak 仍待做。

证据截图：

- `reports/yolo3d_interface/avm3d_fake_matched.png`
- `reports/yolo3d_interface/avm3d_onnx_real_matched.png`

## 7. nuScenes 四路同步演示

用 `reports/nuscenes_scene0061/atlas_4up.mp4`（scene-0061，229 帧，12 fps）跑完整链路。
这里用视觉标定 9103（SYNTH FILL，非严格几何/非验收）；严格模式改用
`calibration_nuscenes_bev.json`（id 9102）并同步改 board config 的 `calibration_id`。

```powershell
$py = "D:\ziguang\.venv_gpu\Scripts\python.exe"
$calib = "reports\nuscenes_scene0061\bev\calibration_nuscenes_bev_visual.json"

# 终端 1：sender 先起，领先视频约 1 s
& $py -X utf8 rk_deploy\app\yolo_sender.py --backend onnx `
    --onnx traffic_yolo_deploy\deploy_rk3568\models\traffic9_split6_640.onnx `
    --video reports\nuscenes_scene0061\atlas_4up.mp4 --layout atlas `
    --calib $calib --host 127.0.0.1 --port 7000 --fps 12 --frames 60 --conf 0.25

# 终端 2：等约 0.8 s 再开 AVM3D
& $py -X utf8 dashboard\avm3d\app.py --source board `
    --board-config dashboard\avm3d\data\board\board_config.nuscenes.example.json `
    --calib $calib --view 2 --wait-ms 100 --frames 60 --shots 5
```

顺序很重要：**sender 先、AVM3D 后**。AVM3D 先起会让它等“未来”的元数据，
表现为 `NO_BUNDLE`；sender 领先约 1 s 时，元数据已在 store 里，UI 按当前
`frame_id` 直接命中。文件源不是实时链路，这种手工领先只用于演示；真板端应
用 AVM1 帧表/同一触发源保证同帧。

本次实测：55 帧渲染，48 帧 `MATCHED`；演示视频与截图：

- `reports/yolo3d_nuscenes/flow_nuscenes_yolo_to_3d.mp4`（12 fps，56 帧画布）
- `reports/yolo3d_nuscenes/nuscenes_matched_f019.png`
- `reports/yolo3d_nuscenes/nuscenes_matched_f048.png`

## 8. 单路模式与手动选通道

AVM3D 新增两个启动参数：

```powershell
# 只展示选中的一路（单路模式）
& $py -X utf8 dashboard\avm3d\app.py --source board `
    --board-config dashboard\avm3d\data\board\board_config.nuscenes.example.json `
    --calib reports\nuscenes_scene0061\bev\calibration_nuscenes_bev_visual.json `
    --view 2 --layout single --detect-camera front --wait-ms 1000 --frames 1 --shots 1

# 四路 3D 碗面，但检测/查看都选 right
& $py -X utf8 dashboard\avm3d\app.py --source board `
    --board-config dashboard\avm3d\data\board\board_config.nuscenes.example.json `
    --calib reports\nuscenes_scene0061\bev\calibration_nuscenes_bev_visual.json `
    --view 2 --layout 3d --detect-camera right --wait-ms 1000 --frames 1 --shots 1
```

对应 sender 必须用同一个通道：

```powershell
& $py -X utf8 rk_deploy\app\yolo_sender.py --backend onnx `
    --onnx traffic_yolo_deploy\deploy_rk3568\models\traffic9_split6_640.onnx `
    --video reports\nuscenes_scene0061\atlas_4up.mp4 --layout atlas `
    --calib reports\nuscenes_scene0061\bev\calibration_nuscenes_bev_visual.json `
    --cell front --host 127.0.0.1 --port 7000 --fps 12 --frames 1 --conf 0.25
# 3D RIGHT 示例把 --cell front 改成 --cell right
```

单帧演示可以先起 AVM3D（`--wait-ms 1000` 会等元数据），0.3 s 后再起 sender；
连续演示按第 7 节 **sender 先起、AVM3D 后起**，避免 AVM3D 等“未来”元数据。

规则：

- `--detect-camera` 是 **sender 实际推理的通道**，必须与 `yolo_sender --cell` 一致；
  因为 `OBJECT` 没有 `camera_id`（G0-02），AVM3D 无法从报文反推 sender 用的哪一路。
- `--layout 3d`：四路碗面 + 选中通道的前视 inset 框；
  `--layout single`：视图区只显示选中通道的大画面 + 框，不渲染碗面。
- 窗口按钮 `查看: FRONT/RIGHT/...` 或 `c` 只切换**查看通道**；当查看通道 ≠ 检测通道时，
  框会隐藏并显示 `检测 X ≠ 查看 Y · 框已隐藏`，不会把一通道的框画到另一通道。
- `模式: 3D/单路` 按钮或 `v` 切换布局；`m` 只在 3D 模式切换严格/视觉标定。
- 改检测通道要**同时**重启 sender（`--cell`）和 AVM3D（`--detect-camera`），不是只点按钮。
## 9. 单视频文件（不是四路 atlas）

单个行车视频也能直接进单路模式，配置 `video.layout=single`：

- 视频内部缩放到 front 标定 `640x360`；
- 只存在 front 一路，`source_map` 的 right/rear/left 写 `absent`；
- AVM3D 检测到 `single_video` 会**自动锁到 single 布局**，查看通道固定 FRONT；
- sender 用 `--layout single` 时也会把输入缩放到 front 640x360，框坐标一致；
- 这种源没有四路几何，`--layout 3d` 会被强制改为 single，不能拿它做 AVM 几何验收。

**路线/弯向在 PC 侧**：单路模式默认加载 `tools/_lane_runs/v9/lanenet.onnx`，
板端仍然只发 `OBJECT`，不发车道消息。PC 在单路画面上画本车道中心线：
实线是模型近场 7 点，虚线是按拟合曲线的远端外推；右下角显示
`道路弯向: 直行/左弯/右弯/不确定` 与 `a*w`。`--no-lane` 可关闭，
`--lane-onnx` 可换模型。

⚠ `道路弯向` 是**图像估计**，不是驾驶员转向/控制指令；没有轮速/IMU，
项目文档 §6.3 的 L4 转向判定仍然 unavailable。窗口里明确写
`PC 图像估计 · 非驾驶转向/无轮速IMU`。

示例配置：`dashboard/avm3d/data/board/board_config.single.example.json`。

```powershell
# sender 先起（以 data\drive_720p.mp4 为例；换成你的 MOV 即可）
& $py -X utf8 rk_deploy\app\yolo_sender.py --backend onnx `
    --onnx traffic_yolo_deploy\deploy_rk3568\models\traffic9_split6_640.onnx `
    --video data\drive_720p.mp4 --layout single --cell front `
    --calib dashboard\avm3d\calib\sim_calibration.json `
    --host 127.0.0.1 --port 7000 --fps 30 --frames 240 --conf 0.25

# AVM3D 单路窗口
& $py -X utf8 dashboard\avm3d\app.py --source board `
    --board-config dashboard\avm3d\data\board\board_config.single.example.json `
    --calib dashboard\avm3d\calib\sim_calibration.json `
    --layout single --frames 240 --wait-ms 100 --shots 240
```

已跑过的 MOV：`video_20260929_113539.mov`（854x480、24 fps、1852 帧）。
先跑前 240 帧（纯 YOLO）：225 帧渲染 / 219 帧 `MATCHED`（约 97%）；再加 PC 车道
跑前 120 帧：82 帧渲染 / 70 帧 `MATCHED`，车道推理约 25 ms/帧，最后状态右弯、
置信度 0.85。演示：

- `reports/yolo3d_single_mov/flow_mov_single_yolo.mp4`（无车道）
- `reports/yolo3d_single_lane/flow_mov_single_lane_yolo.mp4`（YOLO + PC 车道/弯向）
- `reports/yolo3d_single_lane/matched_f116.png`
- `reports/yolo3d_single_lane/stats.json`
## 10. RK3568 实板部署（无窗口）

已在 `user@192.168.1.100`（Rockchip RK3568 EVB1，Linux 6.1.99，Python 3.10.12）
实跑通过。板端只跑 RKNN YOLO 并发 `OBJECT`，没有任何窗口；窗口和车道都在 PC。

板端环境：

- `rknn-toolkit-lite2 2.3.2`、`librknnrt 1.6.0`
- 模型：`/home/neardi/traffic9_rk3568_deploy/models/traffic9_split6_640_rk3568.rknn`
- 输入视频：启动器缓存到 `/home/neardi/avm_board/input_<文件名>_<大小>_<mtime>.mov`
  （本次为 854x480、24 fps、1852 帧；手动模式可用 `input.mov`）
- 输入统一缩放到 `640x360`，与 PC front 标定坐标一致

部署包：`reports/board_deploy/avm_board.tar.gz`，板端解压到 `~/avm_board`。
板端启动：

```bash
cd ~/avm_board
python3 board_yolo_udp.py --video input.mov \
  --host 10.16.16.4 --port 7000 \
  --fps 15 --frames 0 --control-port 7002 --post fast --print-every 10
```

`--frames 0` 表示全片；`--fps 0` 表示板端全速（实测约 16 fps，适合长视频离线
处理）。`--post fast` 是默认值；`--post ref` 可切回原后处理，`--verify-post 3`
会在前 3 帧同时跑两条路径并逐项比对，不一致直接退出码 5。

**启动握手**：板端加载模型后停在 `WAIT_START udp :7002`；PC 的 `BoardSource`
绑定 7000 后向板端发 `START`，板端才开始推 `OBJECT`。这样 PC 的 `frame_id`
和视频帧从 0 对齐，不靠 sleep 猜时序。配置里写：

```json
{
  "control": {"host": "192.168.1.100", "start_port": 7002},
  "video": {"sync_to_detections": true, "detect_wait_ms": 500}
}
```

`sync_to_detections` 让 PC 视频源在发布第 N 帧前先等 `frame_id=N` 的检测；
板端慢时 PC 自动跟着降速，不再出现“本地视频抢跑 → 队列丢帧 → 每帧空等 1 s”。
`detect_wait_ms` 是单帧等待上限；超时只记 `detect_wait_timeout` 并继续，
不会卡死整条链路。

四路 3D 配置额外写：

```json
{
  "video": {
    "layout": "atlas",
    "quad_paths": {
      "front": "D:/.../front.mp4",
      "right": "D:/.../right.mp4",
      "rear":  "D:/.../rear.mp4",
      "left":  "D:/.../left.mp4"
    },
    "start_delay_ms": 1000
  },
  "atlas": {"width": 1280, "height": 720,
            "cell_order": ["front", "right", "rear", "left"]}
}
```

`BoardSource` 会逐帧读取四个文件并现场拼 atlas；不写中间视频文件。
`start_delay_ms` 是 PC 发 `START` 后、开始读源文件前的等待；建议 ≤5000 ms，
配合 `--frame-cache 240` 使用。

PC 端仍用单路模式（`--layout single`），先启动板端到 `WAIT_START`，再启动 PC：

```powershell
& $py -X utf8 dashboard\avm3d\app.py --source board `
  --board-config reports\launcher\board_config.json `
  --calib dashboard\avm3d\calib\sim_calibration.json `
  --layout single --frames 0 --wait-ms 50 --frame-cache 120 `
  --headless --force-no-gl --shots 60
```

`reports/launcher/board_config.json` 由启动器生成，已带 `sync_to_detections=true`；
手动换视频时同步改它的 `video.path`。旧配置
`reports/yolo3d_single_lane/board_mov.json` 保留为 8 fps 历史证据，不建议再用。

实测（2026-10-30，优化后）：

- 板端 15 fps 目标：整片 **1852 帧 / 123.48 s = 15.00 fps**；RKNN 推理约 43–49 ms，
  预处理约 2 ms，后处理约 8–12 ms；
- 板端全速（`--fps 0`）：120 帧 / 7.43 s = **16.16 fps**；
- PC：**1852/1852 MATCHED**，0 丢帧、0 检测等待超时；渲染 p95 11.4 ms，
  车道推理约 21 ms/帧；PC 平均 14.87 fps（含 1 s 启动延时，板端 15.00 fps）；
- 板端只发 `OBJECT`，PC 车道/路线/弯向全部本地计算。

旧版 8 fps 的瓶颈不是网络，而是每帧对全部 6400 个锚点做 DFL softmax（约 43 ms）
加上二次 resize（约 21 ms）。现在只对过阈值锚点做 DFL，预处理一次 resize 到
640×360，板端才真正跑到 15–16 fps。

已知警告：RKNN 模型 toolkit 2.3.2 与 runtime 1.6.0 版本不一致，推理能跑；
上量产前应统一版本并做同一批帧的 PC ONNX vs RKNN 逐框对拍。

## 11. PC 一键启动器（选视频 -> 板端推理 -> 窗口）

双击仓库根目录的 `启动板端可视化.bat`，或运行：

```powershell
& "D:\ziguang\.venv_gpu\Scripts\python.exe" -X utf8 rk_deploy\app\pc_launcher.py
```

界面里：

1. `模式` 选 **单路** 或 **四路 3D**；
2. 单路：`选择...` 选一个视频；
   四路：分别选 `前向 / 右 / 后 / 左` 四个文件；
3. 板端默认 `user@192.168.1.100`，Key 默认 `~/.ssh/id_ed25519`；
4. FPS 默认 15，帧数默认 0（0=全片/四路取最短）；启动延时默认 1000 ms；
5. 点 **开始推理**。

启动器会自动：

- SSH 检查板端；缺协议/schema 时上传 `reports/board_deploy/avm_board.tar.gz`；
- 板端视频按 `文件名_大小_mtime` 缓存；同一文件第二次运行**跳过上传**；
  上传前检查板端剩余空间；
- 四路模式上传**前向 + 后向**，后向只存储、不推理；右/左只在本机拼接；
- 启动板端 `board_yolo_udp.py --post fast`（等 `WAIT_START`）；
- 生成 `reports/launcher/board_config.json`：
  - 单路：`layout=single`；
  - 四路：`layout=atlas` + `video.quad_paths`；
  - 两者都带 `sync_to_detections=true`、`detect_wait_ms=500`、
    `start_delay_ms`、`control.start_port=7002`；
- 打开 PC AVM3D 单路/四路 3D 窗口；PC 绑定 7000 后发 START，板端开始推 `OBJECT`；
- PC 端**等本帧检测到了才发布视频帧**，不会因为本地视频抢跑而每帧空等 1 s；
- 窗口关闭后自动 `pkill` 板端进程，并写 `reports/launcher/run_stats.json`。

> Windows GUI 下**不再使用 `ssh -f`**：启动器保持一条非阻塞 SSH 连接，以板端
> `run_board.log` 出现 `WAIT_START` 判定启动成功。之前 `ssh -f` 在无控制台的 GUI
> 进程里可能挂住 30 s，导致板端已启动却被启动器判失败并杀掉。

长视频/帧率建议：

| 场景 | FPS 设置 | 说明 |
|---|---|---|
| 常规可视化 | `15` | 板端 15.00 fps；PC 平均约 14.9（含 1 s 启动延时），0 丢帧 |
| 长视频尽快跑完 | `0` | 板端全速，实测 16.16 fps |
| 快速抽检前几百帧 | `15` + 帧数 `120` | 不跑全片 |

日志与统计：

- PC：`reports/launcher/avm.log`、`reports/launcher/run_stats.json`
- 板端：`/home/neardi/avm_board/run_board.log`

命令行走同一流程（无窗口，便于测试）：

```powershell
& $py -X utf8 rk_deploy\app\pc_launcher.py --auto `
  --video "D:\ziguang\交通场景数据集\video_20260929_113539.mov" `
  --fps 15 --frames 120 --headless
```

实测：15 fps、整片 1852 帧，PC 1852/1852 `MATCHED`，队列丢帧 0，检测等待超时 0。

## 12. 四路 3D（阶段 A：本地源文件现场拼接）

启动器“模式”选 **四路 3D** 后，分别选择 `前向 / 右 / 后 / 左` 四个源文件：

- **前向会上传 RK3568 并做 YOLO**；
- **后向也会上传 RK3568，但只存储、不推理**，为后续 50K 链路预留；
- 右/左只在本机参与四宫格拼接；
- PC 逐帧读取四个源文件，现场拼成 `1280×720` atlas（每格 `640×360`，
  顺序按 AVM3D 标定：左上 front、右上 right、左下 rear、右下 left），
  **不落 atlas 文件，也不读取 FPGA/HDMI 处理后的画面**。

同步流程：

1. 板端进入 `WAIT_START`；
2. PC 打开 `BoardSource`、绑定 UDP 7000、向板端发 `START`；
3. PC 再等待“启动延时”（默认 1000 ms，可调 0–5000 ms），让板端先跑；
4. PC 开始现场拼接，并对每一帧等待同 `frame_id` 的 `OBJECT` 到了再发布；
5. 四路帧数不一致时取最短通道，板端 `--frames` 同步截断；
6. 四路必须同帧率、同起点；否则日志会警告，只能做视觉演示，不能声称同帧。

车道线：

- 单路模式：整幅前向画面画 PC 车道中心线/外推/弯向；
- 四路 3D：**只在前向 inset 上画**，切换查看通道到右/后/左时不画；
- 不把 2D 车道点投到 3D 碗面，避免假几何；
- 四路 3D 下加载车道模型，30 帧实测约 22 ms/帧。

命令行等价入口：

```powershell
& $py -X utf8 rk_deploy\app\pc_launcher.py --auto --quad `
  --front reports\nuscenes_scene0061\front.mp4 `
  --right reports\nuscenes_scene0061\right.mp4 `
  --rear  reports\nuscenes_scene0061\rear.mp4 `
  --left  reports\nuscenes_scene0061\left.mp4 `
  --fps 15 --frames 30 --delay-ms 1000 --headless
```

实测（2026-10-30，nuScenes 四路 30 帧）：

- PC 30/30 `MATCHED`，队列丢帧 0，检测等待超时 0；
- 板端只发前向 YOLO，14.92 fps；
- 四路现场拼接约 17.5 ms/帧（1600×900 源），PC 车道约 22 ms/帧；
- 证据：`reports/launcher/quad3d_30f/`。

**阶段 A 边界**：使用本地源文件做窗口展示，不是 FPGA HDMI 回环，也不是 LIVE；
状态保持 `BOARD`。3D 几何默认使用 `sim_calibration.json`（id 7301）做视觉演示，
不是四路真实标定；nuScenes 精确视觉可另行换 9103。V3.2 的 HDMI Frame Marker、
`READY`、FPGA `LANE`、50K 前/后转发属于阶段 B，需要 50K/100Pro+/RK HDMI 链路
就绪后接入，不能把本阶段的文件演示冒充实时。


## 13. FPGA 发送与 HDMI 采集推理（N1 链路）

### 13.1 FPGA 发送

- 链路：RK3568 `eth1 10.10.20.1/30` → FPGA N1 `10.10.20.2`，静态邻居 `02:00:00:00:00:51`；
- 协议：`send_raw.py` + `video_protocol.py`，YTM1 包，CH2=前向、CH3=后向，960×540 RGB565；
- 板端 ffmpeg 预转码，按源文件修改时间缓存；`send_raw.py` 循环发送；
- 实测发送 36.9–40.5 fps/通道、DMA 丢弃 0；启动器现场发送约 19–25 fps 取决于板端负载。

启动器 GUI 的“开始 FPGA 传输”使用前向/后向两个文件；命令行：

```powershell
& $py -X utf8 rk_deploy\app\pc_launcher.py `
  --fpga-front reports\nuscenes_scene0061\front.mp4 `
  --fpga-rear  reports\nuscenes_scene0061\rear.mp4 `
  --fpga-fps 25 --fpga-frames 0
```

### 13.2 USB HDMI 采集卡

板端采集卡为 UVC：

```text
/dev/video0  Display capture-UVC05
1920x1080 MJPG, 60/30/15 fps
```

FPGA HDMI OUT 必须接到采集卡的 HDMI IN；只插 USB、不接 HDMI 时采集卡会输出黑底
“No Signal”，OpenCV 读不到有效帧。

板端单独测试采集 + 左上格裁剪 + YOLO：

```bash
python3 board_yolo_udp.py \
  --capture-device 0 --capture-width 1920 --capture-height 1080 \
  --capture-fps 15 --capture-fourcc MJPG --crop 0,0,960,540 \
  --host <PC_IP> --port 7000 --fps 15 --frames 0 \
  --control-port 7002 --post fast
```

- FPGA 2×2 布局：左上 front、右上 rear、下排双相机；
- 只裁 `0,0,960,540` 前向格再缩到 640×360，不能把整张 1920×1080 直接压成 640×360；
- 文件模式也可用 `--crop` 验证，例如 `--video atlas_4up.mp4 --crop 0,0,640,360`。

### 13.3 一条龙：FPGA HDMI 推理

GUI 按钮 **FPGA HDMI 推理**（或命令行 `--fpga-infer`）执行：

1. 上传前/后向视频，板端转 RGB565；检查 `/dev/video0`；
2. 启动 FPGA 发送（CH2/CH3），发送帧率与采集/YOLO 帧率对齐；
3. 启动板端 UVC 采集；拿到第一帧真实 HDMI 画面后**直接开始推理**，不再等待 PC
   的 START（`--control-port` 可省略），因此 PC 中途加入也不会卡在 `WAIT_START`：
   按实际帧自动裁左上 1/4（1920×1080 时为 `960×540`），RKNN 推理，OBJECT UDP 到 PC；
4. 板端把裁剪后的前向画面编码为 JPEG，UDP 7100 回传 PC；PC 窗口直接显示
   板端采集画面，并按 JPEG 头里的 `frame_id` 等待同帧 OBJECT；
5. 退出时同时停止 `board_yolo_udp.py` 和 `send_raw.py`。

`--fpga-frames N` 同时限制发送素材和 PC 窗口帧数：`N=0` 时窗口常驻直至手动关闭，
`N>0` 时窗口播完 N 帧自动退出并写 `fpga_stats.json`，便于无人值守回归。

```powershell
& $py -X utf8 rk_deploy\app\pc_launcher.py `
  --fpga-infer `
  --fpga-front reports\nuscenes_scene0061\front.mp4 `
  --fpga-rear  reports\nuscenes_scene0061\rear.mp4 `
  --capture-device 0 --capture-fps 15 --crop auto `
  --fpga-fps 15 --fpga-frames 150 --shots 2
```

边界：

- 当前 PC 显示的是**板端回传的 JPEG 前向画面**，不是本地文件；JPEG 与 OBJECT 使用
  板端同一 `frame_id`，但没有 HDMI Frame Marker/跨板时间戳，不能声明严格同帧或 LIVE；
- 为对齐，发送、采集、YOLO 都按 15 fps；40 fps 只适用于纯 FPGA 发送；
- 板载 HDMI IN 驱动未启用，本链路使用 USB UVC 采集卡；
- 30 min 长稳、温度和跨板一致性仍未测。

### 13.4 板端环境实测（2026-11-01）

板端 UVC 采集卡曾出现“USB 已识别但 HDMI 无帧”，根因是 USB 运行时电源管理：

```text
/sys/bus/usb/devices/5-1/power/control = auto
/sys/bus/usb/devices/5-1/power/runtime_status = suspended
```

把 `power/control` 设为 `on` 并复位 USB 后恢复。启动器 `FPGA HDMI 推理` 的预检
现在会先对 `1de1:f115` 执行 `power/control=on`（需要板端 `sudo -n`），避免再次 suspend。

采集卡上电/HDMI 刚锁定时会先输出黑底 `No Signal` 帧（1920×1080，mean≈0.4）；
板端脚本用 `--min-mean 5` 跳过这些帧，拿到真实帧后再开始推理。真实采集可能是
1920×1080 或 640×480，`--crop auto` 按实际帧取左上 1/4，避免把整张宫格压扁。

端到端实测（前向/后向 nuScenes，FPGA 发送 15 fps，板端采集 15 fps）：

- 板端采集：1920×1080 MJPG，自动裁左上 `960×540`，RKNN 单帧约 44–47 ms；
- PC：**150/150 MATCHED**，0 丢帧，0 等待超时，渲染 p95 12.3 ms；
- PC 配置 `video.kind=udp`、`udp_port=7100`；窗口显示的是板端采集/裁剪画面；
  证据：`reports/launcher/fpga_chain_150f/`，窗口截图 `window_board.png`。

无 START 版本复测（同日，`--fpga-frames 150 --shots 2`）：

- 板端拿到首帧后直接推理，日志出现 `[board] model=`；PC 中途加入，**窗口首帧即显示
  板端 JPEG 画面**，不再出现空白窗口或 `wait START timeout`；
- PC：150 帧产出、151 条协议、0 丢帧、0 stale、150 次同帧等待命中、0 超时；
  其中首帧因 PC 晚加入存在 1 次未匹配（149/150 MATCHED），属预期启动瞬态；
- 板端单帧 45.1–54.7 ms（pre 1.4–5.6 ms，infer 37.4–42.1 ms，post 5.2–11.2 ms），
  采集 1920×1080 MJPG → 左上 `960×540` 裁剪，检测 1–6 个目标；
- 证据：`reports/launcher/fpga_chain_nostart2/`（首帧/末帧截图、`fpga_stats.json`、
  `run_hdmi.log`、`send_raw.log`、`launcher.log`）。

当前结论：**FPGA HDMI → 板端 UVC → YOLO → 板端 JPEG 回传 → PC 窗口**已打通；
PC 窗口显示板端画面，但不能声明严格同帧或 LIVE。若 FPGA KEY2 处于灰度/二值模式，
YOLO 会看到处理后的画面，检测数可能为 0；切换干净彩色后再看检测结果。

### 13.5 三框同显（Stage B 预览）

一个窗口同时显示：

1. 左：本地四路源文件经 Stage A 现场拼 1280×720，再上 GL 碗面；
2. 右上：FPGA HDMI 左上 1/4 前路，板端 RKNN 检测；
3. 右下：FPGA 整张 2×2 四宫格，板端 RKNN 再跑一次检测。

板端同一次采集顺序跑两次 RKNN（同一个模型）：

| 输入 | 推理坐标 | OBJECT | JPEG |
|---|---|---|---|
| 左上 1/4 前路 | 640×360 | `7000` | `7100` |
| 整张四宫格 | 960×540 | `7001` | `7200` |

两路使用同一个 `frame_id`；板端**先发 OBJECT 再发 JPEG**，PC 收到画面时同帧框
已经可查。PC 端从最近 8 帧里选两路共同的 `frame_id` 配对显示，右两框因此能长期
保持 `PAIR MATCHED`。

```powershell
& $py -X utf8 rk_deploy\app\pc_launcher.py `
  --fpga-triple `
  --front reports\nuscenes_scene0061\front.mp4 `
  --right reports\nuscenes_scene0061\right.mp4 `
  --rear  reports\nuscenes_scene0061\rear.mp4 `
  --left  reports\nuscenes_scene0061\left.mp4 `
  --capture-fps 15 --crop auto --fpga-frames 200 --shots 2 --headless
```

GUI 对应按钮：**FPGA 三框**（使用四路 3D 源文件；前/后向同时发 FPGA）。

边界：

- 左框是**本地四路源文件**，不是 FPGA 视频；三框不同源，不能声称同帧；
- 右两框同源、同 `frame_id`，但没有 HDMI Frame Marker/跨板时间戳，仍不能声明
  严格同帧或 LIVE；
- 双推理使板端降到约 5.5–6 fps；PC 三框 UI 与本地 3D 约 15 fps；
- 整张四宫格在 960×540 坐标系输出框，PC 按面板显示尺寸等比缩放。

实测（2026-11-01，200 帧）：

- 板端前路 46–57 ms/帧、四宫格 48–57 ms/帧，双推理 5.7 fps；
- PC 前路 JPEG 78 帧 / 四宫格 JPEG 83 帧，协议 79/78 条；前路 OBJECT 缺包 0，
  四宫格启动期缺包 5；
- 右两框配对 76 帧、未配 0 tick；三框 UI 14.9 fps、本地 3D 14.9 fps、GL OK；
- 证据：`reports/launcher/fpga_triple_final/`（两张截图、`triple_stats.json`、
  `pc_triple.log`、`run_hdmi.log`、`send_raw.log`）。

启动器可靠性修正：

- 板端改为 `setsid nohup ... < /dev/null` detached 启动；SSH 会话断开不再带走
  板端采集进程（此前表现为板端日志停在某一帧、PC 三框只有左框）；
- 停止统一用 `pkill -f '[b]oard_yolo_udp.py'`，兼容绝对路径启动的板端进程。
