#!/usr/bin/env python3
"""Split a generated sheet into one PNG per object, and trim each.

    python references/tools/separate_sheet.py sheet.png --out-dir pieces/

ForgeGUI's `generation_gui` often returns several objects packed into one image
-- a wide button and an icon button side by side, say. Applied as a single
ImageLabel that sheet stretches both objects into one element, which is the
layering fault this works around. `auto_separate` is the intended remedy but it
requires a `project_id` an MCP client cannot obtain, so the split
happens here instead.

Objects are found by projection: fully transparent columns separate objects
horizontally, fully transparent rows separate them vertically. That is exact for
the grid layouts these sheets use, and it never guesses at overlapping art.
"""
from __future__ import annotations

import argparse
import pathlib
import sys

from PIL import Image

ALPHA_FLOOR = 8


def _runs(occupied: list[bool], min_gap: int) -> list[tuple[int, int]]:
    """Contiguous occupied spans, merging spans separated by a gap < min_gap."""
    spans: list[tuple[int, int]] = []
    start = None
    for index, value in enumerate(occupied + [False]):
        if value and start is None:
            start = index
        elif not value and start is not None:
            spans.append((start, index))
            start = None
    if not spans:
        return []
    merged = [spans[0]]
    for begin, end in spans[1:]:
        if begin - merged[-1][1] < min_gap:
            merged[-1] = (merged[-1][0], end)
        else:
            merged.append((begin, end))
    return merged


def separate(path: pathlib.Path, out_dir: pathlib.Path, min_gap: int, min_area: int) -> list[pathlib.Path]:
    image = Image.open(path).convert("RGBA")
    alpha = image.getchannel("A")
    width, height = image.size
    pixels = alpha.load()

    columns = [any(pixels[x, y] > ALPHA_FLOOR for y in range(height)) for x in range(width)]
    written: list[pathlib.Path] = []
    out_dir.mkdir(parents=True, exist_ok=True)

    for column_index, (left, right) in enumerate(_runs(columns, min_gap)):
        strip = image.crop((left, 0, right, height))
        strip_alpha = strip.getchannel("A")
        strip_pixels = strip_alpha.load()
        strip_width = right - left
        rows = [any(strip_pixels[x, y] > ALPHA_FLOOR for x in range(strip_width)) for y in range(height)]
        for row_index, (top, bottom) in enumerate(_runs(rows, min_gap)):
            piece = strip.crop((0, top, strip_width, bottom))
            box = piece.getchannel("A").point(lambda a: 255 if a > ALPHA_FLOOR else 0).getbbox()
            if not box:
                continue
            piece = piece.crop(box)
            if piece.size[0] * piece.size[1] < min_area:
                continue
            name = f"{path.stem}-{column_index}{row_index}.png"
            target = out_dir / name
            piece.save(target)
            written.append(target)
    return written


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sheet")
    parser.add_argument("--out-dir", default="pieces")
    parser.add_argument("--min-gap", type=int, default=12, help="transparent pixels that separate two objects")
    parser.add_argument("--min-area", type=int, default=4096, help="ignore fragments smaller than this")
    args = parser.parse_args()

    pieces = separate(pathlib.Path(args.sheet), pathlib.Path(args.out_dir), args.min_gap, args.min_area)
    if not pieces:
        print("no objects found", file=sys.stderr)
        return 1
    for piece in pieces:
        with Image.open(piece) as image:
            print(f"{piece}  {image.size[0]}x{image.size[1]}  aspect {image.size[0] / image.size[1]:.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
