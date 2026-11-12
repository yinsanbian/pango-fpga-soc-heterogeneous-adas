"""接收板端/替身发来的 OBJECT/TRACK_V1，打印或落 ndjson（AVM3D 之外的调试口）。

AVM3D 本身用 `BoardSource(metadata.udp_port=7000)` 接收同一份报文；本脚本用于
在不开 3D 窗口时确认“板端 -> PC”链路。
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from dashboard.vision.transport import UdpDetectionReceiver  # noqa: E402


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="接收 YOLO OBJECT/TRACK_V1")
    ap.add_argument("--port", type=int, default=7000)
    ap.add_argument("--frames", type=int, default=0, help="0=一直收")
    ap.add_argument("--timeout", type=float, default=2.0)
    ap.add_argument("--json-out", default=None)
    args = ap.parse_args(argv)
    fh = None
    if args.json_out:
        p = Path(args.json_out)
        p.parent.mkdir(parents=True, exist_ok=True)
        fh = open(p, "w", encoding="utf-8", newline="\n")
    rx = UdpDetectionReceiver(port=args.port, timeout_s=args.timeout)
    print(f"[receive] listening udp :{rx.port}  (Ctrl+C 退出)")
    n = 0
    try:
        while not args.frames or n < args.frames:
            fd = rx.poll(args.timeout)
            if fd is None:
                continue
            n += 1
            top = fd.detections[0] if fd.detections else None
            extra = (f" top=c{top.class_id}:{top.score:.2f}" if top else "")
            print(f"frame {fd.frame_id:6d} n_obj={len(fd.detections)} "
                  f"n_trk={len(fd.tracks)} src={fd.source}{extra}")
            if fh is not None:
                doc = {
                    "frame_id": fd.frame_id, "source": fd.source,
                    "objects": [
                        {"class_id": d.class_id, "score": d.score,
                         "bbox_xyxy": list(d.bbox_xyxy),
                         "distance_status": d.distance_status}
                        for d in fd.detections
                    ],
                    "tracks": [
                        {"track_id": t.track_id, "class_id": t.class_id,
                         "state": t.state, "score": t.score,
                         "bbox_xyxy": list(t.bbox_xyxy)}
                        for t in fd.tracks
                    ],
                }
                fh.write(json.dumps(doc, ensure_ascii=False) + "\n")
    except KeyboardInterrupt:
        pass
    finally:
        rx.close()
        if fh is not None:
            fh.close()
    print(f"[receive] {n} frames; {rx.stats()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
