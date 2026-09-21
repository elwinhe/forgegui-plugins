#!/usr/bin/env python3
"""Compare the palettes of two runs, and render the evidence.

    python references/tools/style_delta.py runs/ref-a/ runs/ref-b/ --contact-sheet delta.png

This is a diagnostic, not a test of whether a style reference worked. It
measures one property -- colour -- of outputs you already have. Point it at two
directories with matching filenames when two comparable runs exist; do not
commission extra paid generations to produce a number.

The number is an unweighted palette-center distance in CIELAB delta-E (CIE76).
It ignores color proportions and spatial arrangement: near-zero means matched
centers are close, not equal color distributions or style. Reversing 90/10
red/blue shares can score nearly zero. Inspect the contact sheet as well.
The default threshold of 5.0 is advisory, not a validated whole-image or style
threshold; a single-color just-noticeable difference does not validate one.
Absolute hue distance and signed saturation/value deltas are reported alongside.
Successful measurements exit 0 regardless of magnitude; no matching pairs is an
error. Fully transparent inputs contain insufficient color evidence, even if the
legacy diagnostic returns zero; do not interpret that as equivalence.

A palette distance cannot establish cause. Two runs of the same prompt differ on
their own, so ordinary generation variance can clear the threshold with no style
effect at all, and a reference that genuinely changed shape, material,
composition or line weight while holding the colours can land below it. Judge
adherence by comparing each output against the reference itself, alongside
whatever conditioning evidence the call returned: the style pin echoed back, the
`style_application` in force, which reference IDs were accepted, or an
`unsupported_style_conditioning` rejection. Use these numbers to describe a
difference, never to prove one.

Only pixels above the alpha floor are measured. Generated GUI art is mostly
transparent background, and averaging that in drags every palette toward the
same grey -- it would make two genuinely different styles look identical.

Requires Pillow and numpy. Runs locally on the artifact files; no network.
"""
from __future__ import annotations

import argparse
import itertools
import pathlib
import sys

import numpy as np
from PIL import Image

ALPHA_FLOOR = 8
DEFAULT_COLORS = 5
JND = 2.3
DEFAULT_THRESHOLD = 5.0
KMEANS_ITERATIONS = 24
SUFFIXES = {".png", ".jpg", ".jpeg", ".webp"}


def opaque_pixels(image: Image.Image) -> np.ndarray:
    """Non-transparent pixels as an (N, 3) float array in 0..1."""
    rgba = np.asarray(image.convert("RGBA"), dtype=np.float64)
    flat = rgba.reshape(-1, 4)
    kept = flat[flat[:, 3] > ALPHA_FLOOR]
    if kept.size == 0:
        return np.zeros((0, 3), dtype=np.float64)
    return kept[:, :3] / 255.0


def srgb_to_lab(rgb: np.ndarray) -> np.ndarray:
    """sRGB 0..1 to CIELAB under a D65 white point."""
    if rgb.size == 0:
        return np.zeros((0, 3), dtype=np.float64)
    linear = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    matrix = np.array(
        [
            [0.4124564, 0.3575761, 0.1804375],
            [0.2126729, 0.7151522, 0.0721750],
            [0.0193339, 0.1191920, 0.9503041],
        ]
    )
    xyz = linear @ matrix.T
    white = np.array([0.95047, 1.00000, 1.08883])
    scaled = xyz / white
    epsilon = 216 / 24389
    kappa = 24389 / 27
    f = np.where(scaled > epsilon, np.cbrt(scaled), (kappa * scaled + 16) / 116)
    return np.stack(
        [116 * f[:, 1] - 16, 500 * (f[:, 0] - f[:, 1]), 200 * (f[:, 1] - f[:, 2])],
        axis=1,
    )


def rgb_to_hsv(rgb: np.ndarray) -> np.ndarray:
    """sRGB 0..1 to HSV, hue in degrees."""
    if rgb.size == 0:
        return np.zeros((0, 3), dtype=np.float64)
    high = rgb.max(axis=1)
    low = rgb.min(axis=1)
    span = high - low
    hue = np.zeros_like(high)
    safe = span > 1e-12
    red, green, blue = rgb[:, 0], rgb[:, 1], rgb[:, 2]
    is_red = safe & (high == red)
    is_green = safe & (high == green) & ~is_red
    is_blue = safe & ~is_red & ~is_green
    with np.errstate(invalid="ignore", divide="ignore"):
        hue[is_red] = ((green - blue)[is_red] / span[is_red]) % 6
        hue[is_green] = ((blue - red)[is_green] / span[is_green]) + 2
        hue[is_blue] = ((red - green)[is_blue] / span[is_blue]) + 4
    hue = (hue * 60) % 360
    saturation = np.where(high > 1e-12, span / np.maximum(high, 1e-12), 0.0)
    return np.stack([hue, saturation, high], axis=1)


def palette(lab: np.ndarray, colors: int) -> tuple[np.ndarray, np.ndarray]:
    """k dominant Lab colours and their pixel shares.

    Seeded from lightness quantiles rather than at random, so the same art always
    produces the same palette and two runs stay comparable.
    """
    if lab.shape[0] == 0:
        return np.zeros((0, 3)), np.zeros((0,))
    colors = max(1, min(colors, lab.shape[0]))
    quantiles = np.linspace(0, 100, colors + 2)[1:-1]
    centers = np.stack([np.percentile(lab, q, axis=0) for q in quantiles])
    for _ in range(KMEANS_ITERATIONS):
        distances = np.linalg.norm(lab[:, None, :] - centers[None, :, :], axis=2)
        labels = distances.argmin(axis=1)
        moved = False
        for index in range(colors):
            member = lab[labels == index]
            if member.shape[0] == 0:
                continue
            mean = member.mean(axis=0)
            if not np.allclose(mean, centers[index]):
                centers[index] = mean
                moved = True
        if not moved:
            break
    distances = np.linalg.norm(lab[:, None, :] - centers[None, :, :], axis=2)
    labels = distances.argmin(axis=1)
    weights = np.array([(labels == index).sum() for index in range(colors)], dtype=np.float64)
    weights /= max(weights.sum(), 1.0)
    order = np.argsort(centers[:, 0])
    return centers[order], weights[order]


def measure(image: Image.Image, colors: int = DEFAULT_COLORS) -> dict:
    """The style fingerprint of one image."""
    rgb = opaque_pixels(image)
    lab = srgb_to_lab(rgb)
    hsv = rgb_to_hsv(rgb)
    centers, weights = palette(lab, colors)
    if rgb.shape[0] == 0:
        return {"pixels": 0, "palette": centers, "weights": weights, "hue": 0.0, "saturation": 0.0, "value": 0.0}
    # Hue is circular, and an unsaturated pixel has no meaningful hue, so the
    # mean is a vector sum weighted by how colourful each pixel actually is.
    chroma = hsv[:, 1] * hsv[:, 2]
    radians = np.deg2rad(hsv[:, 0])
    hue = float(np.rad2deg(np.arctan2((np.sin(radians) * chroma).sum(), (np.cos(radians) * chroma).sum())) % 360)
    return {
        "pixels": int(rgb.shape[0]),
        "palette": centers,
        "weights": weights,
        "hue": hue,
        "saturation": float(hsv[:, 1].mean()),
        "value": float(hsv[:, 2].mean()),
    }


def hue_gap(first: float, second: float) -> float:
    """Absolute shortest hue distance, 0..180; symmetric and unsigned."""
    return abs((second - first + 180) % 360 - 180)


def palette_distance(first: dict, second: dict) -> float:
    """Unweighted mean delta-E over the best pairing of palette centers.

    Calculated shares are ignored: this is not a mass-sensitive comparison.

    Both palettes are small, so every pairing is tried and the cheapest wins;
    matching by sorted lightness alone would punish a style that simply
    brightened.
    """
    left, right = first["palette"], second["palette"]
    if left.shape[0] == 0 or right.shape[0] == 0:
        return 0.0
    size = min(left.shape[0], right.shape[0])
    left, right = left[:size], right[:size]
    best = None
    for order in itertools.permutations(range(size)):
        cost = float(np.linalg.norm(left - right[list(order)], axis=1).mean())
        if best is None or cost < best:
            best = cost
    return best or 0.0


def compare_pair(first: Image.Image, second: Image.Image, colors: int = DEFAULT_COLORS) -> dict:
    """Every number for one prompt rendered under two style references."""
    a, b = measure(first, colors), measure(second, colors)
    return {
        "delta_e": palette_distance(a, b),
        "hue_shift": hue_gap(a["hue"], b["hue"]),
        "saturation_delta": b["saturation"] - a["saturation"],
        "value_delta": b["value"] - a["value"],
        "pixels": (a["pixels"], b["pixels"]),
    }


def pair_files(first: pathlib.Path, second: pathlib.Path) -> list[tuple[pathlib.Path, pathlib.Path]]:
    """Files present in both directories, matched on name."""
    def index(folder: pathlib.Path) -> dict[str, pathlib.Path]:
        return {
            path.name: path
            for path in sorted(folder.iterdir())
            if path.is_file() and path.suffix.lower() in SUFFIXES
        }

    left, right = index(first), index(second)
    return [(left[name], right[name]) for name in sorted(set(left) & set(right))]


def contact_sheet(pairs: list[tuple[pathlib.Path, pathlib.Path]], target: pathlib.Path, cell: int = 320) -> None:
    """One row per prompt: the reference-A output beside the reference-B output."""
    if not pairs:
        return
    sheet = Image.new("RGBA", (cell * 2, cell * len(pairs)), (24, 24, 28, 255))
    for row, (left, right) in enumerate(pairs):
        for column, path in enumerate((left, right)):
            with Image.open(path) as source:
                art = source.convert("RGBA")
                art.thumbnail((cell, cell))
                sheet.alpha_composite(
                    art,
                    (column * cell + (cell - art.size[0]) // 2, row * cell + (cell - art.size[1]) // 2),
                )
    sheet.save(target)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("first", help="outputs generated under style reference A")
    parser.add_argument("second", help="outputs generated under style reference B")
    parser.add_argument("--colors", type=int, default=DEFAULT_COLORS, help="palette size per image")
    parser.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD, help="advisory comparison point for the mean delta-E, not a validated whole-image or style threshold")
    parser.add_argument("--contact-sheet", help="write a side-by-side PNG here")
    args = parser.parse_args()

    pairs = pair_files(pathlib.Path(args.first), pathlib.Path(args.second))
    if not pairs:
        print("no matching filenames in both directories", file=sys.stderr)
        return 1

    deltas = []
    print(f"{'asset':<28} {'deltaE':>8} {'hue_gap':>8} {'sat':>8} {'val':>8}")
    for left, right in pairs:
        with Image.open(left) as a, Image.open(right) as b:
            result = compare_pair(a, b, args.colors)
        deltas.append(result["delta_e"])
        print(
            f"{left.name:<28} {result['delta_e']:>8.2f} {result['hue_shift']:>7.1f}° "
            f"{result['saturation_delta']:>+8.3f} {result['value_delta']:>+8.3f}"
        )

    mean = float(np.mean(deltas))
    print(f"\nunweighted palette-center mean delta-E over {len(pairs)} asset(s): {mean:.2f}  (advisory comparison point {args.threshold})")
    if args.contact_sheet:
        contact_sheet(pairs, pathlib.Path(args.contact_sheet))
        print(f"contact sheet: {args.contact_sheet}")

    side = "at or above" if mean >= args.threshold else "below"
    print(
        f"advisory: the palettes sit {side} the comparison point. This metric ignores color proportions and spatial arrangement. Colour distance alone neither "
        "proves nor disproves that the reference conditioned the output -- generation variance "
        "moves it, and a change to shape, material or composition may not. Compare the outputs "
        "against the reference and report the conditioning evidence the calls returned."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
