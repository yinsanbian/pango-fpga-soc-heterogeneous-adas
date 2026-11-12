# 推理策略与部署调优

## ROI 区域推理（零精度损失）

工业场景检测范围固定（如传送带中间区域），只裁剪感兴趣区域推理，再把框坐标映射回原图。运行 `scripts/roi_infer.py`：

```bash
python scripts/roi_infer.py --model yolov8l_int8.pt --image img.jpg --roi 100,100,500,500
```

示例：全图 35ms → ROI 推理 22ms（Jetson Xavier NX）。

## 动态锚框

COCO 预定义锚框与工业目标尺寸不匹配，用现场标注框 KMeans 聚成 3~5 个锚框，写回配置并重训：

```python
import numpy as np
from sklearn.cluster import KMeans

annos = []  # 现场标注框 [w, h]
kmeans = KMeans(n_clusters=3, random_state=0).fit(annos)
print(kmeans.cluster_centers_)   # 替换 YOLO 配置中的锚框
```

## NMS 优化

- 快速 NMS：阈值预筛，减少参与 NMS 的框数；
- DIoU-NMS：同时考虑重叠度与中心点距离，精度更高、速度相当；
- 批量 NMS：多图框批量处理，利用 GPU 并行。

## 推理框架选型

框架优先级：**TensorRT > OpenVINO > ONNX Runtime > PyTorch**。CPU 场景务必用 OpenVINO 而非 TensorRT。

## 静态 batch 与指令集

- 工业场景用**静态 batch=1**，动态 batch 会降低 TensorRT 加速效果。
- CPU 推理确认开启 AVX-512 指令集，否则速度下降约 30%。

## 多线程调度与预处理异步化

多相机产线场景，用线程池并发，预处理（读图/裁剪/归一化）与推理并行，消除预处理瓶颈，并做硬件亲和/资源隔离避免多线程抢占 GPU：

```python
from concurrent.futures import ThreadPoolExecutor
from ultralytics import YOLO
import cv2

model = YOLO("yolov8l_int8.trt")
camera_list = ["rtsp://ip1/stream", "rtsp://ip2/stream"]

def infer_camera(url):
    cap = cv2.VideoCapture(url)
    while cap.isOpened():
        ok, frame = cap.read()
        if not ok: break
        frame = cv2.resize(frame, (640, 640))
        results = model(frame)
        # ... 后处理
    cap.release()

with ThreadPoolExecutor(max_workers=len(camera_list)) as ex:
    ex.map(infer_camera, camera_list)
```

注意：

- 线程数 = 相机数；线程亲和/资源隔离，避免抢占 GPU；
- 预处理占比 >50% 时务必异步化；
- 需处理推理超时、图像模糊等异常，保证产线不停机。
