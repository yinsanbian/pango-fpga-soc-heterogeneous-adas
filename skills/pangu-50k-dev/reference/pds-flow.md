# PDS 开发流程与工程规范（盘古50K 实测笔记）

> **本文证据边界**：全部结论来自本机文件与本机命令实测，**未联网**。
> 主要证据源：
> - 安装目录 `D:\PDS23.2\PDS_2023.2-SP3-ads`（`bin\`、`doc\`、`arch\`、`Templates\`）
> - 官方例程 `D:\ziguang\pds_ov5640\10_HDMI_DDR3_OV5640_test\`（`impl.tcl`、各阶段 `run.log`、`report_timing\*.rtr`、`log\`）
> - 本机实测探测（2026-09-22 13:34，工作目录 `D:\ziguang\tmp\pds_probe\`，**只读探测 + 临时目录**）
> - `D:\ziguang\reports\pds_pds文件改动核查_20260920.md`（并发改工程事件核查）
>
> 标注「**（推断，依据：…）**」的是推断；拿不到的写「**未确认**」。

---

## 1. 环境事实（实测）

### 1.1 版本 / Build / 安装路径

| 项 | 实测值 | 证据 |
|---|---|---|
| 产品名 | Fabric Compiler（Pango Design Suite） | `bin\flow.log:1` |
| 版本 | `2023.2-SP3` | `bin\flow.log:1`、`pds_shell.exe -version` 输出 |
| Build | `154097`，构建时间 `May 10 00:31 2024` | `bin\flow.log:1`、`bin\run.log:1` |
| 安装目录 | `D:\PDS23.2\PDS_2023.2-SP3-ads` | `bin\flow.log:2` |
| 安装根子目录 | `arch / assistant / bin / doc / driver / example / ip / parellel_driver` + `license.rtf`、`PDS-0028F8405C9F.lic`、`uninst.exe` | 目录列举 |
| 帮助文档 | `doc\` 下 24 个 PDF（含 `Tcl_Command_User_Guide.pdf`、`Pango_Design_Suite_User_Guide.pdf`、`Fabric_Configuration_User_Guide.pdf`）+ `bin\helpDoc_pango.qch/.qhc` | 目录列举 |

> ⚠️ **本笔记未阅读上述 PDF 正文**（PDF 内容为压缩流，无离线抽取工具）。PDF 只用于"存在性"引用。

### 1.2 `bin\` 内与流程相关的可执行文件（按体积）

| 文件 | 体积 | 作用（依据） |
|---|---|---|
| `pds.exe` | 79,259,136 | GUI 主程序（`pds.log:3` `#Application name: pds.exe`） |
| `pce.exe` | 79,300,608 | Physical Constraint Editor（`doc\Physical_Constraint_Editor_User_Guide.pdf`；PCE 生成 `.pcf`） |
| `ta.exe` | 78,139,392 | Timing Analyzer |
| `ppp.exe` / `ppc.exe` | 75,777,024 / 77,508,096 | Power Planner / Power Calculator |
| `pds_shell.exe` | 69,135,872 | **Tcl 后端**，批处理入口 |
| `ip_compiler.exe` / `ip_generate.exe` | 64,041,472 / 63,684,608 | IP 核编译 / 生成（`.idf` 相关） |
| `cdt_cfg.exe` | 6,480,896 | **配置/下载工具**（`log\cfg.log:3` `#Application name: cdt_cfg.exe`） |
| `cdt_js.exe` | 4,916,736 | **JtagServer**（`log\js.log:3` `#Application name: cdt_js.exe`） |
| `cdt_dbg.exe` / `cdt_ins.exe` | 6,329,344 / 65,146,880 | Debugger / Inserter |
| `ftd2xx.dll` | 258,416 | FTDI D2XX 驱动（USB 下载线；`log\cfg.log:16` `PANGO USB CABLE II cable driver: D2XX DLL`） |
| `sqlite3.dll` | 1,284,096 | SQLite（**注意**：本工程的 `*.db` 实际是 XML，不是 SQLite，见 §3） |
| `tmpXXXX.pds` × 10 | 各 3,312 | **MCP 探测遗留的临时工程**，默认器件 `PGL12G/-5/FBG256`（见 §4） |

### 1.3 License（实测）

- License 文件：`D:\PDS23.2\License\new_pds_F4A80DA47D72.lic`（1,086 B）
- 实测签出成功（`echo "puts hello; exit" | pds_shell.exe` 的第一行输出）：

```
License checkout: fabric_shell from D:\PDS23.2\License\new_pds_F4A80DA47D72.lic
Compiling architecture definition.
hello
```

- `.lic` 内容（`new_pds_F4A80DA47D72.lic:1-2`）：
  - `-pkg_name {pango_design_suite} -vendor {PANGO}`
  - `-components {fabric_ads fabric_compiler fabric_compiler_de fabric_configuration fabric_debugger fabric_inserter fabric_ipc fabric_pna fabric_ppc fabric_shell fabric_ta}`
  - `-expire_date {2026-11-03}`、`-host_id {F4A80DA47D72}`、`-num_lic {uncounted}`
- 另有 `D:\PDS23.2\PDS_2023.2-SP3-ads\PDS-0028F8405C9F.lic`（安装根，**未读取内容**）与 `D:\PDS23.2\License\tap-windows.exe` + `虚拟网卡设置MAC.pdf`。
- **有效期 2026-11-03** —— 本机 License 会过期，需留意。

### 1.4 `pds_shell.exe` 真的能启动（本机实测原始输出）

执行时间 `2026-09-22 13:34:11 ~ 13:34:14`，工作目录 `D:\ziguang\tmp\pds_probe\`，四次尝试**全部在 4 秒内返回，退出码 0**，全程无超时、无失败：

**① `pds_shell.exe -h`（可用）**
```
H: pds_shell : Fabric Compiler Shell (Version 2023.2-SP3 build 154097)
    [ -help  ]                       Turn on to print this message
    [ -file string ]                 Specifying a project script file to run batch mode
    [ -project string ]              Specifying a project file to run batch mode
    [ -work_dir string ]             Specifying the work directory
    [ -project_name string ]         Specifying the output project name
    [ -run string ]                  Specifying the cmd action needs to run to
    [ -version  ]                    Print version
    [ -skip_actions { string string ... } ]
        Specify actions that do not need to be run.
        The optional effective actions are "report_power" and "gen_netlist".
    [ -project_file_path string ]    Specifying a project file to run batch mode

Executing : pds_shell -help successfully.
```

**② `pds_shell.exe --help`（不认，但回落打印同一份 help）**
```
E: Flow-0073: Option '--help' is not defined for command 'pds_shell'.
H: pds_shell : Fabric Compiler Shell (Version 2023.2-SP3 build 154097)
...
Executing : pds_shell -help successfully.
```

**③ `pds_shell.exe -version`（只输出一行）**
```
2023.2-SP3
```

**④ `echo "puts hello; exit" | pds_shell.exe`（Tcl 交互可跑）**
```
License checkout: fabric_shell from D:\PDS23.2\License\new_pds_F4A80DA47D72.lic
Compiling architecture definition.
hello
```

**附带实测副作用（重要）**：在空目录里启动 `pds_shell`，它会在**当前工作目录**建默认工程与日志：

| 触发方式 | 在 cwd 生成 |
|---|---|
| 管道喂 stdin | `impl.pds`（3,312 B）+ `run.log` |
| `-file cmds.tcl` | `cmds.pds`（3,312 B，**名字跟随脚本名**）+ `run.log` |

默认工程内容（`tmp\pds_probe\impl.pds:1-20`）：`(_flow fab_demo "2023.2-SP3")`，器件默认
`PGL12G / -5 / FBG256` —— **不是 PGL50H**。

- `-project` / `-work_dir` / `-project_name` / `-run` / `-skip_actions` 的**批处理语义未实测**（未确认；只核实了 `-help` 里存在这些选项）。
- `close_project`、`new_project`、`create_project` **不存在**（实测 `invalid command name "close_project"` / `"new_project"`）。

### 1.5 Tcl 命令规模

实测 `llength [info commands]` = **226**。（与 `reports/pds_pds文件改动核查_20260920.md:104` 的"可用命令 226 个"一致。）

---

## 2. 从 RTL 到上板的完整阶段表

### 2.1 `bin\impl.tcl` 到底是什么

`D:\PDS23.2\PDS_2023.2-SP3-ads\bin\impl.tcl` **只有 3 行**（全部内容）：

```tcl
#Generated by Fabric Compiler ( version 2023.2-SP3 <build 154097> ) at Sun Sep 20 22:55:59 2026

report_power
```

它是 **2026-09-20 22:55 那次 MCP 调用留下的"回放记录"**（同一时刻 `bin\flow.log`、`bin\run.log` 也被写在这个目录）。

**结论：`impl.tcl` 不是 PDS 的输入，而是 PDS 的输出**——GUI/`pds_shell` 每执行一次动作，就把对应 Tcl 命令**追加**（旧版是覆盖）写到当前工作目录的 `impl.tcl`。真正的权威流程记录在**工程目录**：

`pds_ov5640\10_HDMI_DDR3_OV5640_test\impl.tcl`（143 行，5,401 B），头部：
`#Generated by Fabric Compiler ( version 2022.1 <build 99559> ) at Wed Mar 29 15:53:12 2023`

它记录了 14 组重复的流程历史，其中**两种等价写法**都出现过：

```tcl
# 早期（行 25-31）—— 一体式
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module hdmi_ddr_ov5640_top
synthesize -ads -selected_syn_tool_opt 2
dev_map
pnr
report_timing
gen_bit_stream

# 后期（行 117-125）—— 三段式 + 显式配置时钟
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module {hdmi_ddr_ov5640_top}
synthesize -ads -selected_syn_tool_opt 2
dev_map
place
route
route_optimize
report_timing
gen_bit_stream -master_configuration_clock_frequency {40M}
```

> 注意：`impl.tcl` 里的 `add_design` 路径是原作者机器上的 `C:/Users/w/Desktop/...`（行 3-24），
> **不能直接重放**（路径已失效）。重放前必须改用本机路径。

### 2.2 阶段表（Tcl 命令 ↔ GUI "Run" 阶段名 ↔ 产物 ↔ 判据）

GUI 的阶段显示名取自 `pds.log` / `logbackup\pds_2026-09-18-18-35-10.log` 里的
`Process "<名字>" started.` / `done.`；`.pds` 工程里的任务名取自
`HDMI_DDR3_OV5640_test.pds` 的 `_task` / `_command` 结构。

| # | GUI 阶段名 | `.pds` 任务/命令 | Tcl 命令 | 输入 | 输出目录 / 关键文件 | 通过判据（实测原文） |
|---|---|---|---|---|---|---|
| 0 | *Setup* | `tsk_setup` / `wgt_select_arch` | `set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484` | — | `.pds` | `Executing : set_arch ... successfully.`（`bin\run.log:11`） |
| 1 | *Setup* | `tsk_setup` / `wgt_my_design_src`、`wgt_my_ips_src` | `add_design <x.v>` / `add_design <x.idf>` / `add_constraint <x.fdc>` | RTL + IP(`.idf`) + 约束 | `.pds` 登记表 | — |
| 2 | **Compile** | `tsk_compile` / `cmd_compile` | `compile -top_module <top>` | 上表文件 | `compile\`（`*_comp.adf`、`cmr.db`、`formal.pvf`） | 无 `E:` 级错误；`error_info.txt` 为 0 字节（实测 0 B） |
| 3 | **Synthesize** | `tsk_synthesis` / `cmd_synthesize` | `synthesize -ads -selected_syn_tool_opt 2` | `compile\` DB | `synthesize\`（`*_syn.adf`、`*_syn.netlist`、`*_syn.vm`、`snr.db`、`.ccr`） | `Mapping Summary` 出现；`run.log` 无 `E:` |
| 4 | **Device Map** | `tsk_devmap` / `cmd_devmap` | `dev_map` | `synthesize\` DB + `.fdc`（映射引脚） | `device_map\`（`*_map.adf`、`dmr.db`、`*.pcf`、`*_dmr.prt`） | `Design 'x' has been successfully mapped to architecture-specific objects.`（`device_map\run.log:4935`） |
| 5 | **Place** | `tsk_pnr` / `cmd_place` | `place` | `device_map\` DB | `place_route\`（`*_plc.adf`、`plr.db`、`*.plr`、`*_prr_place.prt`） | `Placement done`；`Design Utilization` 打印 |
| 6 | **Route** | `tsk_pnr` / `cmd_route` | `route` | 布局 DB | `place_route\`（`*_route.adf`、`*_route.netlist`、`rur.db`、`*.rur`） | `Routing done.`（`place_route\run.log:1062`） |
| 7 | **Route Optimize** | `tsk_pnr` / `cmd_route_optimize` | `route_optimize` | 布线 DB | `place_route\`（`*_pnr.adf`、`*_route_optimize.netlist`、`ror.db`、`*.ror`） | `Design 'x' has been placed and routed successfully.`（`place_route\run.log:1119`） |
| 5-7 合并写法 | **Place & Route** | `cmd_pnr` | `pnr`（可用 `-place_only`） | 同上 | 同上 | 同上 |
| 8 | **Report Timing** | `tsk_pnr` / `cmd_report_post_pnr_timing` | `report_timing` | `place_route\*_pnr.adf` | `report_timing\`（`*.rtr`、`*_exception.rtr`、`rtr.db`、`*_rtp.adf`） | **`Design Summary : All Constraints Met.`**（`report_timing\hdmi_ddr_ov5640_top.rtr:74`） |
| 9 | **Generate Bitstream** | `tsk_gen_bitstream` / `cmd_gen_bitstream` | `gen_bit_stream -master_configuration_clock_frequency {40M}` | `place_route\*_pnr.adf` | `generate_bitstream\`（`.sbit`、`.smsk`、`bgr.db`、`.bgr`） | `The bitstream file is "...\<top>.sbit"` + `Generating Programming File done.`（`generate_bitstream\run.log:19-21`） |
| 10 | **Report Power** | `tsk_pnr` / `cmd_report_power` | `report_power` | `pnr` DB | `report_power\`（`.ppr`、`.pps`、`.ppf`、`ppr.db`） | `Report Power successfully.`（`report_power\run.log:20`） |
| 11 | **Gen Netlist** | `tsk_pnr` / `cmd_gen_netlist` | `gen_netlist`（可 `-func_sim_only` / `-sdf_annotate` / `-process_corner`） | 同上 | （本工程未跑） | 未确认 |
| 12 | 下载 | — | **非 Tcl**：`cdt_cfg.exe` + `cdt_js.exe` | `.sbit`（SRAM）/ `.sfc`（Flash） | `log\configuration.log`、`cfg_verify_result.sbit` | `COMMAND[Program] execute successfully`、`The done bit is 1`（`log\cfg.log:21-22`） |

### 2.3 实测耗时基线（同一设计、同一台机器，共 3 轮多种子运行）

`logbackup\pds_2026-09-18-18-35-10.log` 的 `Action from compile to <action>: Total Real Time elapsed`：

| 阶段 | 累计 Real Time |
|---|---|
| compile | 0h:00m:11s |
| synthesize | 0h:00m:36s |
| dev_map | 0h:00m:43s |
| place | 0h:01m:07s |
| route | 0h:01m:28s |
| route_optimize | 0h:01m:45s |
| report_timing | 0h:01m:53s |
| gen_bit_stream | 0h:02m:05s |

→ **全流程约 2 分钟**。单步 `report_power` 约 7 s（`report_power\run.log:21`，峰值内存 617 MB）；
`gen_bit_stream` 约 10 s（峰值 717 MB）。

### 2.4 各命令实测选项（`pds_shell.exe -file cmds.tcl` 抓取，2026-09-22）

- `set_arch`：`-family` `-device` `-package` `-speedgrade` `-input_db_file`
- `add_design`：`-library`（默认 `work`）、`-define`、`-copy`、`-of_rm`；位置参数 `input_filename`（**一次一个文件**）
- `add_constraint`：`-copy` + 位置参数
- `compile`：`-top_module` `-include_path` `-defined_parameters` `-compiler_directives` `-verilog_standard` `-loop_limit` `-fsm_compiler` `-force_to_run` `-of_flow` …
- `synthesize`：`-ads`（Pango 综合）/ `-synplify_pro` / `-frequency` / `-fsm_encoding` / `-resource_sharing` / `-retiming` / `-write_verilog` …
  → **`-selected_syn_tool_opt` 不在 `synthesize -help` 列表里**（含义未确认；`impl.tcl` 里原样出现 `2`）
- `dev_map`：`-packing_io`（IO 打拍）、`-detail`、`-override_pcf`、`-devmap_control_set_num` …
- `place` / `route` / `route_optimize` / `pnr`：三者的选项是并集关系（`pnr -help` 同时列出 place/route/route_optimize 三组选项）
- `pnr` 专属（多种子）：`-gplace_seed/-gplace_times/-seed_step/-parallel/-groute_seed/.../-filter/-sort/-timeout/-report_power/-generate_bitstream/-pick_first_timing_convergence_seed/-strategy`
  → 这解释了工程根目录的 **`multiseed_summary.csv`**（多种子汇总）
- `report_timing`：`-delay_type` `-nworst` `-max_path` `-input_pins` `-slack_greater_than` `-slack_less_than` `-clock_group_limit` `-report_max_skew` `-report_exception` `-ignore_db_version`
- `report_power`：`-tempgrade` `-process` `-model` `-junction` `-airflow` `-heatsink` `-output_ppr` `-output_pps` `-output_ppf` `-vcd` + 上百个电压项
- `gen_bit_stream`：**约 100 个选项**，关键的有
  `-create_bit_file`、`-create_bin_file`、`-create_mask_file`、`-master_configuration_clock_frequency`、
  `-system_clock_frequency`、`-usercode`、`-compress_bitstream`、`-write_drm_data`、`-unused_io_status`、
  `-enable_version_fallback` / `-version_fallback_ctrl`、`-encrypt_bitstream`、`-bitstream_security`、
  `-enable_watchdog_in_user_mode`、JTAG 引脚上下拉 `-tdi_pin/-tms_pin/-tck_pin/-tdo_pin` …
- `gen_netlist`：`-func_sim_only`、`-sdf_annotate`、`-process_corner`
- `open_project`：**只有位置参数** `project_file_path`（描述文字写成 "The input tcl file, which records the flow commands."）——**没有** `-project_file_path` 选项（虽然 `pds_shell` 自己有此命令行选项）
- `save_project`：无选项
- `show_device`：`-device <string>`（**必填**）、`-file`

> `E: Flow-0076: Option 'device' is required. It must be set.`（`bin\run.log:13`）就是
> `show_device` 漏给 `-device` 的真实报错。

---

## 3. 产出物字典（文件名 → 含义 → 是否入库/归档）

### 3.1 输入类（必须入库）

| 文件 | 含义 | 位置 | 归档 |
|---|---|---|---|
| `*.v` | 手写 Verilog | `source\rtl\`（17 个，`sources_info.log:1-52`） | ✅ 入库 |
| `*.idf` | **PDS IP 核配置**（DDR3 / PLL / 2×帧缓存），4 个 | `source\rtl\*\` | ✅ 入库 |
| `*.fdc` | **时序约束**（53,332 B / 975 行）。实测构成：`define_attribute` × 934、`create_clock` × 3、`create_generated_clock` × 10、`set_clock_uncertainty` × 5、`set_clock_groups` × 13 | 工程根 | ✅ 入库 |
| `*.pcf` | **引脚锁定（Post-Map）**，136 条 `def_port {sig} LOC=… VCCIO=… IOSTANDARD=…` | `device_map\` | ✅ 入库（引脚是设计契约） |

### 3.2 流程中间产物

| 文件 | 含义（依据） | 位置 | 格式 | 归档 |
|---|---|---|---|---|
| `*.pds` | 工程文件：源列表 + 器件 + 6 个 `_task` 状态 + **工件登记表** | 工程根 | s-expression | 备份，不入库 |
| `*.adf` | 各阶段设计数据库快照，**下一阶段的输入**。命名即阶段：`<top>_comp.adf`→`_syn.adf`→`_map.adf`→`_plc.adf`→`_route.adf`→`_pnr.adf`（PnR 输入给位流）；`report_timing` 另出 `<top>_rtp.adf` | 各阶段目录 | 二进制 | ❌ |
| `*.db`（`cmr.db`/`snr.db`/`dmr.db`/`plr.db`/`rur.db`/`ror.db`/`rtr.db`/`bgr.db`/`ppr.db`） | 各阶段报告的数据源，实测**均为 XML**（不是 SQLite） | 各阶段目录 | XML | ❌（`bgr.db` 可读，含全部位流设置，排错有用） |
| `.cmr` / `.snr` / `.dmr` / `.plr` / `.rur` / `.ror` / `.rtr` / `.bgr` | 各阶段**人读报告**，头部统一为 `Generated by Fabric Compiler ( version 2023.2-SP3 <build 154097> ) at …`。实测起始句：`.plr`→`Placement started.`；`.rur`→`Routing started.`；`.ror`→`Route Optimize started.`；`.rtr` 含完整时序表 | 各阶段目录 | 文本/混合 | 只抽摘要 |
| `*_timing_summary_after_hold_fix.txt` | 各时钟 WNS/WHS/TNS/THS 汇总表（Setup/Hold/Recovery/Removal/PulseWidth × Slow/Fast 角），首行 `Design Summary : All Constraints Met.` | `place_route\` | 文本 | ✅ **归档（验收依据）** |
| `*_prr_{place,route,route_optimize}.prt`、`*_dmr.prt` | **引脚报告**（pin report）。列：`pin \| site \| bank \| function \| net \| direction \| used`；device_map 阶段的 6 列版还没有网表信息 | `device_map\`、`place_route\` | 文本 | 可归档 |
| `*.netlist` | 网表（文本，首行 `Port…`），route 阶段两份 | `place_route\` | 文本 | ❌ |
| `*.ccr` | 约束检查结果（`##### Written on … #####`），`constraint_check.ccr` + `<top>.ccr` | `synthesize\` | 文本 | 摘要归档 |
| `formal.pvf` | 工具内部验证模型，头部是工具 build 信息 | `compile\`/`synthesize\`/`device_map\` | 文本 | ❌ |
| `apm_drm_lutram_utilization.log` | **RAM/ROM 映射明细**（哪个实例映射成 `GTP_DRM18K`/`GTP_DRM9K`/`GTP_RAM16X1DP`） | `synthesize\` | 文本 | ✅ 有用 |
| `multiseed_summary.csv` | 多种子汇总：单种子时序/线长/CPU 时间 + **Device Map 资源占用** + 综合性能 | 工程根 | CSV | ✅ |
| `run.log`、`pds.log`、`sources_info.log`、`flow.log` | 阶段日志。`sources_info.log` = **文件清单 + 大小 + 时间戳**（判断"改了哪些源"最快） | 各阶段目录 + 工程根 | 文本 | 只留最近一次 |
| `logbackup\`、`bak\`、`constraint_backup\` | 工具的自动备份（`constraint_backup\` 保留 8 份 `.fdc` 历史） | 各目录 | — | 只留需要的 |

### 3.3 位流类（重点核实）

`generate_bitstream\` 实测内容（2026-09-18 那次全流程 + 2023 年遗留）：

| 文件 | 大小 | MD5 | 实测定性 |
|---|---|---|---|
| `hdmi_ddr_ov5640_top.sbit` | 2,101,696 | `85D9D3F927B907D7237A7D285D24EDAB` | **最终烧写文件**。头部 ASCII：`PANGO MICROSYSTEMS, INC.` + `hdmi_ddr_ov5640_top` + `Logos-PGL50H--6-FBG484` + `09/18/26 17:53:11` + `Fabric Compiler 2023.2-SP3<154097>` |
| `OV5640_CMOS1_720P30.sbit` | 2,101,696 | `85D9D3F9…`（**与上一行完全相同**） | 人工改名副本（CMOS1 配置对应的那份） |
| `OV5640_CMOS2_720P30.sbit` | 2,101,696 | `B6CE4A73DDE19AE3909E06EB8726325F` | 另一次生成的副本 |
| `hdmi_ddr_ov5640_top.smsk` | 2,101,696 | `1BB8E5143A0260F45DFB56A920C583B5` | **掩码文件**（`gen_bit_stream -create_mask_file` / `bgr.db` 的 `Create Mask File = true`）。与 `.sbit` 同大小但内容不同 |
| `OV5640_CMOS1_720P30.smsk` | 2,101,696 | `1BB8E514…`（同上） | 同上 |
| `hdmi_ddr_ov5640_top.sfc` | 2,101,696 | `5649164C1734508DE567F92C9E4B82BD` | **串行配置 Flash 烧写文件**。头部与 `.sbit` 同格式，但是 **2022.1<99559> / 2023-03-30 10:26:04** 生成的（当前 2023.2-SP3 流程**没有**重新生成）。依据：`log\configuration.log:1512-1514` 选中它做 `Program Outer Flash`，并打印 `begin to check SFC File and Flash Device Read Mode.` |
| `hdmi_ddr_ov5640_top.bgr` + `bgr.db` | 1,695 / 11,010 | — | 位流生成记录：In/Out 清单 + `Flow Command: gen_bit_stream -master_configuration_clock_frequency {40M}` + CPU/内存 |
| `CMOS1.sbit`、`CMOS2.sbit` | 各 2,101,696 | — | 2023-03-30 遗留旧位流 |
| `cfg_verify_result.sbit` | **2,098,752** | `FC6691917B159F252B25809BE7FC7E07` | **不是位流**。位于**工程根**，由 JtagServer 的 `Verify` 操作产生（`log\configuration.log:1943-1966`，与文件时间戳 17:54:59 精确吻合）。实测**全文件 2,098,752 字节全为 0**（非零字节数 = 0）。该大小恰好等于器件原始配置镜像大小 —— 安装目录 `arch\...\cfgdata\Logos-PGL50H.mask` 也是 **2,098,752 B**（该 mask 有非零内容）。→（推断，依据：大小一致 + 全零 + 由 Verify 写出）它是**回读比对用的零缓冲/结果文件**，精确语义未确认 |

**明确回答：最终烧写文件是 `.sbit`，不是 `.bit`。**

- 全盘 `D:\ziguang` 下 **不存在任何 `*.bit`**（实测 `Get-ChildItem -Filter *.bit` 无结果）。
- `bgr.db` 里确有 `Create Bit File = true` 这一项，但产物扩展名是 `.sbit`（`bgr.db` 的 `Part` 行写明 `PGL50H-6FBG484`）。
- →（推断，依据：`gen_bit_stream -help` 的 `-create_bit_file` 选项 + `bgr.db` 的 `Create Bit File` 行 + 无 `.bit` 产物）**"Bit File" 是 PDS 对 `.sbit` 的称呼**，`.bit` 是其他厂商的习惯扩展名。

**`.sbit` / `.sfc` / `.smsk` 三者分工（核实结论）**

| 扩展名 | 用途 | 证据强度 |
|---|---|---|
| `.sbit` | JTAG **SRAM 在线下载**（掉电丢失） | ✅ 强：`log\cfg.log:20,27,34` `Finish program .../xxx.sbit` |
| `.sfc` | **外挂 QSPI Flash 固化**（掉电保留） | ✅ 强：`log\configuration.log:1512` 选中 `.sfc` → `20302 Erase Outer Flash` → `20301 Program Outer Flash` → `20303 Verify Outer Flash` |
| `.smsk` | **掩码文件**，`Verify`（回读比对）时按同名 `.sbit` 查找 | ✅ 强：`log\configuration.log:1824` `can not open mask file : .../OV5640_CMOS2_720P30.smsk` + `1825 Mask file does not exist in Verify Operation..` |
| `cfg_verify_result.sbit` | Verify 操作的输出，全零、大小 = 器件镜像大小 | ⚠️ 中（见上表，精确语义未确认） |

**是否入库建议**：`.fdc` / `.pcf` / `.idf` / 手写 `.v` **必须入库**；`.sbit` 建议按发布版本归档（约 2 MB/份）；
`.smsk` / `.sfc` / `.bgr` / `bgr.db` / 各阶段中间产物 **不入库**；时序与资源摘要（`.rtr` 摘录、`multiseed_summary.csv`、`*_timing_summary_after_hold_fix.txt`）**归档到 `reports/`**。

---

## 4. 操作红线（并发、备份、临时工程）

以下 1-4 条来自 `reports/pds_pds文件改动核查_20260920.md`，5-8 条是本次探测新增的实测证据。

### 红线 1：PDS GUI 打开同一工程时，**禁止**并发调用 MCP / `pds_shell`
依据该报告 §四.1：GUI 与 MCP Tcl 同时对同一 `.pds` 写入会产生竞争。
**正确做法：GUI 与 Tcl 串行使用**（关 GUI 再跑 Tcl，或反之）。

> 已发生过的真实事故：2026-09-20 22:55 通过 MCP 跑 `report_power` 后，
> `HDMI_DDR3_OV5640_test.pds` 被改写（26,242 B → 29,892 B，563 行 → 658 行）。
> 核查结论：**只动了工件登记表（bookkeeping），综合/布局/时序/位流产物时间戳与字节数完全未变**，
> `.fdc` 零改动，不需要重跑。回滚点 `HDMI_DDR3_OV5640_test.backup_1.pds`（26,242 B）存在但**不建议**用作回滚目标。

### 红线 2：MCP 每次调用都是**全新会话**，且**不加载目标工程的器件配置**
- `pds_mcp_server.py:29` — 每次调用执行 `pds_shell.exe -file <临时.tcl>`，`cwd = PDS_BIN_DIR`。
- 实测（本次探测）：空目录启动 `pds_shell` 会生成默认工程，器件是 **`PGL12G / -5 / FBG256`**
  （`tmp\pds_probe\impl.pds:13-16`；`bin\tmpXXXX.pds` 10 个文件同为 3,312 B 的这份模板）。
- **因此：任何依赖器件的命令前，必须显式 `set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484`**，
  否则按 PGL12G 解释设计。
- 也不能指望会话之间有状态残留（`close_project`/`new_project` 都**不存在**）。

### 红线 3：涉及工程文件写入的操作，**先备份 `.pds`**
带时间戳复制一份（如 `HDMI_DDR3_OV5640_test.backup_<日期>.pds`）再动手。

### 红线 4：`open_project` 会把 `pwd` 切到工程目录
后续相对路径据此解析 —— 脚本里要么在 `open_project` 之后一律用绝对路径，要么记住相对基准已变。

### 红线 5（新）：`pds_shell` 的**副作用目录 = 当前工作目录**，绝不要在工程目录/安装 `bin\` 里跑探测
实测在空目录里启动就会生成 `impl.pds`（或 `<脚本名>.pds`）+ `run.log`。
`bin\` 目录里现有 10 个 `tmpXXXX.pds`（各 3,312 B）、`impl.tcl`、`flow.log`、`run.log`，
**就是历史 MCP 探测的残留污染**（`pds_mcp_server.py:34` 把 `cwd` 设成 `bin\`）。
→ 探测一律在独立临时目录进行（本次用 `D:\ziguang\tmp\pds_probe\`）。

### 红线 6（新）：只读探测也会"写"
`report_power` 之类只读命令依然会：重写 `.pds` 登记表 + 刷新 `multiseed_summary.csv`
（两者时间戳都变成 22:56:00）+ 在 cwd 落 `impl.tcl` / `run.log` / `flow.log`。
**不要把"只读命令"当成"零副作用"。**

### 红线 7（新）：`-skip_actions` 只支持两个动作
`pds_shell -help` 原文：`The optional effective actions are "report_power" and "gen_netlist".`
不要指望用它跳过综合/布线。

### 红线 8（新）：License 会过期
`new_pds_F4A80DA47D72.lic` 的 `-expire_date {2026-11-03}`。到期后所有流程会失败，需提前换 License。

---

## 5. 实测资源占用

器件全称在本机文件中的**真实写法是 `PGL50H-6FBG484`**（`generate_bitstream\bgr.db` 的 `Part` 行），
位流头里是 `Logos-PGL50H--6-FBG484`（`.sbit` 头部 ASCII）。
> **`PGL50H-6IFBG484` 中的 "I"（工业级）在本机文件中未出现 → 未确认。** 全流程用到的器件串是
> `-family Logos -device PGL50H -speedgrade -6 -package FBG484`。

**总量**（取自本工程设计自己的报告，非手册）：

| 资源 | 总量 | 出处 |
|---|---|---|
| LUT | 42,800 | `synthesize\run.log:3511` |
| FF | 64,200 | `synthesize\run.log:3514` |
| DRM18K | 134 | `device_map\run.log:4911`；也见 `arch\...\Logos-PGL50H.ini:14` `(DrmCount 134)` |
| APM | 84 | `device_map\run.log:4904` |
| IO | 296 | `synthesize\run.log:3523` |
| PLL | 5 | `place_route\run.log:1105` |
| USCM | 30 | `place_route\run.log:1113` |
| RCKB | 24 | `place_route\run.log:1107` |
| HSST | **1**（报告里的计数单位，不是 4 路） | `place_route\run.log:1087` `Use of HSST \| 0 \| 1` |
| PCIE | **1**（计数单位） | `place_route\run.log:1103` `Use of PCIE \| 0 \| 1` |

> 「HSST 4 路 × 6.375 Gb/s」「PCIe Gen2 ×1」这两个**指标描述未从本机文件核实**（未确认）；
> 本机报告只能证明 HSST 与 PCIE 的计数各为 1。`doc\UG020007_Logos系列产品GTP用户指南_V1.5.pdf` 应含此信息，本次未读。

### 5.1 同一设计、三个阶段的**实际占用**（数字口径不同，必须注明来源）

设计：`hdmi_ddr_ov5640_top`（HDMI 收发 + DDR3 乒乓缓存 + 双 OV5640 采集），2026-09-18 全流程。

| 资源 | ① 综合后（估计） | ② Device Map 后 | ③ 布线后（真实） |
|---|---|---|---|
| LUT | **5,417** （12.66%，其中 72 作分布式 RAM、5,345 作逻辑） | **5,181**（13%） | **5,145**（= CLMA 3,039 + CLMS 2,106）（12%/13%） |
| FF | **5,412**（8.43%），Latch 0 | **5,237**（9%） | **5,025**（= 3,083 + 1,942）（8%） |
| DRM18K | **19.5**（14.55%） | **18.5**（14%） | **18.5**（14%） |
| APM | 0 | 0 | 0 |
| 分布式 RAM | 72（0.42%） | 72（1%） | 72（1%） |
| IO | **136** 端口（45.95%） | **125**（43%） | **125**（43%） |
| USCM | — | 8（27%） | 9（30%） |
| PLL | — | 3（60%） | 3（60%） |
| DLL / DQSL | — | 1 / 8 | 1（10%）/ 8（45%） |
| 唯一控制集 | 235 | — | — |
| 最大扇出 | 1806 | — | — |
| 来源文件 | `synthesize\run.log:3510-3528` | `device_map\run.log:4900-4928`；同值见 `multiseed_summary.csv:24-27` | `place_route\run.log:1066-1116` |

> **口径提醒**：①是综合器的 LUT6 计数，③把资源拆成 CLMA/CLMS 两个 tile 类型相加，
> 且 ③ 还统计 `BKCL 4/4`（100%）、`START 1/1`（100%）、`HARD0N1 431/6672`、`IOBD 11/64`、
> `IOBS_LR 101/161`（63%，最紧）、`IOBS_TB 10/56`、`IOBR_LR 2/7`。**引用时务必带上"来自哪个文件"。**

### 5.2 时序基线（`Design Summary : All Constraints Met.`）

**当前（2026-09-18 那次 PnR）** —— 来源 `report_timing\hdmi_ddr_ov5640_top.rtr:74-110`：

| 时钟 | Setup WNS (ns) | Hold WHS (ns) |
|---|---|---|
| `sys_clk` | 14.715 | 0.254 |
| `ddrphy_clkin` | 2.563 | 0.171 |
| `ioclk0` | **1.692** | 0.450 |
| `ioclk1` | **1.692** | 0.450 |
| `cmos1_pclk` | 9.231 | 0.202 |
| `cmos1_pclk_16bit` | 20.891 | 0.222 |
| `pix_clk` | 10.732 | 0.341 |
| `cfg_clk` | 94.571 | 0.212 |
| `sys_clk\|u_pll/u_pll_e3/CLKOUT2_Inferred` | 36.772 | 0.405 |

**历史（2023-03-30，2022.1 工具那次）** —— 来源 `place_route\hdmi_ddr_ov5640_top_timing_summary_after_hold_fix.txt`：
`sys_clk` 14.634 / 0.302，`ioclk0/ioclk1` 1.692 / 0.450，其余略高。

> ⚠️ `*_timing_summary_after_hold_fix.txt` **是 2023-03-30 的文件，2026-09-18 那次全流程没有重新生成它**
> （`place_route\` 目录里只有这一份，时间戳 2023/3/30 9:52:03）。当前时序结论请以
> `report_timing\hdmi_ddr_ov5640_top.rtr` 为准。
> 最紧的仍是 `ioclk0/ioclk1 = 1.692 ns`（DDR3 物理层接口）——不要在这条路上加逻辑。

### 5.3 功耗（`report_power`，2026-09-20 22:55 实测）

7 s 完成，峰值内存 617 MB，从 `pnr DB` 读设计，`I: The power model of the device is Production`。
结果（同 `reports/pds_pds文件改动核查_20260920.md:108-111`）：总片上 **1.052 W**（静态 0.215 W），
结温 **36.19 °C**，构成：**IO 0.735 W（69.8%）**、Net 0.035 W、CLM 0.031 W、Clock 0.022 W、DRM 0.014 W。
报告文件：`report_power\hdmi_ddr_ov5640_top.ppr`（80,013 B）/ `.ppf`（118,958 B）/ `.pps`（1,276 B，设置文件）。

---

## 6. JTAG / 下载与固化流程

### 6.1 实测到的下载器与链路

| 项 | 实测值 | 出处 |
|---|---|---|
| 下载器 | **`PANGO USB CABLE II`**（`Cable index 0:USB Cable II/fffffffffffffffe`） | `log\configuration.log:1884`、`log\cfg.log:13` |
| 驱动 | **D2XX DLL**（对应 `bin\ftd2xx.dll`） | `log\cfg.log:16` |
| 服务端 | `cdt_js.exe`（Fabric **JtagServer**），监听 **`127.0.0.1:65420`** | `log\js.log:7` `To connect this JtagServer instance use port : 65420` |
| 客户端 | `cdt_cfg.exe`（Fabric **Configuration**），通过 TCP 连 127.0.0.1:65420 | `log\cfg.log:3,9-10` |
| 识别到的器件 | `PGL50H` | `log\cfg.log:17,24,31` |
| JTAG IDCODE（扫描） | **`0x10521899`**（后续 4 个位置为 `0x0`，即单器件链） | `log\jtagserver.log:19-23` |
| 配置状态回读 | `This device configure situation (done bit): 1` | `log\cfg.log:18,25,32` |

> 日志 `Path:` 字段显示这些记录横跨 `D:/pango/PDS_2022.1/bin`（2023 年）与
> `D:\PDS23.2\PDS_2023.2-SP3-ads\bin`（2026 年）两套安装 —— 该日志是**跨版本累积**的。

### 6.2 SRAM 在线下载（掉电丢失）—— 烧 `.sbit`

实测命令序列（RPC over TCP，来自 `log\configuration.log`）：

| 顺序 | cmd id | cmd name | 说明 |
|---|---|---|---|
| 1 | 40004/40005 | `check version information` | 版本协商 |
| 2 | 40010/40011 | `get_cable_paras` | 取下载线参数（返回 Cable List） |
| 3 | 20001 | `Open config cable` | 打开线 + 扫描链，读回器件与 done bit |
| 4 | — | （前置检查）`begin to check mask file.` | 找同名 `.smsk` |
| 5 | **20002** | **`Program`** | 把 `.sbit` 写入 FPGA SRAM |
| 6 | **20004** | **`Verify`** | 回读比对；输出写 `cfg_verify_result.sbit` |

实测成功记录（`log\cfg.log:30-35`）：
```
PANGO USB CABLE II cable driver: D2XX DLL
PGL50H
This device configure situation (done bit): 1
COMMAND[Open config cable] execute successfully, takes 2.5 secs.
[2026.09.20 20:54:03]Finish program D:/.../generate_bitstream/OV5640_CMOS1_720P30.sbit
The done bit is 1
COMMAND[Program] execute successfully, takes 2.0 secs.
```
典型耗时：`Open config cable` 2~4 s（个别 61.9 s / 337.9 s 的离群值）、`Program` **2.0~2.2 s**、
`Verify` **3.0 s**。

**下载文件选择规则（实测）**：`set OpenLastPath: <某>.sbit`，紧接 `begin to check mask file.`
→ 它在**同目录找同名 `.smsk`**。找不到时（`log\configuration.log:1823-1825`）：
```
[Error] can not open mask file : D:/.../generate_bitstream/OV5640_CMOS2_720P30.smsk
[Warn]  Mask file does not exist in Verify Operation..
```
> 该 `.smsk` 现存（时间戳 17:40:46，早于 17:48:05 的报错），**报错的确切原因未确认**。

### 6.3 固化到外挂 QSPI Flash（掉电保留）—— 烧 `.sfc`

实测完整序列（唯一一次，2023-03-30 10:26，`log\configuration.log:1481-1605`）：

| 顺序 | cmd id | cmd name | 实测耗时 |
|---|---|---|---|
| 1 | 20001 | `Open config cable` | 3.4 s |
| 2 | **20300** | **`Scan Outer SPI Flash`** | 1.7 s（`Begin to initialize JtagFlash for selected FPGA Device...`） |
| 3 | — | 选文件 `.../hdmi_ddr_ov5640_top.sfc` + `begin to check SFC File and Flash Device Read Mode.` | — |
| 4 | **20302** | **`Erase Outer Flash`** | **11.4 s** |
| 5 | **20301** | **`Program Outer Flash`** | **33.2 s** |
| 6 | **20303** | **`Verify Outer Flash`** | 2.5 s |

**SRAM 下载 vs Flash 固化的关键区别（实测）**：

| | SRAM 下载 | QSPI Flash 固化 |
|---|---|---|
| 输入文件 | **`.sbit`** | **`.sfc`** |
| 辅助文件 | 同名 `.smsk`（Verify 用） | 无（SFC 文件已含 Flash 读模式信息） |
| 操作码 | 20001 → 20002 → 20004 | 20001 → 20300 → 20302 → 20301 → 20303 |
| 写入目标 | FPGA 内部 SRAM | 外挂 QSPI Flash |
| 掉电后 | **丢失**，需重新下载 | **保留**，上电自加载 |
| 耗时量级 | ~5 s | ~50 s（擦 11 s + 写 33 s + 校验 2.5 s） |

> **本工程的 `.sfc` 是 2023-03-30 用 2022.1 工具生成的，2026-09-18 的 2023.2-SP3 全流程没有再生成它**
> （`generate_bitstream\` 里只有一份 `.sfc`，时间戳 2023/3/30 10:26:44）。
> **在 GUI 里如何生成 `.sfc`（对应 `gen_bit_stream` 的哪个选项/GUI 勾选项）→ 未确认。**
> `gen_bit_stream -help` 的全部约 100 个选项里**没有**名字含 `sfc`/`flash` 的项（`-master_configuration_clock_frequency_in_read_back` 最接近但不是它）。
>
> **命令行烧写**：`cdt_cfg.exe` / `cdt_cfg_shell.exe` 是配置工具的可执行文件，
> 但其**命令行参数未实测**（未确认）。本次任务纪律要求只在临时目录做只读探测，且没有接板子，故未调用。

### 6.4 与 JTAG 无关但容易踩的坑

- GUI 里的下载界面属于 **Configuration**，**不产生** PDS 的阶段目录产物；它只写 `log\configuration.log`、`log\cfg.log`、`log\jtagserver.log`、`log\ins.log`，以及工程根的 `cfg_verify_result.sbit`。
- `log\js.log` 是每次 JtagServer 启动重写的短日志；`log\jtagserver.log`（150 KB）与 `log\configuration.log`（169 KB）是累积日志。

---

## 7. 未确认事项清单（不要当事实用）

1. **`PGL50H-6IFBG484` 里的 "I"（工业级）** —— 本机所有文件只写 `PGL50H-6FBG484` / `Logos-PGL50H--6-FBG484`。
2. **HSST "4 路 6.375 Gb/s"、PCIe "Gen2 ×1"** —— 本机报告只有计数 `HSST 1`、`PCIE 1`；速率/代数需查器件手册（`doc\` PDF 未读）。
3. **`synthesize -selected_syn_tool_opt 2` 的语义** —— 该选项不在 `synthesize -help` 列表内，只在 `impl.tcl` 里原样出现。
4. **GUI 里生成 `.sfc` 的操作路径** —— 未找到对应 Tcl 选项。
5. **`cdt_cfg.exe` / `cdt_cfg_shell.exe` 的命令行参数** —— 未实测。
6. **`cfg_verify_result.sbit` 的精确语义** —— 只确证：2,098,752 B 全零、由 `Verify`(20004) 写出、大小 == 器件 mask 大小（`Logos-PGL50H.mask`）。
7. **`pds_shell.exe -project` / `-run` / `-skip_actions` 的批处理行为** —— 只核实选项存在。
8. **`bin\helpDoc_pango.qch` 与 `doc\*.pdf` 的正文内容** —— 未读（需 GUI 帮助或 PDF 阅读器）。
9. **`OV5640_CMOS2_720P30.smsk` 存在却报 `can not open mask file` 的原因** —— 未确认。
10. **`-6` 速度等级之外是否有 `-6I` 之类的独立速度档** —— `arch\...\pgl50h\` 下只找到 `pgl50h_fbg484.eval`、`pgl50g_fbg484.eval`（二进制/加密），未解析出档位表。
11. **`license.rtf`、`PDS-0028F8405C9F.lic`（安装根的第二个 License）** —— 未读。
12. **`bin\run.log:7-11` 那次 MCP 调用（2026-09-20 22:55:53）的完整 Tcl 脚本** —— 只看到执行了 `open_project` → `set_arch` → `show_device`（报错）→ `report_power`。

---

## 8. 快速命令备忘（本机可直接跑）

```powershell
# 版本（最快，1 秒内返回）
& "D:\PDS23.2\PDS_2023.2-SP3-ads\bin\pds_shell.exe" -version      # -> 2023.2-SP3

# 帮助（列出所有命令行选项）
& "D:\PDS23.2\PDS_2023.2-SP3-ads\bin\pds_shell.exe" -h

# 跑一段 Tcl（★ 必须用独立的临时工作目录，否则会污染该目录）
Set-Location 'D:\ziguang\tmp\pds_probe'
& "D:\PDS23.2\PDS_2023.2-SP3-ads\bin\pds_shell.exe" -file '.\cmds.tcl'

# 某个 Tcl 命令的选项（在 Tcl 里）
#   <command> -help     例：gen_bit_stream -help / place -help / pnr -help
```

Tcl 里跑完整流程的最小骨架（**先 set_arch，再挂文件**）：

```tcl
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
add_design "<abs>/source/rtl/xxx_top.v"
add_design "<abs>/source/rtl/pll/pll.idf"
add_constraint "<abs>/xxx_top.fdc"
compile -top_module xxx_top
synthesize -ads -selected_syn_tool_opt 2
dev_map
place
route
route_optimize
report_timing
gen_bit_stream -master_configuration_clock_frequency {40M}
report_power
exit
```

> `-master_configuration_clock_frequency` 的**工具默认值是 `3.125M`**
> （`arch\vendor\pango\logos\pgl50h\data\config\ini_data\Logos-PGL50H.ini:45`），
> 本工程用的是 `40M`（`bgr.db`）。
> **不显式给就会按 3.125M 生成位流**，与板卡上电加载时序可能对不上。
> 该 .ini 里 40M 对应的编码是 `option0_data[5:0] = 5`（`Logos-PGL50H.ini:293-306` 给出全部档位映射）。
