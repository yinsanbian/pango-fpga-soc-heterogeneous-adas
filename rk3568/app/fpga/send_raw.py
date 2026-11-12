#!/usr/bin/env python3
"""Stream pre-decoded 960x540 RGB565 frames as YTM1 packets.

The mp4 decode is done once, offline (ffmpeg -> rawvideo rgb565be), so the send
loop is pure memory read + socket write. That removes the host CPU as the
bottleneck and lets us measure what the FPGA can actually absorb.
"""
import argparse
import socket
import struct
import time

import video_protocol as vp

WIDTH, HEIGHT = vp.WIDTH, vp.HEIGHT
PIXELS = vp.PIXELS_PER_PACKET
FRAME_BYTES = WIDTH * HEIGHT * 2


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--front", required=True, help="raw RGB565 for the LEFT tile (CH2)")
    ap.add_argument("--rear", required=True, help="raw RGB565 for the RIGHT tile (CH3)")
    ap.add_argument("--bind", default="10.10.20.1")
    ap.add_argument("--target", default="10.10.20.2")
    ap.add_argument("--port", type=int, default=5000)
    ap.add_argument("--fps", type=float, default=25.0)
    ap.add_argument("--frames", type=int, default=0, help="0 loops the file")
    ap.add_argument("--batch", type=int, default=1)
    args = ap.parse_args()

    files = {2: open(args.front, "rb"), 3: open(args.rear, "rb")}
    counts = {}
    for ch, f in files.items():
        f.seek(0, 2)
        counts[ch] = f.tell() // FRAME_BYTES
        f.seek(0)
    total = min(counts.values())
    print(f"frames available: front={counts[2]} rear={counts[3]} using {total}", flush=True)

    templates = []
    for off in range(0, WIDTH * HEIGHT, PIXELS):
        count = min(PIXELS, WIDTH * HEIGHT - off)
        for ch in (2, 3):
            buf = bytearray(vp.encode_packet(ch, 0, off, b"\x00" * (count * 2)))
            templates.append((ch, off * 2, count * 2, buf))

    sent = 0
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4 * 1024 * 1024)
        sock.bind((args.bind, 0))
        sock.connect((args.target, args.port))
        start = time.perf_counter()
        while not args.frames or sent < args.frames:
            idx = sent % total
            pixmap = {}
            for ch, f in files.items():
                f.seek(idx * FRAME_BYTES)
                pixmap[ch] = f.read(FRAME_BYTES)
            fid = struct.pack("!I", sent & 0xFFFFFFFF)
            for ch, ob, cb, buf in templates:
                buf[8:12] = fid
                buf[24:] = pixmap[ch][ob:ob + cb]

            send_start = time.perf_counter()
            deadline = max(start + (sent + 1) / args.fps, send_start)
            budget = deadline - send_start
            for i, item in enumerate(templates):
                sock.send(item[3])
                if args.batch > 0 and (i + 1) % args.batch == 0:
                    remain = send_start + budget * (i + 1) / len(templates) - time.perf_counter()
                    if remain > 0:
                        time.sleep(remain)
            sent += 1
            if sent % 25 == 0:
                print(f"frames={sent} achieved={sent / (time.perf_counter() - start):.2f}fps", flush=True)
    print(f"RAW_SEND_DONE frames={sent}")
    for f in files.values():
        f.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
