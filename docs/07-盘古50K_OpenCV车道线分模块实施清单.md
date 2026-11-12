# 07 · 盘古 50K + OpenCV 车道线分模块实施清单

> 更新日期：2026-09-26
>
> 本文件把用户要求与桌面方案文档分开记录：用户要求是“先列出模块清单，再按依赖顺序实现，并为每个实现给出依据”；桌面方案文档提供的是目标架构、推荐顺序和若干代码框架，其中板卡引脚、HDMI 端口名和部分参数明确标注为占位内容，不能直接当作当前板卡约束。

## 一、实施边界

### 用户要求

1. 先按模块列出功能清单。
2. 按依赖顺序逐项实现。
3. 每项实现必须能追溯到方案、现有工程证据、论文/官方文档或可复现实验。
4. 不凭空填写 PGL50H 的引脚、时钟、接口端口和摄像头寄存器。

### 桌面方案中的工程约束

1. 第一版优先视频链路跑通，再接图像算法。
2. 第一版优先 1280×720@30，HDMI 优先，OV5640 后置。
3. FPGA 做像素级预处理；PC/OpenCV 做概率霍夫、左右线筛选、拟合、中心和偏移。
4. 每一级都要能单独观察或用金标准验证，不能一次性把整条链路写完再定位问题。

### 当前仓库事实

1. rtl/preprocess/ 和 rtl/lane/ 已有灰度、高斯、Sobel、Canny、ROI、霍夫和拟合链路；ModelSim 回归当前为 4/4 通过。
2. 现有 lane_detect_top 是 AXIS 算法顶层，不是带真实板级 HDMI 引脚的最终顶层。
3. pds_ov5640/10_HDMI_DDR3_OV5640_test/ 是板卡视频输入、DDR3 和 HDMI 输出的官方例程资产；其端口和约束只能在核对当前板卡资料后接入。
4. 因此本轮不重写已通过的算法链，也不猜测新引脚；先补齐可独立仿真和 PC 端可运行的缺口。

## 二、模块清单与先后顺序

| 顺序 | 模块 | 目标功能 | 当前状态 | 实现位置 | 验收依据 |
|---:|---|---|---|---|---|
| 0 | 板卡/接口契约 | 锁定 PGL50H 器件、官方视频例程、时钟和约束来源 | 已建立，暂不猜 pin | pds_ov5640/、constr/、pds/ | 官方例程文件、PDS 流程和约束审查 |
| 1 | RGB888→Gray | 定点灰度化 | 已完成 | rtl/preprocess/rgb2gray.v | 77/150/29 Q8 公式；sim 逐拍比对 |
| 2 | Gray→Binary | 阈值化并保留 AXIS 坐标/帧侧带 | 本轮实现 | rtl/preprocess/binarization.v | 桌面方案第 9 节；新增 binary 仿真 |
| 3 | 坐标/ROI | 梯形道路区域掩膜 | 已完成 | rtl/lane/roi_mask.v | 桌面方案第 10/11 节；RTL 与参考模型参数一致 |
| 4 | Line buffer + 3×3 Sobel | 行缓存、梯度幅值和方向 | 已完成 | rtl/preprocess/line_buffer_3x3.v、sobel_3x3.v | Sobel 核和 L1 幅值；逐拍金标准 |
| 5 | FPGA 调试显示 | 原图、灰度、二值、ROI、Sobel、叠加模式 | 本轮实现像素级选择器 | rtl/display/display_mux.v | 桌面方案第 15/16 节；新增 display 仿真 |
| 6 | HDMI/采集卡→PC | 打开摄像头或 USB HDMI 采集卡并读取帧 | 本轮实现 | opencv_lane/capture.py | OpenCV VideoCapture 官方接口；文件源可复现 |
| 7 | PC 预处理 | 原图模式下 Gray/Gaussian/Canny；FPGA 模式下避免重复预处理 | 本轮实现 | opencv_lane/preprocess.py | OpenCV Canny 语义；FPGA 模式分支 |
| 8 | PC 概率霍夫 | 从 ROI 边缘提取线段 | 本轮实现 | opencv_lane/lane_detect.py | HoughLinesP 参数与桌面方案对齐 |
| 9 | 左右线筛选/拟合 | 斜率筛选，拟合 x=k*y+b | 本轮实现 | opencv_lane/lane_fit.py | 桌面方案第 21 节；合成图单元测试 |
| 10 | 车道中心/偏移 | 计算车道中心、图像中心和像素偏移 | 本轮实现 | opencv_lane/lane_fit.py | 桌面方案第 22 节；测试断言 |
| 11 | 结果叠加/主程序 | 画线、中心线、Offset、保存或实时显示 | 本轮实现 | opencv_lane/overlay.py、main.py | 无 GUI 文件回放测试 + CLI |
| 12 | OV5640 最终接入 | 用摄像头替换第一版视频源 | 待板上核验 | 官方例程与板卡约束 | 只有硬件实测通过后标记完成 |

## 三、本轮实现依据

| 功能 | 依据 | 不采用的假设 |
|---|---|---|
| 二值化 | 桌面方案第 9 节的 gray >= threshold 逻辑；输出沿用现有 AXIS 侧带契约 | 不假设固定 HDMI 端口名，不把阈值宣称为所有场景最优 |
| 显示模式 | 桌面方案第 15/16 节的 000–101 模式定义 | 选择器只负责同拍像素；不同流水级的时序对齐仍由上层连接负责 |
| ROI | 统一采用仓库已验证的 0.10/0.90 底边、0.40/0.60 顶边、0.60H–0.95H 行区间 | 不同时复制桌面方案 PC 示例中的另一组 0.52H 参数 |
| OpenCV Canny | OpenCV 官方 Canny 教程与现有 model/ref_lane_detect.py | FPGA 已输出 Sobel/二值模式时不在 PC 重复 Gaussian/Canny |
| OpenCV Hough | OpenCV HoughLinesP 接口与桌面方案给出的 rho=1、theta=π/180、阈值参数 | 不把硬件端 hough_acc 的降采样参数直接当成 OpenCV 参数 |
| 拟合与偏移 | 桌面方案中 x=k*y+b、两侧斜率和 Offset 定义 | 不在没有双侧车道线时伪造 Offset |
| 视频采集 | OpenCV VideoCapture，同时支持设备索引和文件回放 | 不假设采集卡一定枚举为设备 0 |

## 四、阶段门禁

1. binary：4 个灰度边界值和侧带全部通过。
2. display：6 个显示模式输出值全部通过。
3. opencv_lane：合成道路图能检出左右线，Offset 接近已知真值；文件回放不依赖 GUI。
4. 现有 sim -All：原有 4 项必须继续保持通过。
5. PDS/上板 HDMI 和 OV5640：必须使用当前板卡官方约束并单独实测，不能由 PC 仿真代替。

## 五、下一阶段

完成本轮模块后，下一步是把 display_mux 和二值化支路接到官方视频例程的有效像素域，并为每个显示模式提供板上可观察的切换入口；这一步需要先确认当前板卡的 HDMI/OV5640 输入选择和约束文件，不在没有依据时直接修改官方顶层。

