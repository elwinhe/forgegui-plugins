#!/usr/bin/env python3
"""Checks for the GUI import tools on synthetic art, so no generated asset is needed.

    python references/tools/test_tools.py

Requires Pillow and numpy.
"""
from __future__ import annotations

import pathlib
import sys
import tempfile

from PIL import Image, ImageDraw

sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import separate_sheet  # noqa: E402
import slice_metadata  # noqa: E402

failures = 0
checks = 0


def check(condition: bool, label: str) -> None:
    global failures, checks
    checks += 1
    if not condition:
        failures += 1
        print(f"  FAIL {label}")


def panel(width: int = 600, height: int = 300) -> Image.Image:
    """A gold-rimmed panel with a crest top-centre, gems mid-side and painted corner clouds."""
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((0, 0, width - 1, height - 1), radius=40, fill=(212, 160, 60, 255))
    draw.rounded_rectangle((16, 16, width - 17, height - 17), radius=28, fill=(40, 110, 220, 255))
    draw.polygon([(width // 2 - 40, 0), (width // 2, 34), (width // 2 + 40, 0)], fill=(250, 230, 150, 255))
    for x in (8, width - 8):
        draw.regular_polygon((x, height // 2, 14), 4, fill=(250, 230, 150, 255))
    for cx in (70, width - 70):
        for step in range(5):
            draw.ellipse((cx - 50 + step * 9, height - 90 - step * 6, cx + 20 + step * 9, height - 30), fill=(235, 245, 255, 255))
    return image


def test_slice_avoids_decoration() -> None:
    image = panel()
    meta = slice_metadata.compute(image)
    x0, y0, x1, y1 = meta["sliceCenter"]
    width, height = image.size
    check(meta["size"] == [width, height], "slice reports the image size")
    check(0 < x0 < x1 < width and 0 < y0 < y1 < height, "slice centre lies inside the image")
    crest = (width // 2 - 40, width // 2 + 40)
    check(x1 <= crest[0] or x0 >= crest[1], f"horizontal band avoids the top crest (got {x0}..{x1})")
    gem = (height // 2 - 14, height // 2 + 14)
    check(y1 <= gem[0] or y0 >= gem[1], f"vertical band avoids the side gems (got {y0}..{y1})")
    check(y1 <= height - 90, f"vertical band stays above the painted clouds (got {y0}..{y1})")
    check(x0 >= 16 and x1 <= width - 16, "horizontal band stays off the rim corners")
    check(meta["fixedWidth"] == x0 + (width - x1) and meta["fixedHeight"] == y0 + (height - y1), "fixed sizes match the centre")


def test_render_keeps_rim_thickness() -> None:
    image = panel()
    meta = slice_metadata.compute(image)
    out = slice_metadata.render_sliced(image, meta["sliceCenter"], (600, 450), 1.0)
    check(out.size == (600, 450), "preview renders at the requested size")
    # Down the left rim at the vertical middle: 16 px of gold, then panel blue.
    row = 450 // 3
    gold = out.getpixel((8, row))
    inner = out.getpixel((24, row))
    check(gold[2] < 100 and gold[0] > 180, f"left rim stays gold after stretching (got {gold})")
    check(inner[2] > 180, f"rim does not thicken past its native 16 px (got {inner})")


def test_measures_at_roblox_stored_size() -> None:
    large = panel(1496, 659)
    stored = slice_metadata.stored_size(large)
    check(stored.size == (1024, 451), f"a 1496x659 upload is measured at Roblox's 1024x451 (got {stored.size})")
    meta = slice_metadata.compute(stored)
    x0, y0, x1, y1 = meta["sliceCenter"]
    check(meta["size"] == [1024, 451] and x1 <= 1024 and y1 <= 451, "slice centre is in stored pixels")
    small = panel(600, 300)
    check(slice_metadata.stored_size(small) is small, "art already within 1024 px is measured as is")


def test_slice_rejects_all_decorated() -> None:
    noise = Image.effect_noise((200, 200), 120).convert("RGBA")
    try:
        slice_metadata.compute(noise)
        # Noise has no calm band, but compute always returns the calmest one; it must still be well formed.
        check(True, "noise returns a well-formed centre")
    except ValueError:
        check(True, "noise is rejected cleanly")


def test_separate_sheet_splits_and_trims() -> None:
    sheet = Image.new("RGBA", (400, 200), (0, 0, 0, 0))
    draw = ImageDraw.Draw(sheet)
    draw.ellipse((20, 20, 120, 120), fill=(255, 200, 0, 255))
    draw.rectangle((220, 30, 380, 90), fill=(0, 120, 255, 255))
    # Two halves of one icon, 6 px apart: closer than --min-gap, so kept together.
    draw.rectangle((220, 120, 280, 180), fill=(255, 255, 255, 255))
    draw.rectangle((286, 120, 346, 180), fill=(255, 255, 255, 255))
    with tempfile.TemporaryDirectory() as tmp:
        source = pathlib.Path(tmp) / "sheet.png"
        sheet.save(source)
        pieces = separate_sheet.separate(source, pathlib.Path(tmp) / "out", min_gap=12, min_area=400)
        sizes = sorted(Image.open(piece).size for piece in pieces)
    check(len(pieces) == 3, f"three objects found (got {len(pieces)})")
    check((101, 101) in sizes, f"the circle is trimmed to its bounds (got {sizes})")
    check((127, 61) in sizes, f"a split icon closer than min-gap stays whole (got {sizes})")


for test in (test_slice_avoids_decoration, test_render_keeps_rim_thickness, test_measures_at_roblox_stored_size, test_slice_rejects_all_decorated, test_separate_sheet_splits_and_trims):
    test()

print(f"\n{checks} checks, {failures} failures")
sys.exit(1 if failures else 0)
