#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
pinmap_query.py — 盘古50K(MES50HP/PGL50H-6IFBG484) 引脚库查询工具

数据源：同目录上级 reference/pinmap.csv
用法：
    python pinmap_query.py ddr3                 # 关键词模糊查（信号名/备注/外设域）
    python pinmap_query.py --domain hdmi_tx     # 按外设域精确列
    python pinmap_query.py --pin R17            # 反查：这个引脚上挂了什么（查冲突必备）
    python pinmap_query.py --dup                # 全局重复占用检查
    python pinmap_query.py --alias mem_dq       # 工程信号名 -> 原理图网络名 映射
    python pinmap_query.py --domains            # 列出所有域

退出码：0 正常；1 未找到；2 发现重复占用（--dup 时）
"""
import argparse
import csv
import os
import re
import sys

# ★ Windows 控制台默认 GBK，本脚本输出含 ℹ️/✅ 等符号，会抛
#   UnicodeEncodeError: 'gbk' codec can't encode character '\u2139'
#   实测 --dup 直接崩。这里强制 stdout/stderr 走 UTF-8；
#   reconfigure 在 Python 3.6 及以下不存在，故包在 try 里。
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

HERE = os.path.dirname(os.path.abspath(__file__))
CSV_PATH = os.path.join(HERE, os.pardir, "reference", "pinmap.csv")

# 工程/例程信号名  ->  原理图网络名（两侧都不是"错"，只是命名体系不同）
ALIAS = {
    "sys_clk": "FPGA_GCLK_50M",
    "mem_dq": "ddr3_dq",
    "mem_dqs": "ddr3_dqs_p",
    "mem_dqs_n": "ddr3_dqs_n",
    "mem_dm": "ddr3_dm",
    "mem_a": "ddr3_addr",
    "mem_ba": "ddr3_ba",
    "mem_ck": "ddr3_ck_p",
    "mem_ck_n": "ddr3_ck_n",
    "mem_cke": "ddr3_cke",
    "mem_cs_n": "ddr3_cs_n",
    "mem_ras_n": "ddr3_ras_n",
    "mem_cas_n": "ddr3_cas_n",
    "mem_we_n": "ddr3_we_n",
    "mem_odt": "ddr3_odt",
    "mem_rst_n": "ddr3_reset_n",
    "pix_clk": "HD_TX_PCLK",
    "vs_out": "HD_TX_VS",
    "hs_out": "HD_TX_HS",
    "de_out": "HD_TX_DE",
    "r_out": "HD_TX_D",
    "g_out": "HD_TX_D",
    "b_out": "HD_TX_D",
    "iic_tx_scl": "HDMI_TX_SCL",
    "iic_tx_sda": "HDMI_TX_SDA",
    "rstn_out": "HD_TX_RSTN",
    "hdmi_int_led": "HD_TX_INT",
    "cmos1_pclk": "CAM1_PCLK(扩展口/摄像头座，见 note)",
}

# 这些"信号"不是真实引脚占用，重复检查时忽略
IGNORE_DUP_SIGNALS = {"GND", "NC", "-", "", "\\", "地", "5V0", "A5V0", "A3V3", "VCCIN", "+5V", "+3.3V"}


def load():
    if not os.path.exists(CSV_PATH):
        sys.exit("找不到引脚库：%s" % os.path.normpath(CSV_PATH))
    rows = []
    with open(CSV_PATH, "r", encoding="utf-8-sig", newline="") as f:
        rd = csv.DictReader(f)
        for r in rd:
            r = {(k or "").strip(): (v or "").strip() for k, v in r.items()}
            if r.get("signal"):
                rows.append(r)
    return rows


def fmt(rows, show_domain=True):
    if not rows:
        return "（无匹配）"
    w = [max(len(str(r.get(c, ""))) for r in rows + [{c: c}]) for c in
         ("domain", "signal", "package_pin", "io_standard", "bank")]
    out = []
    for r in rows:
        cells = [str(r.get(c, "")) for c in ("domain", "signal", "package_pin", "io_standard", "bank")]
        if not show_domain:
            cells = cells[1:]
        line = "  ".join(c.ljust(n) for c, n in zip(cells, w[1:] if not show_domain else w))
        note = r.get("note", "")
        src = r.get("source", "")
        tail = ("   # " + note if note else "") + ("  [%s]" % src if src else "")
        out.append(line.rstrip() + tail)
    return "\n".join(out)


def norm_pin(p):
    return re.sub(r"\s+", "", p or "").upper()


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("keyword", nargs="*", help="信号名/备注/域 的模糊关键词（可多个，AND）")
    ap.add_argument("--domain", help="按外设域精确过滤（支持前缀匹配）")
    ap.add_argument("--pin", help="反查引脚：该引脚上挂了哪些信号")
    ap.add_argument("--dup", action="store_true", help="全局重复占用检查")
    ap.add_argument("--alias", nargs="?", const="", help="显示工程信号名->原理图网络名映射")
    ap.add_argument("--domains", action="store_true", help="列出所有域")
    ap.add_argument("--csv", action="store_true", help="输出 CSV 而非表格")
    a = ap.parse_args()

    rows = load()

    if a.domains:
        seen = {}
        for r in rows:
            seen[r["domain"]] = seen.get(r["domain"], 0) + 1
        for d, n in sorted(seen.items()):
            print("%-16s %4d 条" % (d, n))
        return 0

    if a.alias is not None:
        for k, v in sorted(ALIAS.items()):
            if not a.alias or a.alias.lower() in k.lower() or a.alias.lower() in v.lower():
                print("%-14s -> %s" % (k, v))
        return 0

    if a.dup:
        CONN = {"conn_j2", "conn_j3", "conn_j4", "conn_j5"}
        buckets = {}
        for r in rows:
            p = norm_pin(r["package_pin"])
            if not p or p == "-" or r["signal"].upper() in {s.upper() for s in IGNORE_DUP_SIGNALS}:
                continue
            buckets.setdefault(p, []).append((r["domain"], r["signal"], r.get("source", "")))
        # 只保留"信号名确实不同"的桶
        real, expected = [], []
        for p, v in sorted(buckets.items()):
            names = {x[1] for x in v}
            if len(names) < 2:
                continue
            doms = {x[0] for x in v}
            # 连接器 × 外设 = 核心板/底板同一物理网络的正常映射，不算冲突
            if len(doms - CONN) <= 1:
                expected.append((p, v))
            else:
                real.append((p, v))

        if expected:
            print("ℹ️ 以下 %d 个引脚在「核心板连接器」与「外设」之间重复 —— 属**同一物理网络**的正常映射，不是冲突：" % len(expected))
            for p, v in expected:
                print("  %-8s %s" % (p, "; ".join("%s/%s" % (d, s) for d, s, _ in v)))
            print()
        if not real:
            print("✅ 未发现真实的引脚冲突（不同外设抢同一引脚）")
            return 0
        print("⚠️ 发现 %d 个引脚被**不同外设**占用（需人工确认是复用还是冲突）：" % len(real))
        for p, v in real:
            print("  %-8s %s" % (p, "; ".join("%s/%s" % (d, s) for d, s, _ in v)))
        print("\n  说明：软复用（例程把 LED 当状态灯、HDMI 收发共用复位）是设计选择；")
        print("        若两个外设要同时工作却抢同一引脚，则是硬件冲突。")
        return 2

    if a.pin:
        target = norm_pin(a.pin)
        hit = [r for r in rows if norm_pin(r["package_pin"]) == target]
        print("引脚 %s ：" % target.upper())
        print(fmt(hit))
        return 0 if hit else 1

    sel = rows
    if a.domain:
        d = a.domain.lower()
        sel = [r for r in sel if r["domain"].lower().startswith(d)]
    for kw in a.keyword:
        k = kw.lower()
        sel = [r for r in sel
               if k in " ".join(r.get(c, "") for c in
                                ("domain", "signal", "package_pin", "io_standard", "bank", "note")).lower()]
    if not (a.domain or a.keyword):
        ap.print_help()
        return 0

    if a.csv:
        wr = csv.DictWriter(sys.stdout, fieldnames=list(rows[0].keys()))
        wr.writeheader()
        for r in sel:
            wr.writerow(r)
        return 0

    print(fmt(sel))
    print("\n共 %d 条" % len(sel))
    return 0 if sel else 1


if __name__ == "__main__":
    sys.exit(main())
