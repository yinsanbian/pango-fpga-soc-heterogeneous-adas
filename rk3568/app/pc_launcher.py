#!/usr/bin/env python3
"""PC 启动器：选视频 -> 上传 RK3568 -> 板端 RKNN 无窗口推理 -> PC 单路窗口。

界面只负责选文件和看日志；真正的流程：
  1. SSH/SCP 用本机 key 操作 user@RK3568；
  2. 把视频传到 ~/avm_board/input.<ext>；
  3. 板端 board_yolo_udp.py 等 PC 的 START；
  4. PC AVM3D 单路窗口绑定 7000 后发 START，板端开始推 OBJECT；
  5. PC 窗口显示 YOLO 框 + PC 车道/弯向。
"""
from __future__ import annotations

import argparse
import json
import os
import queue
import re
import shlex
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PY = ROOT / ".venv_gpu" / "Scripts" / "python.exe"
APP = ROOT / "dashboard" / "avm3d" / "app.py"
TRIPLE_APP = ROOT / "dashboard" / "avm3d" / "triple_app.py"
CALIB = ROOT / "dashboard" / "avm3d" / "calib" / "sim_calibration.json"
DEFAULT_KEY = Path.home() / ".ssh" / "codex_fpga_diag_20261019"
DEFAULT_VIDEO = ROOT / "交通场景数据集" / "video_20260929_113539.mov"
DEFAULT_HOST = "192.168.1.100"
DEFAULT_USER = "neardi"
DEPLOY_TAR = ROOT / "reports" / "board_deploy" / "avm_board.tar.gz"
BOARD_SCRIPT = ROOT / "rk_deploy" / "app" / "board_yolo_udp.py"
OUT_DIR = ROOT / "reports" / "launcher"
CTRL_PORT = 7002
META_PORT = 7000

# ---- FPGA 视频传输（前向->左格 CH2，后向->右格 CH3）----
# 链路：RK3568 eth1 (10.10.20.1/30) -> FPGA N1 (10.10.20.2, MAC 02:00:00:00:00:51)。
# 板端把 mp4 预转成 960x540 big-endian RGB565 原始帧，再用 send_raw.py 逐包节流发送。
FPGA_APP_DIR = ROOT / "rk_deploy" / "app" / "fpga"
FPGA_SEND_SCRIPT = FPGA_APP_DIR / "send_raw.py"
FPGA_PROTO_SCRIPT = FPGA_APP_DIR / "video_protocol.py"
FPGA_LOOP_SCRIPT = FPGA_APP_DIR / "send_loop.sh"
FPGA_BIND_IP = "10.10.20.1"
FPGA_TARGET_IP = "10.10.20.2"
FPGA_TARGET_MAC = "02:00:00:00:00:51"
FPGA_FRAME_BYTES = 960 * 540 * 2
FPGA_FPS_CAP = 40.0   # 实测 40 fps/通道 零丢弃；更高会触发 DDR 写入等待
FPGA_CAPTURE_DEVICE = 0
FPGA_CAPTURE_WIDTH = 1920
FPGA_CAPTURE_HEIGHT = 1080
FPGA_CAPTURE_FPS = 15.0
FPGA_CAPTURE_FOURCC = "MJPG"
FPGA_CAPTURE_CROP = "auto"   # 按实际采集帧取左上 1/4=front
FPGA_VIDEO_PORT = 7100
FPGA_ATLAS_VIDEO_PORT = 7200
FPGA_ATLAS_META_PORT = 7001
FPGA_ATLAS_WIDTH = 960
FPGA_ATLAS_HEIGHT = 540


def _local_ip(host: str) -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect((host, 22))
        return str(s.getsockname()[0])
    finally:
        s.close()


def _ssh_base(host: str, user: str, key: Path) -> list[str]:
    return ["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=8", "-i", str(key), f"{user}@{host}"]


def _scp_base(key: Path) -> list[str]:
    return ["scp", "-q", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=8", "-i", str(key)]


def _run(cmd: list[str], timeout: float = 120.0) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                          encoding="utf-8", errors="replace")


def _terminate_proc_tree(proc: subprocess.Popen | None, timeout_s: float = 5.0) -> None:
    """停止 PC 窗口；Windows 下杀整棵进程树，确保 7000/7002 端口释放。"""
    if proc is None or proc.poll() is not None:
        return
    try:
        if os.name == "nt":
            subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                           capture_output=True, text=True, timeout=10)
        else:
            proc.terminate()
    except Exception:  # noqa: BLE001
        pass
    try:
        proc.wait(timeout=timeout_s)
    except Exception:  # noqa: BLE001
        try:
            proc.kill()
        except Exception:  # noqa: BLE001
            pass


def _remote_size(ssh: list[str], remote_path: str) -> int | None:
    r = _run(ssh + [f"stat -c%s {shlex.quote(remote_path)} 2>/dev/null || true"], 15)
    raw = (r.stdout or "").strip().splitlines()
    return int(raw[-1]) if raw and raw[-1].isdigit() else None


def _remote_free_kb(ssh: list[str], remote_dir: str) -> int | None:
    r = _run(ssh + [f"df -Pk {shlex.quote(remote_dir)} | tail -1"], 15)
    cols = (r.stdout or "").split()
    return int(cols[3]) if len(cols) >= 4 and cols[3].isdigit() else None


def _remote_video_name(video: Path) -> str:
    st = video.stat()
    stem = re.sub(r"[^A-Za-z0-9_.-]+", "_", video.stem).strip("_")[:32] or "video"
    suffix = re.sub(r"[^A-Za-z0-9.]+", "", video.suffix.lower()) or ".mp4"
    return f"input_{stem}_{st.st_size}_{int(st.st_mtime)}{suffix}"


def _video_info(video: Path) -> tuple[float, int]:
    try:
        import cv2

        cap = cv2.VideoCapture(str(video))
        fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
        frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        cap.release()
        return (fps if 1.0 <= fps <= 120.0 else 0.0, max(frames, 0))
    except Exception:
        return 0.0, 0


def _video_fps(video: Path) -> float:
    return _video_info(video)[0]


def _quad_meta(paths: dict[str, Path], fps: float, frames: int,
               log) -> tuple[float, int]:
    infos = {name: _video_info(p) for name, p in paths.items()}
    front_fps = infos.get("front", (0.0, 0))[0]
    src_fps = front_fps or max((v[0] for v in infos.values()), default=0.0)
    if fps <= 0:
        pc_fps = max(src_fps, 30.0)
    else:
        pc_fps = float(fps)
    counts = [int(n) for _, n in infos.values() if n > 0]
    shortest = min(counts) if len(counts) == 4 else 0
    if shortest:
        total = int(min(frames, shortest)) if frames > 0 else int(shortest)
        log(f"四路同步长度 {total} 帧（最短通道 {shortest} 帧）")
    else:
        total = frames
        log("四路帧数未知，按运行帧数/文件结束处理")
    fps_values = [v[0] for v in infos.values() if v[0] > 0]
    if fps_values and max(fps_values) - min(fps_values) > 0.5:
        log(f"警告：四路源帧率不一致 {fps_values}；只能做视觉演示，不能声称同帧")
    for name, (f, n) in infos.items():
        log(f"  {name}: {f:.2f} fps / {n} 帧")
    return pc_fps, total


def _fpga_preflight(ssh: list[str], log) -> None:
    """检查 RK3568 -> FPGA 直连口：链路、地址、静态邻居。"""
    r = _run(ssh + ["cat /sys/class/net/eth1/carrier 2>/dev/null; "
                    "ip -4 -o addr show eth1 2>/dev/null; "
                    "ip neigh show dev eth1 2>/dev/null"], 15)
    out = (r.stdout or "").strip()
    if not out.startswith("1"):
        raise RuntimeError("板端 eth1 链路未连接（carrier=0）；请确认网线插在 FPGA 直连口")
    if "10.10.20.1" not in out:
        raise RuntimeError("板端 eth1 缺少 10.10.20.1/30 地址；先在板端配置直连地址")
    if "10.10.20.2" not in out:
        add = (f"ip neigh replace {FPGA_TARGET_IP} lladdr {FPGA_TARGET_MAC} dev eth1")
        r2 = _run(ssh + [f"{add} 2>/dev/null || sudo -n {add} 2>/dev/null || true; "
                         "ip neigh show dev eth1"], 15)
        if FPGA_TARGET_IP in (r2.stdout or ""):
            log(f"已补写 FPGA 静态邻居 {FPGA_TARGET_IP} -> {FPGA_TARGET_MAC}")
        else:
            log(f"警告：缺少静态邻居 {FPGA_TARGET_IP}，发送可能不通（需 root 配置）")
    log("FPGA 直连链路 OK：eth1 carrier=1，10.10.20.1 -> 10.10.20.2")


def _fpga_convert(ssh: list[str], remote_mp4: str, remote_raw: str, frames: int,
                  log) -> int:
    """板端 ffmpeg 预转 960x540 big-endian RGB565；0=全片，缓存按源帧数校验。"""
    expected = max(int(frames), 0)
    if expected <= 0:
        probe = _run(ssh + [
            f"ffprobe -v error -select_streams v:0 "
            f"-show_entries stream=nb_frames -of csv=p=0 "
            f"{shlex.quote(remote_mp4)} 2>/dev/null | tail -1"], 15)
        digits = re.findall(r"\d+", (probe.stdout or "").strip())
        if digits:
            expected = int(digits[-1])
    fresh = _run(ssh + [f"[ -s {shlex.quote(remote_raw)} ] && "
                        f"[ {shlex.quote(remote_raw)} -nt {shlex.quote(remote_mp4)} ] "
                        "&& echo FRESH || echo STALE"], 15)
    is_fresh = "FRESH" in (fresh.stdout or "")
    size = _remote_size(ssh, remote_raw) or 0
    if is_fresh and expected > 0 and size == expected * FPGA_FRAME_BYTES:
        log(f"板端已有全片缓存 {Path(remote_raw).name}（{size / 1e6:.1f} MB，"
            f"{expected} 帧），跳过")
        return size
    if is_fresh and expected <= 0:
        log(f"板端已有转码缓存 {Path(remote_raw).name}（{size / 1e6:.1f} MB），"
            "源帧数未知，沿用")
        return size
    tmp_raw = remote_raw + ".tmp"
    cmd = (f"ffmpeg -y -loglevel error -i {shlex.quote(remote_mp4)} "
           "-vf scale=960:540 -pix_fmt rgb565be -f rawvideo")
    if expected > 0:
        cmd += f" -frames:v {expected}"
    cmd += f" {shlex.quote(tmp_raw)}"
    if expected > 0:
        log(f"板端转码全片 960x540 RGB565（{expected} 帧，约 "
            f"{expected * FPGA_FRAME_BYTES / 1e6:.0f} MB）...")
    else:
        log("板端转码 960x540 RGB565（全片，约 1 MB/帧）...")
    r = _run(ssh + [cmd], 1800)
    if r.returncode != 0:
        _run(ssh + [f"rm -f {shlex.quote(tmp_raw)}"], 15)
        raise RuntimeError(f"板端转码失败：{(r.stderr or r.stdout or '').strip()[:300]}")
    size = _remote_size(ssh, tmp_raw) or 0
    if size <= 0:
        _run(ssh + [f"rm -f {shlex.quote(tmp_raw)}"], 15)
        raise RuntimeError("转码后原始帧文件为空")
    mv = _run(ssh + [f"mv -f {shlex.quote(tmp_raw)} {shlex.quote(remote_raw)}"], 15)
    if mv.returncode != 0:
        raise RuntimeError(f"替换转码缓存失败：{(mv.stderr or mv.stdout or '').strip()[:300]}")
    log(f"转码完成：{size / 1e6:.1f} MB（约 {size // FPGA_FRAME_BYTES} 帧，"
        "发送器循环整段）")
    return size


def _fpga_start(ssh: list[str], remote_dir: str, front_raw: str, rear_raw: str,
                fps: float, log) -> int:
    """启动单实例发送看门狗：发送器退出后自动重启，链路退出也不停。"""
    _run(ssh + ["pkill -f '[s]end_loop.sh' 2>/dev/null || true; "
                "pkill -f '[s]end_raw.py' 2>/dev/null || true; "
                "rm -f /tmp/send_loop.lock"], 15)
    loop_path = remote_dir + "/send_loop.sh"
    cmd = (f"setsid nohup bash {shlex.quote(loop_path)} "
           f"{shlex.quote(front_raw)} {shlex.quote(rear_raw)} {fps:g} "
           f">/dev/null 2>&1 < /dev/null & echo LOOP_PID=$!")
    r = _run(ssh + [cmd], 20)
    m = re.search(r"LOOP_PID=(\d+)", r.stdout or "")
    if not m:
        raise RuntimeError(f"板端发送看门狗未启动：{(r.stderr or r.stdout or '').strip()[:300]}")
    loop_pid = int(m.group(1))
    time.sleep(2.5)
    alive = _run(ssh + [
        f"kill -0 {loop_pid} 2>/dev/null && echo LOOP_ALIVE || echo LOOP_DEAD; "
        f"pgrep -af '[s]end_raw.py' | head -2; "
        f"tail -5 {shlex.quote(remote_dir)}/send_loop.log 2>/dev/null"], 15)
    out = alive.stdout or ""
    if "LOOP_ALIVE" not in out or "send_raw.py" not in out:
        raise RuntimeError("发送看门狗/发送器未运行，日志：\n" + out.strip()[:800])
    log(f"板端发送看门狗 PID={loop_pid} 已运行（单实例、自动重启；停止按钮可结束）")
    for line in out.splitlines()[1:]:
        if line.strip():
            log("  " + line.strip())
    return loop_pid


def _fpga_stop(ssh: list[str], log) -> None:
    r = _run(ssh + ["pkill -f '[s]end_loop.sh' 2>/dev/null || true; "
                    "pkill -f '[s]end_raw.py' 2>/dev/null || true; sleep 0.6; "
                    "rm -f /tmp/send_loop.lock; "
                    "pgrep -af '[s]end_loop.sh|[s]end_raw.py' || echo FPGA_SEND_STOPPED"], 15)
    log("FPGA 发送已停止（看门狗与发送器均已结束）。"
        if "FPGA_SEND_STOPPED" in (r.stdout or "")
        else "FPGA 发送停止结果：" + (r.stdout or "").strip())


def _remote_check(host: str, user: str, key: Path, remote_dir: str) -> None:
    ssh = _ssh_base(host, user, key)
    r = _run(ssh + ["echo SSH_OK; test -f " + remote_dir + "/dashboard/protocol/schema.py && echo SCHEMA_OK || echo SCHEMA_MISSING"])
    if "SSH_OK" not in (r.stdout or ""):
        raise RuntimeError(f"SSH 失败：{(r.stderr or r.stdout).strip()}\n"
                           "请确认 key 已加入板端 authorized_keys，且当前 PC IP 未被 from= 限制。")
    if "SCHEMA_MISSING" in (r.stdout or ""):
        if not DEPLOY_TAR.exists():
            raise RuntimeError(f"板端缺 schema 且没有部署包：{DEPLOY_TAR}")
        scp = _scp_base(key)
        rr = _run(scp + [str(DEPLOY_TAR), f"{user}@{host}:/home/{user}/avm_board.tar.gz"], 180)
        if rr.returncode != 0:
            raise RuntimeError(f"上传部署包失败：{rr.stderr}")
        rr = _run(ssh + [f"mkdir -p {remote_dir} && tar -xzf /home/{user}/avm_board.tar.gz -C {remote_dir}"])
        if rr.returncode != 0:
            raise RuntimeError(f"解压部署包失败：{rr.stderr}")


def run_pipeline(video: Path, host: str, user: str, key: Path, fps: float,
                 frames: int, headless: bool, log, proc_holder: dict | None = None,
                 quad: dict[str, Path] | None = None,
                 start_delay_ms: float = 0.0, shots: int = 0,
                 out_dir: str | None = None) -> int:
    video = Path(video).resolve()
    quad_paths: dict[str, Path] | None = None
    if quad:
        quad_paths = {str(k).lower(): Path(v).resolve() for k, v in quad.items()}
        if set(quad_paths) != {"front", "right", "rear", "left"}:
            log("四路模式必须提供 front/right/rear/left")
            return 2
        for name, p in quad_paths.items():
            if not p.exists():
                log(f"四路 {name} 视频不存在：{p}")
                return 2
        video = quad_paths["front"]
    if not video.exists():
        log(f"视频不存在：{video}")
        return 2
    if not key.exists():
        log(f"SSH key 不存在：{key}")
        return 2
    if not PY.exists() or not APP.exists():
        log(f"Python/AVM3D 不存在：{PY} / {APP}")
        return 2
    start_delay_ms = max(0.0, min(float(start_delay_ms), 5000.0))
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    remote_dir = f"/home/{user}/avm_board"
    ssh = _ssh_base(host, user, key)
    scp = _scp_base(key)
    board_ssh: subprocess.Popen | None = None
    try:
        log("检查板端 SSH / 部署 ...")
        _remote_check(host, user, key, remote_dir)
        log(f"SSH OK：{user}@{host}")

        # 始终更新板端脚本（小文件），避免板端版本落后
        r = _run(scp + [str(BOARD_SCRIPT), f"{user}@{host}:{remote_dir}/board_yolo_udp.py"], 60)
        if r.returncode != 0:
            raise RuntimeError(f"上传 board_yolo_udp.py 失败：{r.stderr}")

        if quad_paths:
            pc_fps, play_frames = _quad_meta(quad_paths, fps, frames, log)
            board_fps = 0.0 if fps <= 0 else float(fps)
            log("板端只推理前向；后向上传板端仅存储，不推理")
        else:
            if fps <= 0:
                board_fps = 0.0
                pc_fps = _video_fps(video) or 30.0
                log(f"FPS=0：板端全速，PC 按源 {pc_fps:.2f} fps 等检测")
            else:
                board_fps = float(fps)
                pc_fps = float(fps)
            play_frames = frames
        log("帧数=" + ("全片" if play_frames == 0 else str(play_frames)))
        if start_delay_ms > 0:
            log(f"PC 启动延时 {start_delay_ms:.0f} ms（板端 START 后先跑）")

        uploads = [("前向", video)]
        if quad_paths:
            rear = quad_paths["rear"]
            if rear != video:
                uploads.append(("后向", rear))
        pending = []
        front_remote_name = ""
        for label, path in uploads:
            remote_name = _remote_video_name(path)
            remote_path = f"{remote_dir}/{remote_name}"
            local_bytes = path.stat().st_size
            if label == "前向":
                front_remote_name = remote_name
            remote_bytes = _remote_size(ssh, remote_path)
            if remote_bytes == local_bytes:
                log(f"板端已缓存{label} {remote_name}（{local_bytes / 1e6:.1f} MB），跳过上传")
            else:
                pending.append((label, path, remote_name, remote_path, local_bytes))
        if pending:
            free_kb = _remote_free_kb(ssh, remote_dir)
            need_kb = (sum(x[4] for x in pending) + 199 * 1024 * 1024) // 1024
            if free_kb is not None and free_kb < need_kb:
                raise RuntimeError(
                    f"板端空间不足：可用 {free_kb / 1024:.0f} MB，"
                    f"需要约 {need_kb / 1024:.0f} MB")
        for label, path, remote_name, remote_path, local_bytes in pending:
            log(f"上传{label} {path.name}（{local_bytes / 1e6:.1f} MB）"
                f" -> {remote_name} ...")
            r = _run(scp + [str(path), f"{user}@{host}:{remote_path}"], 5400)
            if r.returncode != 0:
                raise RuntimeError(f"上传{label}视频失败：{r.stderr}")
            if _remote_size(ssh, remote_path) != local_bytes:
                raise RuntimeError(f"上传后{label}文件大小不一致，检查磁盘/传输")

        pc_ip = _local_ip(host)
        log(f"PC IP={pc_ip}，启动板端（等待 START）...")
        _run(ssh + ["pkill -f '[b]oard_yolo_udp.py' 2>/dev/null || true"], 15)
        remote_cmd = (
            f"cd {remote_dir} && python3 -u board_yolo_udp.py "
            f"--video {shlex.quote(front_remote_name)} --host {pc_ip} --port {META_PORT} "
            f"--fps {board_fps:g} --frames {play_frames} --control-port {CTRL_PORT} "
            f"--post fast --warmup 3 --print-every 10 > run_board.log 2>&1"
        )
        # 不等待 ssh 返回：GUI/无控制台环境下 ssh -f 可能挂住。
        # 保持这条 SSH 连接作为板端进程的生命周期，后面靠 WAIT_START 日志判定启动成功。
        ssh_f = ["ssh", "-n"] + ssh[1:]
        board_ssh = subprocess.Popen(ssh_f + [remote_cmd], stdin=subprocess.DEVNULL,
                                     stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL)
        log(f"板端启动 SSH PID={board_ssh.pid}，等待 WAIT_START ...")

        deadline = time.monotonic() + 40
        ready = False
        while time.monotonic() < deadline:
            r = _run(ssh + [f"grep -q WAIT_START {remote_dir}/run_board.log && echo READY || echo WAIT"], 15)
            if "READY" in (r.stdout or ""):
                ready = True
                break
            if board_ssh.poll() is not None:
                break
            time.sleep(0.5)
        if not ready:
            raise RuntimeError(
                f"板端未进入 WAIT_START（SSH 退出码 {board_ssh.poll()}）；检查模型/板端日志")
        log("板端 WAIT_START，启动 PC " + ("四路 3D 窗口 ..." if quad_paths else "单路窗口 ..."))

        video_cfg = {
            "kind": "file", "path": str(video), "device": 0, "fps": float(pc_fps),
            "loop": False, "start_frame_id": 0, "width": 0, "height": 0,
            "layout": "atlas" if quad_paths else "single",
            "sync_to_detections": True, "detect_wait_ms": 150,
            "start_delay_ms": start_delay_ms,
        }
        if quad_paths:
            video_cfg["quad_paths"] = {k: str(v) for k, v in quad_paths.items()}
        cfg = {
            "schema": "avm3d_board_v1", "verified": False,
            "video": video_cfg,
            "atlas": {"width": 1280, "height": 720,
                      "cell_order": ["front", "right", "rear", "left"]},
            "calibration_id": 7301,
            "source_map": ({"front": "live", "right": "live",
                            "rear": "live", "left": "live"} if quad_paths else
                           {"front": "live", "right": "absent",
                            "rear": "absent", "left": "absent"}),
            "frame_table": {"mode": "none", "port": 7001, "tolerance_ms": 30.0},
            "metadata": {"udp_port": META_PORT},
            "control": {"host": host, "start_port": CTRL_PORT},
            "notes": ("launcher: 四路源文件现场拼接 + 前向后向上传 + 仅前向 RKNN；"
                      "非 LIVE 验收" if quad_paths else
                      "launcher: 单路视频 + RK3568 板端 YOLO + PC 车道；非 LIVE 验收"),
        }
        cfg_path = OUT_DIR / "board_config.json"
        cfg_path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")

        pc_cmd = [str(PY), "-X", "utf8", str(APP), "--source", "board",
                  "--board-config", str(cfg_path), "--calib", str(CALIB),
                  "--view", "2", "--layout", "3d" if quad_paths else "single",
                  "--detect-camera", "front", "--frames", str(play_frames),
                  "--wait-ms", "50", "--frame-cache", "240",
                  "--stats-out", str(OUT_DIR / "run_stats.json")]
        if headless:
            pc_cmd += ["--headless", "--force-no-gl"]
        if shots:
            pc_cmd += ["--shots", str(int(shots)),
                       "--out-dir", str(out_dir or (OUT_DIR / (
                           "quad3d_shots" if quad_paths else "single_shots")))]
        pc_log = OUT_DIR / "avm.log"
        log(f"PC 启动：{' '.join(pc_cmd)}")
        with open(pc_log, "w", encoding="utf-8") as fh:
            proc = subprocess.Popen(pc_cmd, cwd=str(ROOT), stdout=fh, stderr=subprocess.STDOUT,
                                    text=True)
        if proc_holder is not None:
            proc_holder["proc"] = proc
        log(f"PC 窗口 PID={proc.pid}；关闭窗口或按 Ctrl+C 结束。")
        try:
            rc = proc.wait()
        except KeyboardInterrupt:
            _terminate_proc_tree(proc)
            rc = proc.wait()
        log(f"PC 退出码={rc}，日志：{pc_log}")
        return rc
    except Exception as exc:  # noqa: BLE001
        log(f"失败：{exc}")
        return 3
    finally:
        _run(ssh + ["pkill -f '[b]oard_yolo_udp.py' 2>/dev/null || true"], 15)
        if board_ssh is not None:
            try:
                board_ssh.wait(timeout=5)
            except subprocess.TimeoutExpired:
                board_ssh.terminate()
                try:
                    board_ssh.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    board_ssh.kill()
        log("板端进程已停止。")


def run_fpga_send(front: Path, rear: Path, host: str, user: str, key: Path,
                  fps: float, frames: int, log) -> int:
    """选视频 -> 上传板端 -> 板端转 RGB565 -> 启动 FPGA 发送（CH2/CH3）。"""
    front = Path(front).resolve()
    rear = Path(rear).resolve()
    for label, p in (("前向(左格)", front), ("后向(右格)", rear)):
        if not p.is_file():
            log(f"{label}视频不存在：{p}")
            return 2
    if not key.is_file():
        log(f"SSH key 不存在：{key}")
        return 2
    if not FPGA_SEND_SCRIPT.is_file() or not FPGA_PROTO_SCRIPT.is_file():
        log(f"FPGA 发送脚本缺失：{FPGA_SEND_SCRIPT} / {FPGA_PROTO_SCRIPT}")
        return 2
    if not FPGA_LOOP_SCRIPT.is_file():
        log(f"发送看门狗脚本缺失：{FPGA_LOOP_SCRIPT}")
        return 2
    fps = min(max(float(fps), 1.0), FPGA_FPS_CAP)
    frames = max(int(frames), 0)
    avm_dir = f"/home/{user}/avm_board"
    fpga_dir = f"/home/{user}/fpga_send"
    ssh = _ssh_base(host, user, key)
    scp = _scp_base(key)
    try:
        log("检查板端 SSH ...")
        r = _run(ssh + ["echo SSH_OK"], 15)
        if "SSH_OK" not in (r.stdout or ""):
            raise RuntimeError(f"SSH 失败：{(r.stderr or r.stdout).strip()}")
        log(f"SSH OK：{user}@{host}")
        _fpga_preflight(ssh, log)

        # 上传发送脚本（小文件，每次都更新，避免板端版本落后）
        _run(ssh + [f"mkdir -p {shlex.quote(fpga_dir)} {shlex.quote(fpga_dir)}/videos"], 15)
        for src, dst in ((FPGA_SEND_SCRIPT, "send_raw.py"),
                         (FPGA_PROTO_SCRIPT, "video_protocol.py"),
                         (FPGA_LOOP_SCRIPT, "send_loop.sh")):
            r = _run(scp + [str(src), f"{user}@{host}:{fpga_dir}/{dst}"], 60)
            if r.returncode != 0:
                raise RuntimeError(f"上传 {dst} 失败：{r.stderr}")
        log("已同步 send_raw.py / video_protocol.py / send_loop.sh 到板端")

        # 上传视频：与 YOLO 流程共用 avm_board 缓存，避免同一文件传两遍
        _run(ssh + [f"mkdir -p {shlex.quote(avm_dir)}"], 15)
        jobs = []
        for label, path in (("前向", front), ("后向", rear)):
            remote_name = _remote_video_name(path)
            remote_path = f"{avm_dir}/{remote_name}"
            local_bytes = path.stat().st_size
            if _remote_size(ssh, remote_path) == local_bytes:
                log(f"板端已缓存{label} {remote_name}（{local_bytes / 1e6:.1f} MB），跳过上传")
            else:
                jobs.append((label, path, remote_path, local_bytes))
        if jobs:
            free_kb = _remote_free_kb(ssh, avm_dir)
            need_kb = (sum(x[3] for x in jobs) + 512 * 1024 * 1024) // 1024
            if free_kb is not None and free_kb < need_kb:
                raise RuntimeError(f"板端空间不足：可用 {free_kb / 1024:.0f} MB，"
                                   f"需要约 {need_kb / 1024:.0f} MB")
        for label, path, remote_path, local_bytes in jobs:
            log(f"上传{label} {path.name}（{local_bytes / 1e6:.1f} MB）...")
            r = _run(scp + [str(path), f"{user}@{host}:{remote_path}"], 5400)
            if r.returncode != 0:
                raise RuntimeError(f"上传{label}失败：{r.stderr}")
            if _remote_size(ssh, remote_path) != local_bytes:
                raise RuntimeError(f"上传后{label}大小不一致")

        # 板端转码 960x540 RGB565
        raws = {}
        for label, path in (("前向", front), ("后向", rear)):
            remote_name = _remote_video_name(path)
            raw = f"{fpga_dir}/videos/{remote_name.rsplit('.', 1)[0]}.rgb565"
            _fpga_convert(ssh, f"{avm_dir}/{remote_name}", raw, frames, log)
            raws[label] = raw

        pid = _fpga_start(ssh, fpga_dir, raws["前向"], raws["后向"], fps, log)
        log(f"FPGA 传输运行中：CH2(左格)=前向  CH3(右格)=后向  FPS 上限 {FPGA_FPS_CAP:g}")
        log(f"板端日志：{fpga_dir}/send_raw.log（tail -f 可看进度）")
        return 0
    except Exception as exc:  # noqa: BLE001
        log(f"失败：{exc}")
        return 3


def _usb_power_on(ssh: list[str], log) -> None:
    """关闭 UVC 采集卡 USB 自动挂起：板端 suspend 会导致 HDMI 无帧。"""
    cmd = ("for d in /sys/bus/usb/devices/*; do "
           "if [ -f $d/idVendor ] && [ \"$(cat $d/idVendor)\" = '1de1' ]; then "
           "pid=$(cat $d/idProduct 2>/dev/null); "
           "if [ \"$pid\" = 'f115' ] || [ \"$pid\" = 'f105' ]; then "
           "echo on | sudo -n tee $d/power/control >/dev/null 2>&1 || true; "
           "echo PATH=$d PID=$pid CONTROL=$(cat $d/power/control 2>/dev/null); "
           "fi; fi; done")
    r = _run(ssh + [cmd], 20)
    out = (r.stdout or "").strip()
    if "CONTROL=on" in out:
        log("UVC 采集卡 USB 自动挂起已关闭（power/control=on）")
    elif out:
        log("警告：UVC USB 电源状态未能设为 on：" + out.replace("\n", "; ")[:300])
    else:
        log("警告：未找到 1de1:f105/f115 UVC 采集卡")


def _capture_check(ssh: list[str], device, log) -> str:
    _usb_power_on(ssh, log)
    dev = f"/dev/video{int(device)}" if str(device).isdigit() else str(device)
    r = _run(ssh + [f"test -c {shlex.quote(dev)} && v4l2-ctl -d {shlex.quote(dev)} "
                    "--get-fmt-video 2>/dev/null | sed -n '1,50p' || echo CAPTURE_MISSING"], 20)
    out = (r.stdout or "").strip()
    if "CAPTURE_MISSING" in out or not out:
        raise RuntimeError(
            f"板端没有采集节点 {dev}；确认 USB HDMI 采集卡已插到 RK3568，且系统识别为 UVC")
    log(f"采集卡 {dev} 已识别")
    for line in out.splitlines()[:8]:
        if line.strip():
            log("  " + line.strip())
    return dev


def _send_frames(ssh: list[str], remote_log: str) -> int:
    r = _run(ssh + [f"grep -o 'frames=[0-9]*' {shlex.quote(remote_log)} 2>/dev/null | tail -1"], 15)
    m = re.search(r"frames=(\d+)", r.stdout or "")
    return int(m.group(1)) if m else 0


def run_fpga_infer(front: Path, rear: Path, host: str, user: str, key: Path,
                   fpga_fps: float, capture_device, capture_fps: float,
                   crop: str, frames: int, headless: bool, log,
                   proc_holder: dict | None = None, shots: int = 0,
                   out_dir: str | None = None, triple: bool = False,
                   quad_paths: dict[str, Path] | None = None) -> int:
    """FPGA 发送 -> USB HDMI 采集 -> 前向格裁剪 -> RKNN -> PC 窗口。

    triple=True 时板端额外对整张四宫格跑一次 RKNN，PC 显示三框：
    本地四路 3D + 前路识别 + 四宫格整帧识别。
    """
    if triple:
        if not quad_paths or set(quad_paths) != {"front", "right", "rear", "left"}:
            log("三框模式需要 front/right/rear/left 四路本地视频")
            return 2
        quad = {k: Path(v).resolve() for k, v in quad_paths.items()}
        front, rear = quad["front"], quad["rear"]
    else:
        quad = None
        front = Path(front).resolve()
        rear = Path(rear).resolve()
    for label, p in (("前向", front), ("后向", rear)):
        if not p.is_file():
            log(f"{label}视频不存在：{p}")
            return 2
    if triple:
        for name, p in quad.items():
            if not p.is_file():
                log(f"本地四路 {name} 不存在：{p}")
                return 2
        if not TRIPLE_APP.is_file():
            log(f"三框程序不存在：{TRIPLE_APP}")
            return 2
    if not key.is_file():
        log(f"SSH key 不存在：{key}")
        return 2
    if not BOARD_SCRIPT.is_file():
        log(f"板端脚本不存在：{BOARD_SCRIPT}")
        return 2
    ssh = _ssh_base(host, user, key)
    scp = _scp_base(key)
    remote_dir = f"/home/{user}/avm_board"
    board_ssh: subprocess.Popen | None = None
    try:
        # 先确认采集卡存在；不要等 FPGA 发送完才发现没节点
        _capture_check(ssh, capture_device, log)
        # 为帧序对齐，发送帧率与采集/YOLO 帧率一致
        align_fps = min(max(float(capture_fps), 1.0), 30.0)
        if abs(float(fpga_fps) - align_fps) > 0.1:
            log(f"为对齐将 FPGA 发送帧率从 {fpga_fps:g} 调整为 {align_fps:g} fps")
        rc = run_fpga_send(front, rear, host, user, key, align_fps, frames, log)
        if rc != 0:
            return rc
        time.sleep(0.8)

        log("检查板端部署 / 上传采集推理脚本 ...")
        _remote_check(host, user, key, remote_dir)
        r = _run(scp + [str(BOARD_SCRIPT), f"{user}@{host}:{remote_dir}/board_yolo_udp.py"], 60)
        if r.returncode != 0:
            raise RuntimeError(f"上传 board_yolo_udp.py 失败：{r.stderr}")
        _run(ssh + ["pkill -f '[b]oard_yolo_udp.py' 2>/dev/null || true"], 15)

        pc_ip = _local_ip(host)
        m_dev = re.search(r"(\d+)$", str(capture_device))
        if not m_dev:
            raise RuntimeError(f"无法从采集节点解析设备号：{capture_device!r}")
        dev_num = int(m_dev.group(1))
        yolo_fps = align_fps
        atlas_cmd = (
            f"--atlas-port {FPGA_ATLAS_META_PORT} "
            f"--atlas-video-port {FPGA_ATLAS_VIDEO_PORT} "
            f"--atlas-width {FPGA_ATLAS_WIDTH} --atlas-height {FPGA_ATLAS_HEIGHT} "
            f"--atlas-quality 60 "
            if triple else ""
        )
        remote_cmd = (
            f"setsid nohup python3 -u {remote_dir}/board_yolo_udp.py "
            f"--capture-device {dev_num} --capture-width {FPGA_CAPTURE_WIDTH} "
            f"--capture-height {FPGA_CAPTURE_HEIGHT} --capture-fps {yolo_fps:g} "
            f"--capture-fourcc {FPGA_CAPTURE_FOURCC} --capture-timeout 30 "
            f"--crop {shlex.quote(crop)} --video-port {FPGA_VIDEO_PORT} "
            f"--video-quality 70 {atlas_cmd}"
            f"--host {pc_ip} --port {META_PORT} --fps {yolo_fps:g} --frames 0 "
            f"--post fast --warmup 3 --print-every 10 "
            f"> {remote_dir}/run_hdmi.log 2>&1 < /dev/null & echo BOARD_PID=$!"
        )
        start = _run(ssh + [remote_cmd], 25)
        m_pid = re.search(r"BOARD_PID=(\d+)", start.stdout or "")
        if not m_pid:
            raise RuntimeError("板端采集推理进程未启动："
                               + (start.stderr or start.stdout or "").strip()[:300])
        board_pid = int(m_pid.group(1))
        time.sleep(1.0)
        alive = _run(ssh + [f"kill -0 {board_pid} 2>/dev/null && echo ALIVE || echo DEAD; "
                            f"tail -3 {remote_dir}/run_hdmi.log 2>/dev/null"], 15)
        if "ALIVE" not in (alive.stdout or ""):
            raise RuntimeError("板端采集推理进程启动后退出："
                               + (alive.stdout or "").strip()[:400])
        log(f"板端采集推理 PID={board_pid}（detached），等待首帧/开始推理 ...")
        deadline = time.monotonic() + 45
        ready = False
        while time.monotonic() < deadline:
            r = _run(ssh + [
                f"kill -0 {board_pid} 2>/dev/null || echo BOARD_DEAD; "
                f"grep -qF '[board] model=' {remote_dir}/run_hdmi.log "
                "&& echo READY || echo WAIT"], 15)
            out = r.stdout or ""
            if "READY" in out:
                ready = True
                break
            if "BOARD_DEAD" in out:
                break
            time.sleep(0.5)
        if not ready:
            tail = _run(ssh + [f"tail -20 {remote_dir}/run_hdmi.log 2>/dev/null"], 15)
            raise RuntimeError("板端 HDMI 采集未就绪（检查 FPGA HDMI 是否接到采集卡）："
                               + (tail.stdout or "").strip()[-500:])
        log("板端已拿到 HDMI 首帧并开始推理")

        log(f"板端将回传前向 JPEG 视频到 PC UDP {FPGA_VIDEO_PORT}；"
            f"窗口直接显示板端采集/裁剪画面")
        if triple:
            log(f"四宫格整帧 JPEG/OBJECT 走 UDP {FPGA_ATLAS_VIDEO_PORT}/"
                f"{FPGA_ATLAS_META_PORT}；板端双推理")

        cfg = {
            "schema": "avm3d_board_v1", "verified": False,
            "video": {"kind": "udp", "udp_port": FPGA_VIDEO_PORT, "device": 0,
                      "fps": float(yolo_fps), "loop": False, "start_frame_id": 0,
                      "width": 0, "height": 0, "layout": "single",
                      "sync_to_detections": True, "detect_wait_ms": 500,
                      "start_delay_ms": 0},
            "atlas": {"width": 1280, "height": 720,
                      "cell_order": ["front", "right", "rear", "left"]},
            "calibration_id": 7301,
            "source_map": {"front": "live", "right": "absent",
                           "rear": "absent", "left": "absent"},
            "frame_table": {"mode": "none", "port": 7001, "tolerance_ms": 30.0},
            "metadata": {"udp_port": META_PORT},
            "control": {"host": host, "start_port": 0},
            "notes": ("FPGA HDMI capture -> front crop -> RKNN; "
                      "board streams JPEG+OBJECT; PC joins current frame"),
        }
        cfg_path = OUT_DIR / "board_config.json"
        if triple:
            pc_cmd = [
                str(PY), "-X", "utf8", str(TRIPLE_APP),
                "--front", str(quad["front"]), "--right", str(quad["right"]),
                "--rear", str(quad["rear"]), "--left", str(quad["left"]),
                "--calib", str(CALIB),
                "--front-port", str(FPGA_VIDEO_PORT),
                "--atlas-port", str(FPGA_ATLAS_VIDEO_PORT),
                "--front-meta", str(META_PORT),
                "--atlas-meta", str(FPGA_ATLAS_META_PORT),
                "--fps", f"{yolo_fps:g}",
                "--frames", str(max(0, int(frames))),
                "--stats-out", str(OUT_DIR / "triple_stats.json"),
                "--out-dir", str(out_dir or (OUT_DIR / "fpga_triple")),
            ]
        else:
            cfg_path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2),
                                encoding="utf-8")
            # frames=0 表示窗口常驻；非 0 时窗口播完即正常退出并写统计
            pc_cmd = [str(PY), "-X", "utf8", str(APP), "--source", "board",
                      "--board-config", str(cfg_path), "--calib", str(CALIB),
                      "--view", "2", "--layout", "single",
                      "--detect-camera", "front",
                      "--frames", str(max(0, int(frames))), "--wait-ms", "50",
                      "--frame-cache", "240",
                      "--stats-out", str(OUT_DIR / "fpga_stats.json")]
        if headless:
            pc_cmd += ["--headless"] + ([] if triple else ["--force-no-gl"])
        if shots:
            pc_cmd += ["--shots", str(int(shots))]
            if not triple:
                pc_cmd += ["--out-dir", str(out_dir or (OUT_DIR / "fpga_shots"))]
        pc_log = OUT_DIR / ("triple.log" if triple else "avm.log")
        log(f"PC 启动：{' '.join(pc_cmd)}")
        with open(pc_log, "w", encoding="utf-8") as fh:
            proc = subprocess.Popen(pc_cmd, cwd=str(ROOT), stdout=fh,
                                    stderr=subprocess.STDOUT, text=True)
        if proc_holder is not None:
            proc_holder["proc"] = proc
        log(f"PC 窗口 PID={proc.pid}；关闭窗口或按 Ctrl+C 结束。")
        try:
            return proc.wait()
        except KeyboardInterrupt:
            _terminate_proc_tree(proc)
            return proc.wait()
    except Exception as exc:  # noqa: BLE001
        log(f"失败：{exc}")
        return 3
    finally:
        _run(ssh + ["pkill -f '[b]oard_yolo_udp.py' 2>/dev/null || true"], 15)
        log("板端采集推理已停止；发送看门狗保持运行（要用停止按钮结束）。")


def _gui() -> int:
    import tkinter as tk
    from tkinter import filedialog, messagebox, scrolledtext, ttk

    class Launcher:
        def __init__(self, root):
            self.root = root
            root.title("夜瞳 · 板端 YOLO → PC 单路 / 四路 3D 可视化")
            root.geometry("940x760")
            self.q: queue.Queue[str] = queue.Queue()
            self.worker = None
            self.fpga_worker = None
            self.fpga_infer_worker = None
            self.fpga_triple_worker = None
            self.proc_holder: dict = {}
            self._build()
            self.root.after(100, self._drain)

        def _build(self):
            frm = ttk.Frame(self.root, padding=10)
            frm.pack(fill="x")
            ttk.Label(frm, text="模式").grid(row=0, column=0, sticky="w")
            self.mode = tk.StringVar(value="单路")
            mode_cb = ttk.Combobox(frm, textvariable=self.mode, width=12, state="readonly",
                                   values=("单路", "四路 3D"))
            mode_cb.grid(row=0, column=1, sticky="w", padx=6)
            mode_cb.bind("<<ComboboxSelected>>", lambda _e: self._mode_changed())
            ttk.Label(frm, text="四路：等 START 后延时拼接；前/后都上传，仅前向识别",
                      foreground="#555").grid(row=0, column=2, columnspan=2, sticky="w")

            self.single_row = ttk.Frame(frm)
            self.single_row.grid(row=1, column=0, columnspan=4, sticky="ew")
            ttk.Label(self.single_row, text="单路视频").grid(row=0, column=0, sticky="w")
            self.video = tk.StringVar(value=str(DEFAULT_VIDEO) if DEFAULT_VIDEO.exists() else "")
            ttk.Entry(self.single_row, textvariable=self.video, width=72).grid(
                row=0, column=1, padx=6)
            ttk.Button(self.single_row, text="选择...", command=self._browse).grid(
                row=0, column=2)

            ttk.Label(frm, text="板端").grid(row=2, column=0, sticky="w", pady=6)
            self.host = tk.StringVar(value=DEFAULT_HOST)
            self.user = tk.StringVar(value=DEFAULT_USER)
            ttk.Entry(frm, textvariable=self.host, width=18).grid(
                row=2, column=1, sticky="w", padx=6)
            ttk.Label(frm, text="用户").grid(row=2, column=2, sticky="e")
            ttk.Entry(frm, textvariable=self.user, width=12).grid(
                row=2, column=3, sticky="w")
            ttk.Label(frm, text="Key").grid(row=3, column=0, sticky="w")
            self.key = tk.StringVar(value=str(DEFAULT_KEY))
            ttk.Entry(frm, textvariable=self.key, width=72).grid(row=3, column=1, padx=6)
            ttk.Label(frm, text="FPS(0=板端全速)").grid(row=4, column=0, sticky="w", pady=6)
            self.fps = tk.StringVar(value="15")
            ttk.Entry(frm, textvariable=self.fps, width=8).grid(
                row=4, column=1, sticky="w", padx=6)
            ttk.Label(frm, text="帧数(0=全片)").grid(row=4, column=2, sticky="e")
            self.frames = tk.StringVar(value="0")
            ttk.Entry(frm, textvariable=self.frames, width=8).grid(
                row=4, column=3, sticky="w")
            ttk.Label(frm, text="启动延时(ms)").grid(row=5, column=0, sticky="w")
            self.delay_ms = tk.StringVar(value="300")
            ttk.Entry(frm, textvariable=self.delay_ms, width=8).grid(
                row=5, column=1, sticky="w", padx=6)
            ttk.Label(frm, text="板端 START 后 PC 再开始拼接；最大 5000",
                      foreground="#555").grid(row=5, column=2, columnspan=2, sticky="w")

            self.quad_box = ttk.LabelFrame(
                self.root, text="四路 3D 源文件（前向会上传并推理；后向上传仅存储）",
                padding=8)
            self.quad_vars: dict[str, tk.StringVar] = {}
            labels = (("front", "前向"), ("right", "右"), ("rear", "后"), ("left", "左"))
            for i, (name, label) in enumerate(labels):
                default = ROOT / "reports" / "nuscenes_scene0061" / f"{name}.mp4"
                var = tk.StringVar(value=str(default) if default.is_file() else "")
                self.quad_vars[name] = var
                ttk.Label(self.quad_box, text=label).grid(row=i, column=0, sticky="w",
                                                          pady=3)
                ttk.Entry(self.quad_box, textvariable=var, width=74).grid(
                    row=i, column=1, padx=6)
                ttk.Button(self.quad_box, text="选择...",
                           command=lambda n=name: self._browse_quad(n)).grid(
                    row=i, column=2)
            ttk.Label(self.quad_box,
                      text="按前/右/后/左选择；四路取最短帧数，PC 现场拼 1280×720；"
                           "所有源需同帧率、同起点",
                      foreground="#555").grid(row=4, column=0, columnspan=3,
                                              sticky="w", pady=(4, 0))

            self.fpga_box = ttk.LabelFrame(
                self.root,
                text="FPGA 视频传输（前向 -> 左格 CH2；后向 -> 右格 CH3）",
                padding=8)
            self.fpga_front = tk.StringVar()
            self.fpga_rear = tk.StringVar()
            for i, (name, label) in enumerate((("front", "前向(左格)"),
                                               ("rear", "后向(右格)"))):
                var = self.fpga_front if name == "front" else self.fpga_rear
                ttk.Label(self.fpga_box, text=label).grid(row=i, column=0,
                                                          sticky="w", pady=3)
                ttk.Entry(self.fpga_box, textvariable=var, width=68).grid(
                    row=i, column=1, padx=6)
                ttk.Button(self.fpga_box, text="选择...",
                           command=lambda n=name: self._browse_fpga(n)).grid(
                    row=i, column=2)
            frow = ttk.Frame(self.fpga_box)
            frow.grid(row=2, column=0, columnspan=3, sticky="w", pady=(4, 0))
            ttk.Label(frow, text="FPS(1~40)").pack(side="left")
            self.fpga_fps = tk.StringVar(value="25")
            ttk.Entry(frow, textvariable=self.fpga_fps, width=6).pack(
                side="left", padx=6)
            ttk.Label(frow, text="转码帧数(0=全片)").pack(side="left", padx=(12, 0))
            self.fpga_frames = tk.StringVar(value="0")
            ttk.Entry(frow, textvariable=self.fpga_frames, width=7).pack(
                side="left", padx=6)
            crow = ttk.Frame(self.fpga_box)
            crow.grid(row=4, column=0, columnspan=3, sticky="w", pady=(4, 0))
            ttk.Label(crow, text="采集节点").pack(side="left")
            self.fpga_capture_device = tk.StringVar(value="0")
            ttk.Entry(crow, textvariable=self.fpga_capture_device, width=5).pack(
                side="left", padx=(4, 10))
            ttk.Label(crow, text="采集 FPS").pack(side="left")
            self.fpga_capture_fps = tk.StringVar(value="15")
            ttk.Entry(crow, textvariable=self.fpga_capture_fps, width=5).pack(
                side="left", padx=(4, 10))
            ttk.Label(crow, text="裁剪 x,y,w,h").pack(side="left")
            self.fpga_crop = tk.StringVar(value="auto")
            ttk.Entry(crow, textvariable=self.fpga_crop, width=16).pack(
                side="left", padx=4)
            ttk.Label(self.fpga_box,
                      text="首次对整段视频转码（约 1 MB/帧），已转码按修改时间缓存；"
                           "三框按钮使用上方“四路 3D 源文件”（前/后向同时发 FPGA）",
                      foreground="#555").grid(row=3, column=0, columnspan=3,
                                              sticky="w", pady=(4, 0))

            self.btns = ttk.Frame(self.root, padding=(10, 0))
            self.btns.pack(fill="x")
            self.start_btn = ttk.Button(self.btns, text="开始推理", command=self._start)
            self.start_btn.pack(side="left")
            self.stop_btn = ttk.Button(self.btns, text="停止", command=self._stop,
                                       state="disabled")
            self.stop_btn.pack(side="left", padx=8)
            self.fpga_btn = ttk.Button(self.btns, text="开始 FPGA 传输",
                                       command=self._fpga_start)
            self.fpga_btn.pack(side="left", padx=(16, 0))
            self.fpga_infer_btn = ttk.Button(self.btns, text="FPGA HDMI 推理",
                                             command=self._fpga_infer_start)
            self.fpga_infer_btn.pack(side="left", padx=8)
            self.fpga_triple_btn = ttk.Button(self.btns, text="FPGA 三框",
                                              command=self._fpga_triple_start)
            self.fpga_triple_btn.pack(side="left", padx=8)
            self.fpga_stop_btn = ttk.Button(self.btns, text="停止传输",
                                            command=self._fpga_stop,
                                            state="disabled")
            self.fpga_stop_btn.pack(side="left", padx=8)
            self.status = tk.StringVar(value="就绪")
            ttk.Label(self.btns, textvariable=self.status).pack(side="left", padx=12)
            self.fpga_box.pack(fill="x", padx=10, pady=(0, 4), before=self.btns)
            self.logbox = scrolledtext.ScrolledText(self.root, height=18, state="disabled")
            self.logbox.pack(fill="both", expand=True, padx=10, pady=10)
            self.root.protocol("WM_DELETE_WINDOW", self._close)

        def _mode_changed(self):
            if self.mode.get() == "四路 3D":
                self.single_row.grid_remove()
                self.quad_box.pack(fill="x", padx=10, pady=(0, 4), before=self.fpga_box)
            else:
                self.quad_box.pack_forget()
                self.single_row.grid()
            self.fpga_box.pack(fill="x", padx=10, pady=(0, 4), before=self.btns)

        def _browse(self):
            p = filedialog.askopenfilename(
                title="选择视频",
                filetypes=[("视频", "*.mp4 *.mov *.avi *.mkv *.m4v"), ("所有文件", "*.*")])
            if p:
                self.video.set(p)

        def _browse_quad(self, name: str):
            p = filedialog.askopenfilename(
                title=f"选择{name}视频",
                filetypes=[("视频", "*.mp4 *.mov *.avi *.mkv *.m4v"), ("所有文件", "*.*")])
            if p:
                self.quad_vars[name].set(p)

        def _browse_fpga(self, which: str):
            p = filedialog.askopenfilename(
                title="选择" + ("前向(左格)" if which == "front" else "后向(右格)") + "视频",
                filetypes=[("视频", "*.mp4 *.mov *.avi *.mkv *.m4v"), ("所有文件", "*.*")])
            if p:
                (self.fpga_front if which == "front" else self.fpga_rear).set(p)

        def _fpga_start(self):
            if self.fpga_worker and self.fpga_worker.is_alive():
                return
            front = Path(self.fpga_front.get().strip())
            rear = Path(self.fpga_rear.get().strip())
            if not front.is_file():
                messagebox.showerror("错误", "请选择存在的前向(左格)视频")
                return
            if not rear.is_file():
                messagebox.showerror("错误", "请选择存在的后向(右格)视频")
                return
            try:
                fps = float(self.fpga_fps.get())
                frames = int(self.fpga_frames.get())
            except ValueError:
                messagebox.showerror("错误", "FPS / 转码帧数必须是数字")
                return
            if not 1 <= fps <= 40:
                messagebox.showerror("错误", "FPS 取 1~40（实测上限 40）")
                return
            if frames < 0:
                messagebox.showerror("错误", "转码帧数 >= 0")
                return
            self.fpga_btn.configure(state="disabled")
            self.fpga_triple_btn.configure(state="disabled")
            self.fpga_stop_btn.configure(state="normal")
            self.status.set("FPGA 传输中")
            self._log("=" * 60)
            self._log("FPGA 视频传输")
            self._log(f"前向(左格 CH2)：{front}")
            self._log(f"后向(右格 CH3)：{rear}")
            self._log(f"FPS={fps:g}  转码帧数={'全片' if frames == 0 else frames}")
            self.fpga_worker = threading.Thread(
                target=self._work_fpga, daemon=True,
                args=(front, rear, fps, frames))
            self.fpga_worker.start()

        def _work_fpga(self, front, rear, fps, frames):
            rc = run_fpga_send(front, self.host.get().strip(),
                               self.user.get().strip(),
                               Path(self.key.get().strip()), fps, frames,
                               self._log)
            self._log(f"FPGA 传输流程结束，退出码={rc}")
            self.root.after(0, self._fpga_done)

        def _fpga_done(self):
            self.fpga_btn.configure(state="normal")
            self.fpga_triple_btn.configure(state="normal")
            self.fpga_stop_btn.configure(state="normal")
            self.status.set("发送看门狗运行中（停止按钮结束）")

        def _fpga_infer_start(self):
            if self.fpga_infer_worker and self.fpga_infer_worker.is_alive():
                return
            front = Path(self.fpga_front.get().strip())
            rear = Path(self.fpga_rear.get().strip())
            if not front.is_file():
                messagebox.showerror("错误", "请选择存在的前向(左格)视频")
                return
            if not rear.is_file():
                messagebox.showerror("错误", "请选择存在的后向(右格)视频")
                return
            try:
                fps = float(self.fpga_fps.get())
                frames = int(self.fpga_frames.get())
                capture_fps = float(self.fpga_capture_fps.get())
            except ValueError:
                messagebox.showerror("错误", "FPS / 转码帧数 / 采集 FPS 必须是数字")
                return
            crop = self.fpga_crop.get().strip()
            if crop.lower() not in ("auto", "front") and not re.fullmatch(
                    r"\d+,\d+,\d+,\d+", crop):
                messagebox.showerror("错误", "裁剪填 auto（左上 1/4）或 x,y,w,h")
                return
            if not 1 <= fps <= 40 or not 1 <= capture_fps <= 30:
                messagebox.showerror("错误", "FPGA FPS 取 1~40，采集 FPS 取 1~30")
                return
            if frames < 0:
                messagebox.showerror("错误", "转码帧数 >= 0")
                return
            self.fpga_btn.configure(state="disabled")
            self.fpga_infer_btn.configure(state="disabled")
            self.fpga_triple_btn.configure(state="disabled")
            self.fpga_stop_btn.configure(state="normal")
            self.status.set("FPGA HDMI 推理中")
            self._log("=" * 60)
            self._log("FPGA HDMI -> 板端采集 -> YOLO -> PC")
            self._log(f"前向(左格 CH2)：{front}")
            self._log(f"后向(右格 CH3)：{rear}")
            self._log(f"采集节点={self.fpga_capture_device.get()}  "
                      f"采集FPS={capture_fps:g}  裁剪={crop}")
            self._log("PC 显示本地前向源；检测来自 FPGA HDMI；无 Frame Marker，按发送帧号近似对齐")
            self.fpga_infer_worker = threading.Thread(
                target=self._work_fpga_infer, daemon=True,
                args=(front, rear, fps, frames, self.fpga_capture_device.get().strip(),
                      capture_fps, crop))
            self.fpga_infer_worker.start()

        def _work_fpga_infer(self, front, rear, fps, frames, capture_device,
                             capture_fps, crop):
            rc = run_fpga_infer(front, rear, self.host.get().strip(),
                                self.user.get().strip(),
                                Path(self.key.get().strip()), fps,
                                capture_device, capture_fps, crop, frames,
                                False, self._log, self.proc_holder)
            self._log(f"FPGA HDMI 推理流程结束，退出码={rc}")
            self.root.after(0, self._fpga_infer_done)

        def _fpga_infer_done(self):
            self.fpga_btn.configure(state="normal")
            self.fpga_infer_btn.configure(state="normal")
            self.fpga_triple_btn.configure(state="normal")
            self.fpga_stop_btn.configure(state="normal")
            self.status.set("链路已退出；发送看门狗运行中（停止按钮结束）")

        def _fpga_triple_start(self):
            if self.fpga_triple_worker and self.fpga_triple_worker.is_alive():
                return
            quad = {name: Path(self.quad_vars[name].get().strip())
                    for name in ("front", "right", "rear", "left")}
            for name, p in quad.items():
                if not p.is_file():
                    messagebox.showerror(
                        "错误", f"三框需要四路本地视频；{name} 不存在：{p}")
                    return
            try:
                fps = float(self.fpga_fps.get())
                frames = int(self.fpga_frames.get())
                capture_fps = float(self.fpga_capture_fps.get())
            except ValueError:
                messagebox.showerror("错误", "FPS / 转码帧数 / 采集 FPS 必须是数字")
                return
            crop = self.fpga_crop.get().strip()
            if crop.lower() not in ("auto", "front") and not re.fullmatch(
                    r"\d+,\d+,\d+,\d+", crop):
                messagebox.showerror("错误", "裁剪填 auto（左上 1/4）或 x,y,w,h")
                return
            if not 1 <= fps <= 40 or not 1 <= capture_fps <= 30:
                messagebox.showerror("错误", "FPGA FPS 取 1~40，采集 FPS 取 1~30")
                return
            if frames < 0:
                messagebox.showerror("错误", "转码帧数 >= 0")
                return
            self.fpga_btn.configure(state="disabled")
            self.fpga_infer_btn.configure(state="disabled")
            self.fpga_triple_btn.configure(state="disabled")
            self.fpga_stop_btn.configure(state="normal")
            self.status.set("三框同显运行中")
            self._log("=" * 60)
            self._log("三框同显：本地四路 3D + FPGA 前路 + FPGA 四宫格整帧")
            self._log("板端同一 RKNN 顺序跑两次；发送/采集/YOLO 目标帧率 "
                      f"{capture_fps:g} fps（双推理实际约 8~10 fps）")
            for name, p in quad.items():
                self._log(f"  {name}: {p}")
            self.fpga_triple_worker = threading.Thread(
                target=self._work_fpga_triple, daemon=True,
                args=(quad, fps, frames, self.fpga_capture_device.get().strip(),
                      capture_fps, crop))
            self.fpga_triple_worker.start()

        def _work_fpga_triple(self, quad, fps, frames, capture_device,
                              capture_fps, crop):
            rc = run_fpga_infer(
                quad["front"], quad["rear"], self.host.get().strip(),
                self.user.get().strip(), Path(self.key.get().strip()), fps,
                capture_device, capture_fps, crop, frames, False, self._log,
                self.proc_holder, triple=True, quad_paths=quad)
            self._log(f"三框同显流程结束，退出码={rc}")
            self.root.after(0, self._fpga_infer_done)

        def _fpga_stop(self):
            self._log("请求停止 FPGA 传输/推理 ...")
            try:
                subprocess.run(
                    _ssh_base(self.host.get().strip(), self.user.get().strip(),
                              Path(self.key.get().strip())) +
                    ["pkill -f '[b]oard_yolo_udp.py' 2>/dev/null || true; "
                     "pkill -f '[s]end_loop.sh' 2>/dev/null || true; "
                     "pkill -f '[s]end_raw.py' 2>/dev/null || true; "
                     "rm -f /tmp/send_loop.lock"],
                    capture_output=True, text=True, timeout=10)
                self._log("已发送停止命令（看门狗/发送器/板端采集均已结束）")
            except Exception as exc:  # noqa: BLE001
                self._log(f"停止失败：{exc}")
            p = self.proc_holder.get("proc")
            if p is not None:
                _terminate_proc_tree(p)
            self.fpga_btn.configure(state="normal")
            self.fpga_infer_btn.configure(state="normal")
            self.fpga_triple_btn.configure(state="normal")
            self.fpga_stop_btn.configure(state="disabled")
            self.status.set("已停止")

        def _log(self, msg: str):
            self.q.put(msg)

        def _drain(self):
            try:
                while True:
                    msg = self.q.get_nowait()
                    self.logbox.configure(state="normal")
                    self.logbox.insert("end", msg + "\n")
                    self.logbox.see("end")
                    self.logbox.configure(state="disabled")
            except queue.Empty:
                pass
            self.root.after(100, self._drain)

        def _start(self):
            if self.worker and self.worker.is_alive():
                return
            quad = None
            if self.mode.get() == "四路 3D":
                quad = {}
                labels = (("front", "前向"), ("right", "右"), ("rear", "后"),
                          ("left", "左"))
                for name, label in labels:
                    p = Path(self.quad_vars[name].get().strip())
                    if not p.is_file():
                        messagebox.showerror("错误", f"请选择存在的{label}视频")
                        return
                    quad[name] = p
                video = quad["front"]
            else:
                video = Path(self.video.get().strip())
                if not video.is_file():
                    messagebox.showerror("错误", "请先选择存在的视频文件")
                    return
            try:
                fps = float(self.fps.get())
                frames = int(self.frames.get())
                delay_ms = float(self.delay_ms.get())
            except ValueError:
                messagebox.showerror("错误", "FPS / 帧数 / 延时必须是数字")
                return
            if fps < 0 or frames < 0 or delay_ms < 0 or delay_ms > 5000:
                messagebox.showerror("错误", "FPS>=0，帧数>=0，延时 0~5000 ms")
                return
            self.start_btn.configure(state="disabled")
            self.stop_btn.configure(state="normal")
            self.status.set("运行中")
            self._log("=" * 60)
            self._log(f"模式：{self.mode.get()}")
            if quad:
                for name, label in (("front", "前向"), ("right", "右"),
                                    ("rear", "后"), ("left", "左")):
                    self._log(f"{label}：{quad[name]}")
                self._log("前向会上传并识别；后向上传仅存储；右/左只在本机拼接")
            else:
                self._log(f"视频：{video}")
            self._log(f"板端：{self.user.get()}@{self.host.get()}  "
                      f"FPS={'全速' if fps == 0 else fps} "
                      f"frames={frames or '全片'} delay={delay_ms:.0f}ms")
            self.worker = threading.Thread(target=self._work, daemon=True,
                                           args=(video, fps, frames, quad, delay_ms))
            self.worker.start()

        def _work(self, video, fps, frames, quad, delay_ms):
            rc = run_pipeline(video, self.host.get().strip(), self.user.get().strip(),
                              Path(self.key.get().strip()), fps, frames, False, self._log,
                              self.proc_holder, quad=quad, start_delay_ms=delay_ms)
            self._log(f"流程结束，退出码={rc}")
            self.root.after(0, self._done)

        def _done(self):
            self.start_btn.configure(state="normal")
            self.stop_btn.configure(state="disabled")
            self.status.set("就绪")

        def _stop(self):
            # PC 进程由 run_pipeline 的 Popen.wait 管理；这里通过板端 pkill + 进程终止
            self._log("请求停止 ...")
            try:
                subprocess.run(_ssh_base(self.host.get().strip(), self.user.get().strip(),
                                         Path(self.key.get().strip())) +
                               ["pkill -f '[b]oard_yolo_udp.py' 2>/dev/null || true"],
                               capture_output=True, text=True, timeout=10)
            except Exception as exc:  # noqa: BLE001
                self._log(f"停止板端失败：{exc}")
            p = self.proc_holder.get("proc")
            if p is not None:
                _terminate_proc_tree(p)
            self._log("已发送停止；若窗口仍在，直接关闭窗口。")

        def _close(self):
            self._stop()
            self.root.destroy()

    root = tk.Tk()
    Launcher(root)
    root.mainloop()
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="板端 YOLO -> PC 单路 / 四路 3D 可视化启动器")
    ap.add_argument("--auto", action="store_true", help="无 GUI 直接跑")
    ap.add_argument("--video", default=None, help="单路视频；四路模式可省略")
    ap.add_argument("--quad", action="store_true", help="四路 3D：现场拼接四个源文件")
    ap.add_argument("--front", default=None)
    ap.add_argument("--right", default=None)
    ap.add_argument("--rear", default=None)
    ap.add_argument("--left", default=None)
    ap.add_argument("--host", default=DEFAULT_HOST)
    ap.add_argument("--user", default=DEFAULT_USER)
    ap.add_argument("--key", default=str(DEFAULT_KEY))
    ap.add_argument("--fps", type=float, default=15.0,
                    help="发送节拍；0=板端全速")
    ap.add_argument("--frames", type=int, default=0)
    ap.add_argument("--delay-ms", type=float, default=300.0,
                    help="板端 START 后 PC 开始拼接前的延时")
    ap.add_argument("--headless", action="store_true")
    ap.add_argument("--fpga-front", default=None,
                    help="只做 FPGA 传输：前向视频（左格 CH2）")
    ap.add_argument("--fpga-rear", default=None,
                    help="只做 FPGA 传输：后向视频（右格 CH3）")
    ap.add_argument("--fpga-fps", type=float, default=25.0,
                    help="FPGA 发送帧率，1~40")
    ap.add_argument("--fpga-frames", type=int, default=0,
                    help="转码帧数，0=全片")
    ap.add_argument("--fpga-infer", action="store_true",
                    help="FPGA HDMI -> 板端 USB 采集 -> 前向裁剪 -> YOLO")
    ap.add_argument("--fpga-triple", action="store_true",
                    help="三框同显：本地四路3D + FPGA前路 + FPGA四宫格整帧")
    ap.add_argument("--capture-device", default="0",
                    help="板端采集节点：0 或 /dev/video0")
    ap.add_argument("--capture-fps", type=float, default=15.0)
    ap.add_argument("--crop", default="auto",
                    help="FPGA 2x2 前向格裁剪 x,y,w,h 或 auto")
    ap.add_argument("--shots", type=int, default=0,
                    help="FPGA HDMI 推理时保存 N 张窗口截图")
    ap.add_argument("--out-dir", default=None)
    args = ap.parse_args()
    if args.fpga_triple:
        quad = {"front": args.front or args.video, "right": args.right,
                "rear": args.rear, "left": args.left}
        if not all(quad.values()):
            print("--fpga-triple 需要 --front/--right/--rear/--left（front 可用 --video）")
            raise SystemExit(2)
        paths = {k: Path(v) for k, v in quad.items()}
        raise SystemExit(run_fpga_infer(
            paths["front"], paths["rear"], args.host, args.user,
            Path(args.key), args.fpga_fps, args.capture_device,
            args.capture_fps, args.crop, args.fpga_frames,
            args.headless, print, shots=args.shots, out_dir=args.out_dir,
            triple=True, quad_paths=paths))
    if args.fpga_infer:
        if not (args.fpga_front and args.fpga_rear):
            print("--fpga-infer 需要 --fpga-front 与 --fpga-rear")
            raise SystemExit(2)
        raise SystemExit(run_fpga_infer(
            Path(args.fpga_front), Path(args.fpga_rear), args.host, args.user,
            Path(args.key), args.fpga_fps, args.capture_device,
            args.capture_fps, args.crop, args.fpga_frames,
            args.headless, print, shots=args.shots, out_dir=args.out_dir))
    if args.fpga_front or args.fpga_rear:
        if not (args.fpga_front and args.fpga_rear):
            print("--fpga-front 与 --fpga-rear 必须同时给出")
            raise SystemExit(2)
        raise SystemExit(run_fpga_send(Path(args.fpga_front), Path(args.fpga_rear),
                                       args.host, args.user, Path(args.key),
                                       args.fpga_fps, args.fpga_frames, print))
    if args.auto:
        quad = None
        video = args.video
        if args.quad:
            quad = {"front": args.front or args.video, "right": args.right,
                    "rear": args.rear, "left": args.left}
            if not all(quad.values()):
                print("--quad 需要 --front/--right/--rear/--left（front 可用 --video）")
                raise SystemExit(2)
            quad = {k: Path(v) for k, v in quad.items()}
            video = str(quad["front"])
        if not video:
            print("--auto 需要 --video，或 --quad 四路参数")
            raise SystemExit(2)
        raise SystemExit(run_pipeline(Path(video), args.host, args.user,
                                      Path(args.key), args.fps, args.frames,
                                      args.headless, print, quad=quad,
                                      start_delay_ms=args.delay_ms,
                                      shots=args.shots, out_dir=args.out_dir))
    raise SystemExit(_gui())
