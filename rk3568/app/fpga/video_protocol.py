"""YTM1 wire contract shared by the video sender and offline validation."""
from __future__ import annotations
import struct

MAGIC = b"YTM1"
VERSION = 1
RGB565 = 1
WIDTH = 960
HEIGHT = 540
PIXELS_PER_PACKET = 512
HEADER = struct.Struct("!4sBBBBIIHHHH")


def encode_packet(channel: int, frame_id: int, pixel_offset: int, pixels_be: bytes,
                  width: int = WIDTH, height: int = HEIGHT) -> bytes:
    count = len(pixels_be) // 2
    if len(pixels_be) % 2 or not (0 <= channel < 4):
        raise ValueError("RGB565 needs two bytes per pixel and channel 0..3")
    if not (0 < count <= PIXELS_PER_PACKET and count % 16 == 0 and pixel_offset % 16 == 0):
        raise ValueError("offset/count must be aligned to 16 pixels; count must be 16..512")
    if not (0 <= pixel_offset and pixel_offset + count <= width * height):
        raise ValueError("packet exceeds the frame")
    return HEADER.pack(MAGIC, VERSION, channel, RGB565, 0, frame_id & 0xFFFFFFFF,
                       pixel_offset, count, width, height, 0) + pixels_be


def decode_packet(packet: bytes) -> tuple[dict[str, int], bytes]:
    if len(packet) < HEADER.size:
        raise ValueError("truncated header")
    magic, version, channel, fmt, flags, frame, offset, count, width, height, reserved = HEADER.unpack_from(packet)
    if (magic, version, fmt, flags, reserved) != (MAGIC, VERSION, RGB565, 0, 0):
        raise ValueError("unsupported header")
    if (width, height) != (WIDTH, HEIGHT):
        raise ValueError("expected 960x540")
    payload = packet[HEADER.size:]
    # Reuse exactly the sender's bounds/alignment checks.
    encode_packet(channel, frame, offset, payload, width, height)
    if len(payload) != count * 2:
        raise ValueError("declared pixel count does not match datagram length")
    return dict(channel=channel, frame_id=frame, pixel_offset=offset,
                pixel_count=count, width=width, height=height), payload


def frame_packets(channel: int, frame_id: int, pixels_be: bytes):
    if len(pixels_be) != WIDTH * HEIGHT * 2:
        raise ValueError("frame must contain exactly 960x540 RGB565 pixels")
    for offset in range(0, WIDTH * HEIGHT, PIXELS_PER_PACKET):
        chunk = pixels_be[offset * 2:(offset + PIXELS_PER_PACKET) * 2]
        yield encode_packet(channel, frame_id, offset, chunk)
