#!/usr/bin/env python3
"""Write a soft black-alpha gradient PNG for contact shadows and passage shade.

    python references/tools/make_gradient.py --shape round  contact_round.png
    python references/tools/make_gradient.py --shape rect   contact_rect.png   # also passage shade
    python references/tools/make_gradient.py --shape band   band.png           # dark centre line, clear ends
    python references/tools/make_gradient.py --shape vertical wall_base.png    # opaque bottom, clear top
    python references/tools/make_gradient.py --selftest

Upload the PNG as an Image (references/asset-upload.md) and pass its rbxassetid:// to
ContactShadows (`textures.round` / `textures.rect`) or PassageShade (`texture`). The colour is
black everywhere; the gradient lives in alpha, and the Decal's Transparency sets the strength.

Shapes use a normalised distance d from the centre (0) to the edge (1):
  round     d = radius                     (a soft pool)
  rect      d = superellipse, exponent 4   (a rounded rectangle: buildings, walls, passages)
  band      d = |x|                        (fades along one axis only)
  vertical  d = 1 - y from the bottom      (darkest at the bottom row)
alpha = (1 - d) ** power, power 1.4 by default. That curve matches the contact-shadow
textures shipped in the build this came from (alpha 13/255 one sixteenth in from the edge,
101/255 at a quarter, 253/255 at the centre). Standard library only.
"""
import argparse
import struct
import sys
import tempfile
import zlib
from pathlib import Path

SHAPES = ("round", "rect", "band", "vertical")
RECT_EXPONENT = 4.0


def distance(shape: str, u: float, v: float) -> float:
    """u, v in [-1, 1] across the image (v = 1 at the bottom). Returns d >= 0."""
    if shape == "round":
        return (u * u + v * v) ** 0.5
    if shape == "rect":
        return (abs(u) ** RECT_EXPONENT + abs(v) ** RECT_EXPONENT) ** (1 / RECT_EXPONENT)
    if shape == "band":
        return abs(u)
    if shape == "vertical":
        return (1 - v) / 2
    raise ValueError(f"unknown shape {shape!r}; choose from {', '.join(SHAPES)}")


def alpha_rows(shape: str, size: int, power: float) -> list:
    rows = []
    for y in range(size):
        v = (y + 0.5) / size * 2 - 1
        row = bytearray()
        for x in range(size):
            u = (x + 0.5) / size * 2 - 1
            d = min(distance(shape, u, v), 1.0)
            row.append(round(255 * (1 - d) ** power))
        rows.append(bytes(row))
    return rows


def encode_png(rows: list, size: int) -> bytes:
    """Greyscale + alpha (colour type 4), grey fixed at 0 (black)."""
    raw = b"".join(b"\x00" + b"".join(b"\x00" + bytes([a]) for a in row) for row in rows)

    def chunk(kind: bytes, data: bytes) -> bytes:
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", size, size, 8, 4, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def decode_alpha(data: bytes) -> tuple:
    """Reads back what encode_png wrote (filter 0 only). Returns (size, rows of alpha)."""
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos, idat, size = 8, b"", 0
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind, body = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            size = struct.unpack(">I", body[:4])[0]
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    raw = zlib.decompress(idat)
    stride = 1 + size * 2
    rows = []
    for y in range(size):
        line = raw[y * stride:(y + 1) * stride]
        assert line[0] == 0, "unexpected PNG filter"
        rows.append(line[2::2])
    return size, rows


def write(shape: str, out: Path, size: int = 256, power: float = 1.4) -> Path:
    if size < 8 or size > 2048:
        raise ValueError("size must be between 8 and 2048")
    if not 0.2 <= power <= 6:
        raise ValueError("power must be between 0.2 and 6")
    out.write_bytes(encode_png(alpha_rows(shape, size, power), size))
    return out


def selftest() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        for shape in SHAPES:
            path = write(shape, Path(tmp) / f"{shape}.png", 64)
            size, rows = decode_alpha(path.read_bytes())
            assert size == 64 and len(rows) == 64, f"{shape}: wrong size"
            mid = rows[32]
            if shape == "vertical":
                assert rows[-1][32] >= 245 and rows[0][32] <= 10, f"{shape}: bottom dark, top clear"
                column = [rows[y][32] for y in range(64)]
                assert column == sorted(column), f"{shape}: alpha must rise toward the bottom"
                continue
            assert mid[32] >= 240, f"{shape}: centre must be near opaque, got {mid[32]}"
            assert mid[0] <= 12 and mid[63] <= 12, f"{shape}: edges must be near clear"
            assert list(mid[32:]) == sorted(mid[32:], reverse=True), f"{shape}: must fall off from the centre"
            assert mid[:32] == bytes(reversed(mid[32:])), f"{shape}: must be symmetric"
        _, rect = decode_alpha(write("rect", Path(tmp) / "r.png", 64).read_bytes())
        _, rnd = decode_alpha(write("round", Path(tmp) / "c.png", 64).read_bytes())
        assert rect[12][12] > rnd[12][12], "rect must hold its corners darker than round"
        _, band = decode_alpha(write("band", Path(tmp) / "b.png", 64).read_bytes())
        assert band[0][32] == band[63][32] == band[32][32], "band must not fade across its length"
        try:
            write("star", Path(tmp) / "x.png", 64)
        except ValueError:
            pass
        else:
            raise AssertionError("an unknown shape must be rejected")
    print("make_gradient selftest: ok")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("out", nargs="?", type=Path)
    parser.add_argument("--shape", choices=SHAPES, default="round")
    parser.add_argument("--size", type=int, default=256)
    parser.add_argument("--power", type=float, default=1.4)
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()
    if args.selftest:
        selftest()
        return
    if not args.out:
        parser.error("give an output path, or --selftest")
    try:
        path = write(args.shape, args.out, args.size, args.power)
    except (ValueError, OSError) as err:
        sys.exit(f"make_gradient: {err}")
    print(f"wrote {path} ({args.shape}, {args.size}x{args.size}, power {args.power})")


if __name__ == "__main__":
    main()
