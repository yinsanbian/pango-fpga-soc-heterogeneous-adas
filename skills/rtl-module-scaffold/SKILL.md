---
name: rtl-module-scaffold
description: 为夜瞳多目 FPGA 项目生成符合流水线纪律的 Verilog 模块骨架（valid 对齐、级间打拍、延迟登记、AXIS 接口、行缓存模板）。在新建任何一个 rtl/ 模块时使用。
---

# RTL 模块骨架生成

服务于 `docs/04-工作流程.md` §3.1 第③步 与 §3.3 流水线纪律（目标 ID：**ALG-07, SYS-01**）。

## 何时用

- 要新写一个 `rtl/` 下的模块（行缓存、灰度、高斯、CLAHE、Sobel、CBAM、NMS、OSD…）
- 需要把已有模块改造成符合流水线纪律的结构

## 项目约定（不可违背）

1. **文件头必须登记总延迟**：`// LATENCY: <N> cycles`，供 SYS-04 端到端延迟核算。
2. **像素流统一用 AXI4-Stream 风格**：`s_axis_*` / `m_axis_*`，含 `tvalid/tready/tdata/tuser(SOF)/tlast(EOL)`。
3. **8bit 灰度单通道**为主，1080P 行有效 1920。
4. **级间必须打拍**，禁止跨模块长组合路径。
5. **行缓存读写指针必须与 `pixel_valid` 同源推进**（禁各自计数）—— 避坑 #9。
6. 跨时钟域一律异步 FIFO，并在 `constr/` 登记。

## 生成骨架

```verilog
// ============================================================
// Module : <模块名>
// Target : <ALG-0x / AI-0x>
// Desc   : <一句话>
// LATENCY: <N> cycles @ <clk 频率>
// Note   : 位宽/定点格式 Q<m>.<n>
// ============================================================
module <模块名> #(
    parameter P_DATA_W = 8,
    parameter P_IMG_W  = 1920
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // ---- 输入流 ----
    input  wire [P_DATA_W-1:0]      s_axis_tdata,
    input  wire                     s_axis_tvalid,
    input  wire                     s_axis_tuser,   // SOF
    input  wire                     s_axis_tlast,   // EOL
    output wire                     s_axis_tready,

    // ---- 输出流 ----
    output reg  [P_DATA_W-1:0]      m_axis_tdata,
    output reg                      m_axis_tvalid,
    output reg                      m_axis_tuser,
    output reg                      m_axis_tlast,
    input  wire                     m_axis_tready,

    // ---- 配置（AXI4-Lite 侧，可选） ----
    input  wire [15:0]              cfg_<参数>
);

    // ---------- 级 1：输入寄存 ----------
    reg [P_DATA_W-1:0] s1_data;
    reg                s1_valid, s1_sof, s1_eol;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 1'b0; s1_sof <= 1'b0; s1_eol <= 1'b0;
        end else if (s_axis_tready) begin
            s1_data  <= s_axis_tdata;
            s1_valid <= s_axis_tvalid;
            s1_sof   <= s_axis_tuser;
            s1_eol   <= s_axis_tlast;
        end
    end

    // ---------- 级 2：核心运算 ----------
    // <在此实现算法；每一级结束都把 valid 一起打拍>

    // ---------- 级 N：输出寄存 ----------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tvalid <= 1'b0; m_axis_tuser <= 1'b0; m_axis_tlast <= 1'b0;
        end else if (m_axis_tready) begin
            m_axis_tdata  <= <结果>;
            m_axis_tvalid <= s1_valid;
            m_axis_tuser  <= s1_sof;
            m_axis_tlast  <= s1_eol;
        end
    end

    assign s_axis_tready = m_axis_tready;   // 无反压处理时直通；有反压需改握手

endmodule
```

## 3×3 窗口 / 行缓存骨架要点

- 用**双口 RAM** 缓存 **2 行**（1080P：深度 1920 × 8bit），配合当前行构成 3 行。
- 窗口寄存器阵列 `w00..w22` 在**同一拍**整体移位，**移位使能 = pixel_valid**。
- 行缓存的**读地址 = 写地址延迟一行**，二者由**同一个** `pixel_valid` 驱动计数器产生。
- 输出 valid 相对输入 valid 的延迟 = 2 行 + 窗口填充延迟，**必须写进文件头 LATENCY**。

## 完成后必做

1. 跑 `verilog-lint-gate` 检查位宽/latch。
2. 用 `refmodel-golden-gen` 生成金标准，做逐拍比对。
3. 比对报告存 `reports/sim_<模块名>.md`。
