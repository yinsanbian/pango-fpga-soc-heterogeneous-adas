# 模型转换

## 导出 ONNX（必须静态）

```python
model.export(
    format="onnx",
    opset=12,            # 12 或 13 均可（实测 export 走 **kwargs，两者都接受）；转换失败先降级
    simplify=True,
    dynamic=False,       # 端侧必须 False，固定尺寸更快
    imgsz=640,
)
```

> ⚠️ 有来源文章建议端侧导出加 `--dynamic`，**那条是错的**（会导致动态 shape 报错），
> 见 `deployment.md` 的勘误一节与 `provenance.md` 第 7 条。

## ONNX 简化（部署必备）

去除冗余节点，解决端侧不支持的算子：

```bash
onnxsim yolov8n.onnx yolov8n-sim.onnx
```

## 格式优先级

**TensorRT Engine > RKNN > OpenVINO IR > ONNX > PyTorch**

## 各后端转换命令

| 硬件 | 后端 | 命令 |
|---|---|---|
| Jetson / NVIDIA | TensorRT | `trtexec --onnx=yolov8n.onnx --saveEngine=yolov8n.trt --fp16` |
| 瑞芯微 RK3588 | RKNN | `rknn_toolkit convert --model yolov8n-sim.onnx --output yolov8n.rknn --quantize int8` |
| Intel CPU / 核显 | OpenVINO | `model.export(format="openvino", imgsz=640)`（产出 .xml/.bin） |
| Android / 手机 | NCNN | `onnx2ncnn yolov8n.onnx yolov8n.param yolov8n.bin` |

## 常见转换失败处理

- 指定 `opset 12/13`（TensorRT 解析失败多因未指定 opset）；
- 先 `onnxsim` 简化，解决端侧不支持的算子；
- 导出时 `dynamic=False`，固定输入尺寸与静态 batch=1。
