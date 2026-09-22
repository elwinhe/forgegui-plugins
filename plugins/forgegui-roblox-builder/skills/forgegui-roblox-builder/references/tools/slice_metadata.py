#!/usr/bin/env python3
"""Compute 9-slice metadata for a generated panel or button, and preview it.

    python references/tools/slice_metadata.py panel.png
    python references/tools/slice_metadata.py panel.png --preview 720x400 --out preview.png

A generated `gui_panel` or `gui_button` arrives as one fixed-aspect image with a
decorated rim: gold trim, corner flourishes, a crest on the top edge, gems at
the middle of the sides. Stretched with `ScaleType.Stretch` to any other aspect,
the rim thickens and the corners smear. `ScaleType.Slice` fixes that, but only
if `SliceCenter` marks bands that are safe to stretch -- and a band that crosses
a gem or a crest stretches the decoration instead of the plain trim.

The tool finds those bands from the pixels. Each row and column gets a stretch
cost: how much it differs from its neighbour, how much its rim strips differ,
and how much detail runs along it. The calmest band of rows and of columns, away
from the corners, becomes the centre rect; everything outside it keeps its
pixels. Painted interiors (clouds, scenery) still limit how far a panel can
stretch: past roughly 1.5x its native aspect, ask the generator for a plain
interior instead.

Roblox stores an uploaded image at no more than 1024 pixels on its longer side,
and `SliceCenter` is read in the stored pixels. The art is therefore measured at
that size (`--max-side`, default 1024): a 1496x659 panel is measured as 1024x451,
and metadata taken from the original would slice the wrong pixels in game.

Output is JSON: image size, `sliceCenter` as [x0, y0, x1, y1] in image pixels
(the order of `Rect.new`), and the fixed widths that set the smallest size the
art can take at a given `SliceScale`.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

import numpy as np
from PIL import Image

ROBLOX_MAX_SIDE = 1024
RIM_FRACTION = 0.12
EDGE_MARGIN = 0.12
WINDOW_FRACTION = 0.06
GROW_RATIO = 1.5
PAD_FRACTION = 0.02
# Line scores are mean absolute differences in 0-255 units. Flat art defeats a
# purely relative growth rule: its calmest window scores about the same as every
# other interior line (grain, dither, a soft gradient -- all ~1-2 units), so
# "1.5x the calmest" stops at the first line that is a hair noisier, and a panel
# whose only fixed parts are 8 px corners is reported as 270 px of fixed height.
# So the limit is never allowed below twice the interior's own typical line,
# capped so an ornate interior (where the typical line IS detail) cannot use the
# allowance to grow into its decoration.
NOISE_MULTIPLE = 2.0
NOISE_CAP = 3.0


def _line_scores(pixels: np.ndarray, axis: int) -> np.ndarray:
    """How costly it is to stretch across each line, one score per pixel line.

    axis 0 scores rows (vertical stretch), axis 1 scores columns (horizontal
    stretch). Two things make a line expensive: it differs from its neighbour
    (stretching repeats a step), or it carries detail along its length, such as
    a cloud edge or a gem, which stretching turns into streaks. The rim strips
    are measured separately and count double, because a seam in the trim is the
    most visible failure.
    """
    height, width, _ = pixels.shape
    rim_x = max(2, int(width * RIM_FRACTION))
    rim_y = max(2, int(height * RIM_FRACTION))
    if axis == 0:
        rim = np.concatenate([pixels[:, :rim_x, :], pixels[:, width - rim_x :, :]], axis=1)
        step = np.abs(np.diff(pixels, axis=0)).mean(axis=(1, 2))
        rim_step = np.abs(np.diff(rim, axis=0)).mean(axis=(1, 2))
        detail = np.abs(np.diff(pixels[:, rim_x : width - rim_x, :], axis=1)).mean(axis=(1, 2))
    else:
        rim = np.concatenate([pixels[:rim_y, :, :], pixels[height - rim_y :, :, :]], axis=0)
        step = np.abs(np.diff(pixels, axis=1)).mean(axis=(0, 2))
        rim_step = np.abs(np.diff(rim, axis=1)).mean(axis=(0, 2))
        detail = np.abs(np.diff(pixels[rim_y : height - rim_y, :, :], axis=0)).mean(axis=(0, 2))
    step = np.concatenate([step[:1], step])
    rim_step = np.concatenate([rim_step[:1], rim_step])
    return step + 2.0 * rim_step + detail


def _best_band(scores: np.ndarray) -> tuple[int, int]:
    """The calmest window of lines away from the edges, grown while its neighbours stay calm."""
    total = len(scores)
    margin = int(total * EDGE_MARGIN)
    lo, hi = margin, total - margin
    window = max(2, int(total * WINDOW_FRACTION))
    if hi - lo < window:
        raise ValueError("image too small to slice")
    sums = np.convolve(scores[lo:hi], np.ones(window), mode="valid")
    begin = lo + int(np.argmin(sums))
    end = begin + window
    noise = min(float(np.median(scores[lo:hi])) * NOISE_MULTIPLE, NOISE_CAP)
    limit = max((sums.min() / window) * GROW_RATIO, noise)
    # The margin keeps the SEARCH off the rim; growth may run past it, because the
    # rim's own scores are what stop it. Holding growth at the margin reported a
    # 12% fixed border on art whose rim is a one-pixel hairline.
    while begin > 1 and scores[begin - 1] <= limit:
        begin -= 1
    while end < total - 1 and scores[end] <= limit:
        end += 1
    # The first lines of a decoration score low -- the tip of a gem or crest is only a
    # few pixels wide -- so the band keeps a safety pad from wherever it stopped.
    pad = max(1, int(total * PAD_FRACTION))
    if end - begin > 2 * pad + 2:
        begin, end = begin + pad, end - pad
    return begin, end


def stored_size(image: Image.Image, max_side: int = ROBLOX_MAX_SIDE) -> Image.Image:
    """The image as Roblox keeps it: scaled down so its longer side is at most max_side."""
    width, height = image.size
    longest = max(width, height)
    if longest <= max_side:
        return image
    scale = max_side / longest
    return image.resize((max(1, round(width * scale)), max(1, round(height * scale))), Image.LANCZOS)


def compute(image: Image.Image) -> dict:
    pixels = np.asarray(image.convert("RGBA")).astype(np.int16)
    height, width, _ = pixels.shape
    y0, y1 = _best_band(_line_scores(pixels, 0))
    x0, x1 = _best_band(_line_scores(pixels, 1))
    return {
        "size": [width, height],
        "sliceCenter": [x0, y0, x1, y1],
        "fixedWidth": x0 + (width - x1),
        "fixedHeight": y0 + (height - y1),
        "note": "Rect.new(x0, y0, x1, y1). At SliceScale s the art needs at least fixedWidth*s by fixedHeight*s.",
    }


def render_sliced(image: Image.Image, center: list[int], size: tuple[int, int], scale: float) -> Image.Image:
    """Approximates Roblox ScaleType.Slice: corners scaled by `scale`, edges stretched one way, centre both."""
    source = image.convert("RGBA")
    width, height = source.size
    x0, y0, x1, y1 = center
    target_w, target_h = size
    xs = [0, x0, x1, width]
    ys = [0, y0, y1, height]
    left, right = round(x0 * scale), round((width - x1) * scale)
    top, bottom = round(y0 * scale), round((height - y1) * scale)
    txs = [0, left, max(left, target_w - right), target_w]
    tys = [0, top, max(top, target_h - bottom), target_h]
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    for row in range(3):
        for column in range(3):
            box = (xs[column], ys[row], xs[column + 1], ys[row + 1])
            dest_w = txs[column + 1] - txs[column]
            dest_h = tys[row + 1] - tys[row]
            if dest_w <= 0 or dest_h <= 0 or box[2] <= box[0] or box[3] <= box[1]:
                continue
            piece = source.crop(box).resize((dest_w, dest_h), Image.BILINEAR)
            out.alpha_composite(piece, (txs[column], tys[row]))
    return out


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("image", type=pathlib.Path)
    parser.add_argument("--preview", help="WIDTHxHEIGHT to render a sliced preview at")
    parser.add_argument("--scale", type=float, default=None, help="SliceScale for the preview (default: fit)")
    parser.add_argument("--out", type=pathlib.Path, default=None)
    parser.add_argument(
        "--max-side",
        type=int,
        default=ROBLOX_MAX_SIDE,
        help="measure at the size Roblox stores the upload (longer side, default 1024)",
    )
    args = parser.parse_args(argv)

    image = stored_size(Image.open(args.image), args.max_side)
    try:
        metadata = compute(image)
    except ValueError as error:
        print(f"{args.image}: {error}", file=sys.stderr)
        return 1
    print(json.dumps(metadata, indent=2))

    if args.preview:
        target_w, target_h = (int(part) for part in args.preview.lower().split("x"))
        scale = args.scale
        if scale is None:
            scale = min(target_w / metadata["size"][0], target_h / metadata["size"][1])
        preview = render_sliced(image, metadata["sliceCenter"], (target_w, target_h), scale)
        out = args.out or args.image.with_name(f"{args.image.stem}-sliced-{target_w}x{target_h}.png")
        preview.save(out)
        print(f"preview: {out} (SliceScale {scale:.3f})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
