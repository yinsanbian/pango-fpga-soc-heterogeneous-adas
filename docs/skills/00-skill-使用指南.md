# 00 · 项目 Skill 使用指南

> 本目录配套 6 个**项目级 skill**，位于仓库根 `.dsh/skills/`。
> 作用：把 [`../04-工作流程.md`](../04-%E5%B7%A5%E4%BD%9C%E6%B5%81%E7%A8%8B.md) §三 的**模块六步流程**从"口头纪律"变成"可一键执行的步骤"。
>
> ⚠️ **`.dsh/` 已加入 `.gitignore`，不进版本控制**（本项目决定）。
> 因此本文件是 skill 的**唯一可版本化载体**：队友 clone 仓库后拿不到 skill，需按 §五 自行复制。

---

## 一、为什么需要 skill

本项目最大的两个失败模式：

1. **避坑 #11**：直接写 Verilog 实现 CLAHE → 调试地狱，看不到效果。
2. **避坑 #9**：行缓存指针与 `pixel_valid` 未对齐 → 3×3 窗口像素错位，极难定位。

这两个坑的共同点是：**都知道该怎么做，但执行时容易跳过**。
Skill 把正确顺序固化下来，让 AI 助手（或团队成员）在动手前就被强制走对流程。

---

## 二、Skill 清单与用途

| Skill | 一句话 | 对应工作流环节 | 服务目标 ID |
|---|---|---|---|
| `rtl-module-scaffold` | 生成合规 Verilog 模块骨架 | §3.1 ③ | ALG-07, SYS-01 |
| `verilog-lint-gate` | 提交前静态自检门禁 | §3.1 ⑤ 前置 | ALG-07 |
| `refmodel-golden-gen` | Python 参考模型 + 金标准激励 | §3.1 ①④ | ALG-01~06 |
| `int8-weight-export` | INT8 量化 + .mem 导出 | §3.1 ② | AI-03 |
| `timing-constraints-fdc` | PDS 时序约束生成与审查 | §六 SYS-01 | SYS-01/02/03 |
| `kpi-dashboard` | KPI 看板维护与校核 | §七 | SYS-04/05, DOC-01/04 |

---

## 三、按阶段的使用顺序

```
阶段一 W1    ── 装工具链（自检清单见 verilog-lint-gate 的环境前提）
阶段二 W2-W3 ── rtl-module-scaffold 起步 DVP 采样 / DDR3 仲裁模块
阶段三 W4-W5 ── rtl-module-scaffold 起步 AXI 从机；timing-constraints-fdc 首版约束 ★W6 前
阶段四 W6-W8 ── 【每模块标准动作】
                 refmodel-golden-gen  →  rtl-module-scaffold
                 →  verilog-lint-gate  →  仿真比对
阶段五 W9-W12── int8-weight-export → rtl-module-scaffold(CBAM/CNN/NMS)
                 → verilog-lint-gate
                 【W12】Go/No-Go 决策 → reports/go_nogo_W12.md
阶段六 W13-W16── timing-constraints-fdc 收口 → kpi-dashboard 出数据 → PPT
```

### 每个模块的标准动作（阶段四/五 反复执行）

```bash
# 1. 先做算法验证与金标准
#    → 调用 refmodel-golden-gen
#    产出 model/ref_<算法>.py、sim/vectors/*.mem、sim/golden/*.mem

# 2. 再写 RTL
#    → 调用 rtl-module-scaffold
#    产出 rtl/<模块>/<模块>.v（含 LATENCY 登记）

# 3. 提交前自检
#    → 调用 verilog-lint-gate
#    产出 reports/lint_<模块>.md（FAIL 则禁止合并 main）

# 4. 仿真逐拍比对，mismatch 必须 = 0
#    产出 reports/sim_<模块>.md
```

---

## 四、当前环境限制（务必先读）

本机实测的工具链现状，直接影响哪些 skill 能立刻用：

| 工具 | 状态 | 影响 |
|---|---|---|
| Python 3.13 + numpy/scipy/scikit-image/Pillow | ✅ 已装 | `refmodel-golden-gen` **可直接用** |
| Node.js | ✅ 已装 | — |
| **PyTorch / torchvision / ONNX** | ❌ **未装** | `int8-weight-export` 的**训练/量化部分需先装**；导出校验部分可跑 |
| **iverilog / verilator / yosys** | ❌ **未装** | **无法做功能仿真** —— 强烈建议 W2 前装上，否则阶段四只能盲写 |
| **PDS / Pango Design Suite** | ❌ 未发现安装 | 综合、时序、比特流全部无法进行 → 卡住 M2 之后所有门禁 |
| **git CLI** | ✅ **已装** git 2.55.0（`C:\Program Files\Git\cmd\git.exe`） | INF-05 已就绪；仓库已 `git init -b main` |
| OpenCV / matplotlib | ❌ 未装 | 无影响（已用 skimage/PIL/scipy 替代） |

> 🔴 **W1 剩余阻塞项（按紧急度）**：① 开发板与 PDS ② iverilog ③ PyTorch（阶段五前）。git 已解决。
> ⚠️ **PATH 提示**：git 安装后机器 PATH 已含 `C:\Program Files\Git\cmd`，但**已在运行的进程（含本 DSH 会话）继承的是旧环境**。
> 新开终端即可直接用 `git`；老进程需走全路径，或重启 DSH。
> 见 [`../02-目标分类.md`](../02-%E7%9B%AE%E6%A0%87%E5%88%86%E7%B1%BB.md) INF-01~05 与 [`../03-关键资源与避坑清单.md`](../03-%E5%85%B3%E9%94%AE%E8%B5%84%E6%BA%90%E4%B8%8E%E9%81%BF%E5%9D%91%E6%B8%85%E5%8D%95.md)。

---

## 五、维护规范

| 项 | 约定 |
|---|---|
| 位置 | 仓库根 `.dsh/skills/<skill-name>/SKILL.md`（**已 gitignore，不入库**） |
| 命名 | 仅小写字母/数字/连字符，**必须与目录名一致** |
| Frontmatter | 必填 `name` + `description`；description 要写清**何时使用**（它决定 AI 何时自动加载） |
| 新增流程 | 新建目录 → 写 SKILL.md → 在本文件 §二 登记一行 → **保留一份可版本化的副本**（见下） |
| 冲突 | 若 `refmodel-golden-gen` 与 `kpi-dashboard` 的指标口径不一致，**以 `docs/04-工作流程.md` §七 为准** |

### ⚠️ 备份要求（因为 `.dsh/` 不入库）

`.dsh/` 已在 `.gitignore` 中，**clone 仓库的人拿不到 skill**。因此：

| 做法 | 说明 |
|---|---|
| **① 用户级安装（推荐）** | 复制到 `C:\Users\<你>\.dsh\skills\<skill-name>\SKILL.md`，本机任意目录都生效 |
| ② 手动归档 | 将 `.dsh/skills/` 打包放网盘，并在 `README` 记录版本号（与比特流、权重同一处理方式） |
| ③ 新成员接入 | 按本文件 §二 清单逐个重建（每个 SKILL.md 都不长，约 45~85 行） |

> 本文件（`docs/skills/00-skill-使用指南.md`）是**唯一进版本控制**的 skill 载体 ——
> 它记录了 skill 清单、用途与关键约定，即使 `.dsh/` 丢失也能据此重建。

### 运行前提（已实测）

项目级 skill 的发现依赖**仓库根存在 `.git` 目录**（DSH 用它定位项目根）：

- 本仓库已 `git init -b main`，**前提已满足** ✅
- 若日后 skill 未生效，先确认 `D:\ziguang\.git` 是否存在
- 若在**子目录**下启动 DSH，会用正向查找定位到仓库根，仍可生效
