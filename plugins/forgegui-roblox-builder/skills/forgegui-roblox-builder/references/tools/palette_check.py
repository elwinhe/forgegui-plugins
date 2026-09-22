#!/usr/bin/env python3
"""Find colour a generation invented that the project never asked for.

    python references/tools/palette_check.py art.png --project forgegui-project.json
    python references/tools/palette_check.py art.png --palette "#111820,#D9A54A" --map off.png

The reliable tell that art was generated rather than authored is rarely the
shapes -- it is a hue nobody chose. A weapon sheet prompted for off-white and
amber came back with 10% of its opaque pixels green, not as an anti-aliasing
fringe but painted into the artwork. At icon size it reads as dirt on the
silhouette, and across a screen it is what makes a UI look assembled from stock
rather than designed.

Judged on **hue angle alone.** A pixel is on-palette when its CIELAB hue sits
within a few degrees of some palette entry's hue. Neither lightness nor
saturation is considered, and that is the whole point: shading, highlights, rim
light and a punchier accent are all the same hue at different lightness or
chroma, and any distance-based check condemns every one of them. Measuring the
angle instead isolates the actual defect -- a hue nobody chose. On one real
sheet that is the difference between flagging a brighter amber (same hue, fine)
and flagging pure green 60 degrees away from anything in the palette.

Near-neutral pixels (grey, white, black, and the desaturated body of most
industrial art) are judged separately: they pass when the palette itself
contains a neutral, which nearly every game palette does.

Exits non-zero when off-palette coverage exceeds --threshold, so it can gate a
UI pass. Requires Pillow and numpy; runs locally, no network.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

import numpy as np
from PIL import Image

sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from style_delta import srgb_to_lab  # noqa: E402

ALPHA_FLOOR = 8
OPAQUE_FLOOR = 250
# Degrees of CIELAB hue a pixel may sit from the nearest palette hue.
DEFAULT_TOLERANCE = 20.0
# Below this chroma a colour carries no usable hue and is treated as neutral.
# Kept low on purpose: a moody palette's darks are desaturated but still hued
# (#111820 is chroma 7 at hue 265), and a higher cutoff drops them from the
# comparison, which then condemns the very shades the project is built from.
NEUTRAL_CHROMA = 4.0
DEFAULT_THRESHOLD = 1.0


def parse_palette(text: str) -> list[str]:
    out = []
    for chunk in text.replace(";", ",").split(","):
        chunk = chunk.strip().lstrip("#")
        if len(chunk) == 6:
            out.append("#" + chunk.upper())
    return out


def hex_to_lab(colors: list[str]) -> np.ndarray:
    rgb = np.array([[int(c[i : i + 2], 16) / 255 for i in (1, 3, 5)] for c in colors], dtype=np.float64)
    return srgb_to_lab(rgb)


def analyse(image: Image.Image, colors: list[str], tolerance: float) -> dict:
    rgba = np.asarray(image.convert("RGBA"), dtype=np.float64)
    flat = rgba.reshape(-1, 4)
    visible = flat[flat[:, 3] > ALPHA_FLOOR]
    if visible.size == 0:
        return {"pixels": 0, "off": 0, "share": 0.0, "offenders": [], "mask": None}

    lab = srgb_to_lab(visible[:, :3] / 255.0)
    palette = hex_to_lab(colors)
    chroma = np.linalg.norm(lab[:, 1:], axis=1)
    palette_chroma = np.linalg.norm(palette[:, 1:], axis=1)
    palette_has_neutral = bool((palette_chroma < NEUTRAL_CHROMA).any())

    # Only a chromatic palette entry has a hue to compare against.
    chromatic = palette[palette_chroma >= NEUTRAL_CHROMA]
    hue = np.degrees(np.arctan2(lab[:, 2], lab[:, 1]))
    if chromatic.shape[0]:
        palette_hue = np.degrees(np.arctan2(chromatic[:, 2], chromatic[:, 1]))
        gap = np.abs((hue[:, None] - palette_hue[None, :] + 180) % 360 - 180)
        nearest = gap.min(axis=1)
    else:
        nearest = np.full(lab.shape[0], 180.0)

    neutral = chroma < NEUTRAL_CHROMA
    off = np.where(neutral, not palette_has_neutral, nearest > tolerance)

    offenders = []
    if off.any():
        bad = visible[off][:, :3].astype(int)
        # Cluster coarsely so the report names a few colours, not thousands. The
        # representative is each cluster's MEAN, not the bucket floor: rounding
        # down lands on a grey that is not the colour actually flagged, and then
        # the printed hue distance does not match the printed hex.
        keys = (bad // 16) * 16
        uniq, inverse, counts = np.unique(keys, axis=0, return_inverse=True, return_counts=True)
        order = np.argsort(-counts)[:6]
        means = np.stack([bad[inverse == index].mean(axis=0) for index in order])
        bad_lab = srgb_to_lab(means / 255.0)
        bad_hue = np.degrees(np.arctan2(bad_lab[:, 2], bad_lab[:, 1]))
        hued = palette_chroma >= NEUTRAL_CHROMA
        all_hue = np.degrees(np.arctan2(palette[hued][:, 2], palette[hued][:, 1]))
        hued_names = [c for c, keep in zip(colors, hued) if keep]
        bad_distance = np.abs((bad_hue[:, None] - all_hue[None, :] + 180) % 360 - 180)
        for row, index in enumerate(order):
            r, g, b = (int(round(v)) for v in means[row])
            near = int(bad_distance[row].argmin())
            offenders.append(
                {
                    "hex": f"#{r:02X}{g:02X}{b:02X}",
                    "pixels": int(counts[index]),
                    "share": float(counts[index]) / len(visible),
                    "nearest": hued_names[near],
                    "degrees": float(bad_distance[row][near]),
                }
            )

    mask = None
    if off.any():
        alpha = rgba[..., 3].reshape(-1)
        full = np.zeros(alpha.shape, dtype=bool)
        full[alpha > ALPHA_FLOOR] = off
        mask = full.reshape(rgba.shape[:2])

    opaque = visible[:, 3] > OPAQUE_FLOOR
    return {
        "pixels": int(len(visible)),
        "off": int(off.sum()),
        "share": float(off.sum()) / len(visible),
        "off_opaque": int((off & opaque).sum()),
        "offenders": offenders,
        "mask": mask,
    }


def lab_to_srgb(lab: np.ndarray) -> np.ndarray:
    """CIELAB back to sRGB 0..1 under D65, clipped to gamut."""
    fy = (lab[:, 0] + 16) / 116
    fx = fy + lab[:, 1] / 500
    fz = fy - lab[:, 2] / 200
    epsilon = 216 / 24389
    kappa = 24389 / 27
    def expand(t):
        cube = t ** 3
        return np.where(cube > epsilon, cube, (116 * t - 16) / kappa)
    xyz = np.stack([expand(fx), expand(fy), expand(fz)], axis=1) * np.array([0.95047, 1.0, 1.08883])
    matrix = np.array([
        [3.2404542, -1.5371385, -0.4985314],
        [-0.9692660, 1.8760108, 0.0415560],
        [0.0556434, -0.2040259, 1.0572252],
    ])
    linear = np.clip(xyz @ matrix.T, 0, 1)
    return np.where(linear <= 0.0031308, linear * 12.92, 1.055 * linear ** (1 / 2.4) - 0.055)


def repair(image: Image.Image, colors: list[str], tolerance: float) -> tuple[Image.Image, int]:
    """Rotate every off-palette pixel's hue onto the nearest palette hue.

    Lightness is kept exactly and chroma only clamped to the palette's own
    maximum, so shading, highlights and the silhouette survive; what changes is
    the one thing that was wrong. A negative prompt cannot do this -- asking for
    "no green" just moved the contamination to magenta on the next run -- because
    the colour is painted into opaque pixels by the generator, not prompted.
    """
    rgba = np.asarray(image.convert("RGBA"), dtype=np.float64).copy()
    shape = rgba.shape[:2]
    flat = rgba.reshape(-1, 4)
    seen = flat[:, 3] > ALPHA_FLOOR
    if not seen.any():
        return image, 0

    palette = hex_to_lab(colors)
    palette_chroma = np.linalg.norm(palette[:, 1:], axis=1)
    hued = palette[palette_chroma >= NEUTRAL_CHROMA]
    if hued.shape[0] == 0:
        return image, 0
    palette_hue = np.degrees(np.arctan2(hued[:, 2], hued[:, 1]))
    ceiling = float(palette_chroma.max())

    lab = srgb_to_lab(flat[seen][:, :3] / 255.0)
    chroma = np.linalg.norm(lab[:, 1:], axis=1)
    hue = np.degrees(np.arctan2(lab[:, 2], lab[:, 1]))
    gap = np.abs((hue[:, None] - palette_hue[None, :] + 180) % 360 - 180)
    off = (chroma >= NEUTRAL_CHROMA) & (gap.min(axis=1) > tolerance)
    if not off.any():
        return image, 0

    target = np.radians(palette_hue[gap[off].argmin(axis=1)])
    held = np.minimum(chroma[off], ceiling)
    fixed = lab[off].copy()
    fixed[:, 1] = held * np.cos(target)
    fixed[:, 2] = held * np.sin(target)

    block = flat[seen]
    block[off, :3] = lab_to_srgb(fixed) * 255.0
    flat[seen] = block
    return Image.fromarray(np.clip(flat.reshape(*shape, 4), 0, 255).astype(np.uint8), "RGBA"), int(off.sum())


def write_map(image: Image.Image, mask: np.ndarray, target: pathlib.Path) -> None:
    """The artwork dimmed, with every off-palette pixel flagged magenta."""
    base = image.convert("RGBA")
    dim = np.asarray(base, dtype=np.float64)
    dim[..., :3] *= 0.25
    dim[mask, 0], dim[mask, 1], dim[mask, 2] = 255, 0, 255
    dim[mask, 3] = 255
    Image.fromarray(dim.astype(np.uint8), "RGBA").save(target)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("images", nargs="+")
    parser.add_argument("--palette", help="comma-separated hex colours")
    parser.add_argument("--project", help="forgegui-project.json to read `palette` from")
    parser.add_argument("--tolerance", type=float, default=DEFAULT_TOLERANCE, help="degrees of hue that still count as the same colour")
    parser.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD, help="percent off-palette that fails the check")
    parser.add_argument("--map", help="write an off-palette map for the first image")
    parser.add_argument("--fix", action="store_true", help="rewrite each image in place with off-palette hues rotated onto the palette")
    args = parser.parse_args()

    colors: list[str] = []
    if args.project:
        colors = parse_palette(",".join(json.loads(pathlib.Path(args.project).read_text(encoding="utf-8"))["palette"]))
    if args.palette:
        colors += parse_palette(args.palette)
    if not colors:
        print("no palette: pass --palette or --project", file=sys.stderr)
        return 2

    print(f"palette ({len(colors)}): {' '.join(colors)}\n")
    worst = 0.0
    for index, name in enumerate(args.images):
        path = pathlib.Path(name)
        with Image.open(path) as image:
            result = analyse(image, colors, args.tolerance)
            if args.map and index == 0 and result["mask"] is not None:
                write_map(image, result["mask"], pathlib.Path(args.map))
        share = result["share"] * 100
        worst = max(worst, share)
        flag = "FAIL" if share > args.threshold else "ok  "
        print(f"{flag} {path.name:<26} {share:5.2f}% off-palette  ({result['off']}/{result['pixels']} px)")
        for bad in result["offenders"]:
            print(f"       {bad['hex']}  {bad['share']*100:5.2f}%  nearest {bad['nearest']}, {bad['degrees']:.0f}° off")
        if args.fix and result["off"]:
            with Image.open(path) as image:
                repaired, changed = repair(image, colors, args.tolerance)
            repaired.save(path)
            print(f"       repaired {changed} px -> {path}")

    if args.map:
        print(f"\noff-palette map: {args.map}")
    print(f"\nworst: {worst:.2f}%  (threshold {args.threshold}%)")
    return 1 if worst > args.threshold else 0


if __name__ == "__main__":
    sys.exit(main())
