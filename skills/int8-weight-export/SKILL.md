---
name: int8-weight-export
description: 把训练好的 LPRNet+CBAM 权重做 INT8 量化，导出 FPGA 可 $readmemh 加载的 .mem/.coe，并产出逐层中间结果固定测试向量。在模型量化与权重导出阶段（AI-03）使用。
---

# INT8 量化与权重导出

服务于 `docs/04-工作流程.md` §3.1 第②步（目标 ID：**AI-03**，被 M5 门禁实际视为 P0）。

## 何时用

- PyTorch 模型已训练收敛（AI-01）之后
- 需要给 CBAM/CNN 加速器（AI-04/05/06）提供权重与逐层比对基准

## ⚠️ 本机环境现状

**当前未安装 `torch` / `torchvision` / `onnx`**。
训练与量化需先安装（`pip install torch torchvision`），或在有 GPU 的机器上做。**本 skill 的导出/校验部分（numpy）在本机可直接跑。**

## 目标产物

| 产物 | 路径 | 用途 |
|---|---|---|
| 量化权重 | `gen/weights/<layer>.mem` | `$readmemh` 加载 |
| 量化偏置 | `gen/weights/<layer>_bias.mem` | 同上 |
| 逐层测试向量 | `sim/vectors/<layer>_in.mem` | 硬件逐层比对 |
| 逐层期望输出 | `sim/golden/<layer>_out.mem` | 同上 |
| 量化精度报告 | `reports/quant_accuracy.md` | 证明精度损失 < 2% |

## 量化流程

```
① 逐层权重统计 min/max → 确定 scale（per-tensor 起步，够用再上 per-channel）
② W_q = round(W / scale)  截断到 int8 [-128,127]
③ 校准集前向（500~1000 张夜间+白天样本）→ 激活 scale
④ 逐层导出 + 记录 (layer, scale, zero_point) 到 gen/weights/manifest.json  ★关键
⑤ 量化后模型在测试集评估 → 精度损失必须 < 2%
```

> 🔑 **`manifest.json` 是 RTL 定点参数的唯一真源**。
> Verilog 里做乘加后的移位量必须从这里取，**禁止在 RTL 里硬编码另一套 scale**。

## `.mem` 导出格式

```python
# int8 权重：按 int8 的补码十六进制输出
def dump_mem(path, arr_int8):
    with open(path, "w") as f:
        for v in arr_int8.flatten():
            f.write(f"{int(v) & 0xFF:02x}\n")
```

- 卷积权重**排列顺序必须与 RTL 的读取顺序一致**（建议 [out_ch][in_ch][kh][kw]），**在模块头注释里写死并同步**。
- CBAM 通道注意力的 FC 权重同样按此导出（AI-04）。
- 空间注意力的 7×7 卷积核用小尺寸，可直接内联为常数，不必走 .mem。

## 验收

- [ ] `$readmemh` 在仿真中能正确加载（无 X、无截断警告）
- [ ] 量化后测试集精度损失 **< 2%**
- [ ] 逐层比对 mismatch = 0
- [ ] `manifest.json` 与 RTL 参数一致性人工核对过一遍
