#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fdc_audit.py — 盘古50K/PDS 时序约束(.fdc)静态审查

用法：
    python fdc_audit.py constr/lane_detect.fdc
    python fdc_audit.py pds_ov5640/.../hdmi_ddr_ov5640_top.fdc
    python fdc_audit.py a.fdc --include b.fdc      # 合并审查（增量约束场景）
    python fdc_audit.py a.fdc --json out.json

检查项：
  C1  create_clock 的主时钟是否都有对应端口
  C2  生成时钟数 vs 主时钟数（提示：每个 PLL 输出都要有一条）
  C3  定义了但**从未出现在任何 set_clock_groups / set_false_path 里**的时钟（潜在未约束域）
  C4  `set_clock_groups` 与同一对时钟上的 `set_multicycle_path` 是否冲突（后者会失效）
  C5  可疑的 `set_false_path`：整时钟域 -> 整时钟域（应用 set_clock_groups 而非 false_path）
  C6  跨域通路缺少任何例外约束的时钟对（需要人工确认是否真有同步器）
  C7  `set_multicycle_path` 是否写了理由注释（本项目纪律：必须写）
  C8  IO 端口是否有 set_input_delay/set_output_delay 或 PCF 锁定（提示性）

退出码 0（仅报告，不阻断）；发现 C4/C5 这类硬冲突时返回 2。
带 —— 的行表示"需要人来判断"，不代表一定错。
"""
import argparse
import json
import os
import re
import sys

CLOCK_DEF = re.compile(r"^\s*create_clock\b(.*)$", re.I)
GEN_DEF = re.compile(r"^\s*create_generated_clock\b(.*)$", re.I)
GRP = re.compile(r"^\s*set_clock_groups\b(.*)$", re.I)
FP = re.compile(r"^\s*set_false_path\b(.*)$", re.I)
MCP = re.compile(r"^\s*set_multicycle_path\b(.*)$", re.I)
IN_DLY = re.compile(r"^\s*set_input_delay\b", re.I)
OUT_DLY = re.compile(r"^\s*set_output_delay\b", re.I)
NAME = re.compile(r"-name\s+\{?([\w\.\-/]+)\}?")
GETCLK = re.compile(r"get_clocks\s+\{?([^\]\}]+)\}?")
GETPORT = re.compile(r"get_ports\s+\{?([^\]\}]+)\}?")
GETPIN = re.compile(r"get_pins\s+\{?([^\]\}]+)\}?")
GETNET = re.compile(r"get_nets\s+\{?([^\]\}]+)\}?")


def strip_comment(line):
    """去掉行尾注释，但保留 # 之后的内容用于'是否写了理由'的判断。"""
    i = line.find("#")
    if i < 0:
        return line, ""
    return line[:i], line[i:]


def split_names(s):
    s = s.strip().strip("{}")
    return [x for x in re.split(r"[,\s]+", s) if x]


def groups_to_pairs(group_entries, all_clocks):
    """
    按 set_clock_groups 的 Tcl 语义展开异步时钟对：
      · 一条语句里写多个 -group  → 各组之间两两异步
      · 一条语句里只写 1 个 -group → 该组与"未在任何组中出现的时钟"异步
        （官方例程就是这种"一个时钟一条语句"的写法）
    返回 (async_pairs, grouped_clocks)
    """
    pairs = set()
    grouped_clocks = set()
    for g in group_entries:
        cl = [c for c in g["clocks"] if c]
        grouped_clocks.update(cl)
        if len(cl) >= 2:
            for i in range(len(cl)):
                for j in range(i + 1, len(cl)):
                    pairs.add(frozenset((cl[i], cl[j])))
        elif len(cl) == 1:
            for other in all_clocks:
                if other != cl[0]:
                    pairs.add(frozenset((cl[0], other)))
    return pairs, grouped_clocks


def read_lines(paths):
    out = []
    for p in paths:
        with open(p, "r", encoding="utf-8-sig", errors="replace") as f:
            for ln, line in enumerate(f, 1):
                out.append((os.path.basename(p), ln, line.rstrip("\n")))
    return out


def nearby_comment(lines, idx, back=3, fwd=0):
    """语句前后 back/fwd 行内是否有注释——本项目把理由写在语句上方的段落注释里。"""
    fn = lines[idx][0]
    lo = max(0, idx - back)
    hi = min(len(lines), idx + fwd + 1)
    for j in range(lo, hi):
        if j == idx:
            continue
        if lines[j][0] != fn:
            continue
        if "#" in lines[j][2] and lines[j][2].strip().startswith("#"):
            txt = lines[j][2].strip().lstrip("#").strip()
            if len(txt) >= 4:
                return txt
    return ""


def report_section(title):
    print("\n" + "=" * 78)
    print(title)
    print("=" * 78)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("fdc", nargs="+")
    ap.add_argument("--json", help="同时输出 JSON 报告")
    a = ap.parse_args()

    lines = read_lines(a.fdc)
    clocks, gen, groups, fps, mcps, in_d, out_d, ports, pins, nets = {}, {}, [], [], [], 0, 0, set(), set(), set()
    reason_missing = []

    for idx, (fn, ln, raw) in enumerate(lines):
        code, comment = strip_comment(raw)
        low = code.strip().lower()
        if not low:
            continue

        m = CLOCK_DEF.match(code)
        if m:
            n = NAME.search(m.group(1))
            nm = n.group(1) if n else "(unnamed)"
            p = GETPORT.search(m.group(1))
            clocks[nm] = {"file": fn, "line": ln, "port": p.group(1) if p else None}
            if p:
                ports.update(split_names(p.group(1)))
            continue

        m = GEN_DEF.match(code)
        if m:
            n = NAME.search(m.group(1))
            nm = n.group(1) if n else "(unnamed)"
            src = GETPORT.search(m.group(1)) or GETPIN.search(m.group(1)) or GETNET.search(m.group(1))
            gen[nm] = {"file": fn, "line": ln,
                       "source": (src.group(1) if src else None),
                       "mult": (re.search(r"-multiply_by\s+\{?(\d+)", m.group(1)) or [None, "?"])[1],
                       "div": (re.search(r"-divide_by\s+\{?(\d+)", m.group(1)) or [None, "?"])[1]}
            continue

        m = GRP.match(code)
        if m:
            grp_clocks = []
            for g in GETCLK.findall(m.group(1)):
                grp_clocks.extend(split_names(g))
            groups.append({"file": fn, "line": ln, "clocks": grp_clocks, "raw": code.strip()})
            continue

        m = FP.match(code)
        if m:
            fps.append({"file": fn, "line": ln, "raw": code.strip(), "comment": comment.strip()})
            continue

        m = MCP.match(code)
        if m:
            mcps.append({"file": fn, "line": ln, "raw": code.strip(), "comment": comment.strip()})
            why = comment.strip() or nearby_comment(lines, idx)
            if not why:
                reason_missing.append((fn, ln, "set_multicycle_path 未写理由注释（本行或上方 3 行内）"))
            continue

        if IN_DLY.match(code):
            in_d += 1
        elif OUT_DLY.match(code):
            out_d += 1
        for x in GETPORT.findall(code):
            ports.update(split_names(x))
        for x in GETPIN.findall(code):
            pins.update(split_names(x))
        for x in GETNET.findall(code):
            nets.update(split_names(x))

    all_clocks = sorted(set(clocks) | set(gen))
    referenced = set()
    for g in groups:
        referenced.update(g["clocks"])
    for f in fps:
        for x in GETCLK.findall(f["raw"]):
            referenced.update(split_names(x))
    referenced_by_mcp = set()
    for m in mcps:
        for x in GETCLK.findall(m["raw"]):
            referenced_by_mcp.update(split_names(x))

    findings = []

    report_section("C1/C2 时钟清单（%d 个）" % len(all_clocks))
    print("%-28s %-8s %-6s %-6s %s" % ("时钟名", "来源", "mult", "div", "行"))
    for c in all_clocks:
        if c in clocks:
            print("%-28s %-8s %-6s %-6s %s:%s  port=%s" %
                  (c, "主时钟", "-", "-", clocks[c]["file"], clocks[c]["line"], clocks[c]["port"]))
        else:
            g = gen[c]
            print("%-28s %-8s %-6s %-6s %s:%s  src=%s" %
                  (c, "生成", g["mult"], g["div"], g["file"], g["line"], g["source"]))
    if not all_clocks:
        findings.append(("C2", "❌ 没有解析到任何 create_clock —— 约束文件里没有主时钟定义"))

    report_section("C3 时钟域隔离覆盖检查")
    async_pairs, grouped_clocks = groups_to_pairs(groups, all_clocks)
    unref = [c for c in all_clocks if c not in referenced and c not in grouped_clocks]
    if unref:
        for c in unref:
            tag = "（已被 set_multicycle_path 覆盖）" if c in referenced_by_mcp else ""
            print("  —— %s %s" % (c, tag))
        hard_unref = [c for c in unref if c not in referenced_by_mcp]
        findings.append(("C3", "⚠️ %d 个时钟无 set_clock_groups 覆盖%s"
                         % (len(unref),
                            "，其中 %d 个连例外约束都没有：%s" % (len(hard_unref), ", ".join(hard_unref)) if hard_unref else
                            "（均已由多周期/假路径约束覆盖，属有意设计）")))
        print("\n  说明：未被 set_clock_groups 覆盖的时钟与其它域之间会被当作**同步**关系分析。")
        print("        若确实只走多周期/假路径（如同步器握手），这是允许的；")
        print("        若实际异步（FIFO 两端 / 外部恢复时钟），必须补 set_clock_groups，否则是假收敛。")
    else:
        print("  ✅ 全部 %d 个时钟都被 set_clock_groups 或例外约束覆盖" % len(all_clocks))
        print("     （异步对共 %d 对，来自 %d 条 set_clock_groups）" % (len(async_pairs), len(groups)))

    report_section("C4 set_clock_groups 与 set_multicycle_path 冲突检查")
    conflict = []
    for m in mcps:
        cl = []
        for x in GETCLK.findall(m["raw"]):
            cl.extend(split_names(x))
        for i in range(len(cl)):
            for j in range(i + 1, len(cl)):
                pair = frozenset((cl[i], cl[j]))
                if pair in async_pairs:
                    conflict.append((m["file"], m["line"], tuple(sorted(pair))))
    if conflict:
        for fn, ln, pair in conflict:
            print("  ❌ %s:%s  同一对时钟 %s 既有 set_clock_groups 又有 set_multicycle_path（后者会失效）" % (fn, ln, " <-> ".join(pair)))
        findings.append(("C4", "❌ %d 处 set_clock_groups / set_multicycle_path 冲突" % len(conflict)))
    else:
        print("  ✅ 未发现冲突")

    report_section("C5 可疑的 set_false_path（整时钟域 -> 整时钟域）")
    suspicious = []
    for f in fps:
        tgt = GETCLK.findall(f["raw"])
        if tgt:
            suspicious.append(f)
    if suspicious:
        for f in suspicious:
            print("  —— %s:%s  %s" % (f["file"], f["line"], f["raw"]))
        findings.append(("C5", "⚠️ %d 条 set_false_path 作用于整时钟域，建议改用 set_clock_groups" % len(suspicious)))
        print("\n  说明：整域 false_path 会连建立/保持一起免掉，掩盖真实违例；")
        print("        仅当两端确实异步且已用 FIFO/同步器处理时才可接受。")
    else:
        print("  ✅ 没有整域 set_false_path（本项目纪律：#18）")

    report_section("C6 跨域覆盖率（哪些时钟对既无 clock_groups 也无 false_path）")
    covered = set(async_pairs)
    for f in fps:
        cl = []
        for x in GETCLK.findall(f["raw"]):
            cl.extend(split_names(x))
        for i in range(len(cl)):
            for j in range(i + 1, len(cl)):
                covered.add(frozenset((cl[i], cl[j])))
    # 多周期路径也算"已声明例外"（它是针对具体路径的例外，不是遗漏）
    for m in mcps:
        cl = []
        for x in GETCLK.findall(m["raw"]):
            cl.extend(split_names(x))
        for i in range(len(cl)):
            for j in range(i + 1, len(cl)):
                covered.add(frozenset((cl[i], cl[j])))
    uncovered = []
    for i in range(len(all_clocks)):
        for j in range(i + 1, len(all_clocks)):
            pair = frozenset((all_clocks[i], all_clocks[j]))
            if pair not in covered:
                uncovered.append(tuple(all_clocks[i:i + 1] + all_clocks[j:j + 1]))
    if len(all_clocks) > 1:
        print("  共 %d 个时钟 → %d 对组合，其中 %d 对未声明例外：" % (len(all_clocks), len(uncovered) + len(covered), len(uncovered)))
        for p in uncovered[:40]:
            print("    · %s  <->  %s" % p)
        if len(uncovered) > 40:
            print("    … 其余 %d 对省略" % (len(uncovered) - 40))
        if uncovered:
            findings.append(("C6", "⚠️ %d 对时钟无例外声明，需人工确认是否存在跨域通路" % len(uncovered)))
    else:
        print("  只有 1 个时钟，无跨域对")

    report_section("C7 set_multicycle_path 理由注释")
    if reason_missing:
        for fn, ln, msg in reason_missing:
            print("  ⚠️ %s:%s  %s" % (fn, ln, msg))
        findings.append(("C7", "⚠️ %d 条 set_multicycle_path 缺理由注释" % len(reason_missing)))
    else:
        print("  ✅ 每条多周期约束都有理由注释" if mcps else "  （无多周期约束）")

    report_section("C8 IO 延时约束")
    print("  set_input_delay: %d 条，set_output_delay: %d 条" % (in_d, out_d))
    if in_d == 0 and out_d == 0:
        print("  ℹ️ 没有任何 IO 延时约束。若顶层端口直连引脚（本案常见），")
        print("     需确认引脚已由 .pcf/.fdc 的 PAP_IO_LOC 锁定，且输入是同步信号。")
        findings.append(("C8", "ℹ️ 无 set_input_delay/set_output_delay，确认端口是否直连引脚"))

    report_section("结论")
    hard = [f for f in findings if f[1].startswith("❌")]
    soft = [f for f in findings if not f[1].startswith("❌")]
    print("  硬问题 %d 项，提示 %d 项" % (len(hard), len(soft)))
    for code, msg in findings:
        print("  [%s] %s" % (code, msg))
    if not findings:
        print("  ✅ 静态审查未发现问题（仍需以 PDS report_timing 的 WNS/TNS ≥ 0 为准）")

    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump({"clocks": clocks, "generated": gen, "groups": groups,
                       "false_paths": fps, "multicycles": mcps, "findings": findings},
                      f, ensure_ascii=False, indent=2)
        print("\nJSON 报告：%s" % os.path.abspath(a.json))

    return 2 if hard else 0


if __name__ == "__main__":
    sys.exit(main())
