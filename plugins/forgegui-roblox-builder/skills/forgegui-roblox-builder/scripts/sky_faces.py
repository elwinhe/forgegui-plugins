#!/usr/bin/env python3
"""Cut a 2:1 equirectangular panorama into the six faces a Roblox Sky needs.

usage: sky_faces.py <panorama.png> <out_dir> [--size 1024]
       sky_faces.py --selftest
Writes SkyboxFt/Bk/Lf/Rt/Up/Dn.png. Faces come from one continuous image, so
edges meet by construction; the panorama's own left/right wrap seam is the only
place a generated image can mismatch, and it lands behind the camera (Bk).
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# Direction for face pixel (u, v), both in [-1, 1], u right, v down.
# Roblox: +Y up, camera faces -Z at spawn, +X to the right. Measured in Studio on
# 19 Sep 2026: Roblox shows SkyboxLf on the +X side and SkyboxRt on -X.
FACES = {
    "SkyboxFt": lambda u, v: (u, -v, -np.ones_like(u)),
    "SkyboxBk": lambda u, v: (-u, -v, np.ones_like(u)),
    "SkyboxLf": lambda u, v: (np.ones_like(u), -v, u),
    "SkyboxRt": lambda u, v: (-np.ones_like(u), -v, -u),
    "SkyboxUp": lambda u, v: (u, np.ones_like(u), -v),   # forward at bottom edge
    "SkyboxDn": lambda u, v: (u, -np.ones_like(u), v),    # forward at top edge
}
# Quarter turns (counter-clockwise) applied after sampling. Studio shows the Up
# face turned 90° clockwise and the Dn face 90° counter-clockwise, so undo both.
ROTATE = {"SkyboxFt": 0, "SkyboxBk": 0, "SkyboxRt": 0, "SkyboxLf": 0, "SkyboxUp": 1, "SkyboxDn": -1}


def sample(pano, x, y, z):
    h, w, _ = pano.shape
    lon = np.arctan2(x, -z)                                  # 0 = forward (-Z), + = right
    lat = np.arcsin(y / np.sqrt(x * x + y * y + z * z))     # + = up
    px = (lon / (2 * np.pi) + 0.5) * w - 0.5
    py = (0.5 - lat / np.pi) * h - 0.5
    x0 = np.floor(px).astype(int); fx = (px - x0)[..., None]
    y0 = np.clip(np.floor(py).astype(int), 0, h - 1); fy = (py - np.floor(py))[..., None]
    y1 = np.clip(y0 + 1, 0, h - 1)
    x0w, x1w = x0 % w, (x0 + 1) % w                         # wrap horizontally
    top = pano[y0, x0w] * (1 - fx) + pano[y0, x1w] * fx
    bot = pano[y1, x0w] * (1 - fx) + pano[y1, x1w] * fx
    return top * (1 - fy) + bot * fy


def faces(pano, size, rotate=True):
    c = (np.arange(size) + 0.5) / size * 2 - 1
    u, v = np.meshgrid(c, c)
    return {n: np.rot90(sample(pano, *f(u, v)), ROTATE[n] if rotate else 0) for n, f in FACES.items()}


def main(src, out, size=1024):
    img = Image.open(src).convert("RGB")
    w, h = img.size
    if abs(w / h - 2) > 0.02:
        sys.exit(f"error: {src} is {w}x{h}; an equirectangular panorama must be 2:1")
    Path(out).mkdir(parents=True, exist_ok=True)
    for name, arr in faces(np.asarray(img, dtype=np.float32), size).items():
        Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(Path(out) / f"{name}.png")
        print(Path(out) / f"{name}.png")


def selftest():
    # Panorama coloured by direction: R = forward/back, G = up/down, B = right/left.
    h, w = 256, 512
    lon = ((np.arange(w) + 0.5) / w - 0.5) * 2 * np.pi
    lat = (0.5 - (np.arange(h) + 0.5) / h) * np.pi
    lon, lat = np.meshgrid(lon, lat)
    d = np.stack([np.cos(lat) * np.sin(lon), np.sin(lat), -np.cos(lat) * np.cos(lon)], -1)
    pano = (d * 127.5 + 127.5).astype(np.float32)
    f = faces(pano, 64, rotate=False)  # geometry before Studio's per-face turns
    mid = lambda n: f[n][32, 32]
    assert mid("SkyboxFt")[2] < 20, "Ft centre should look along -Z"
    assert mid("SkyboxBk")[2] > 235, "Bk centre should look along +Z"
    assert mid("SkyboxLf")[0] > 235 and mid("SkyboxRt")[0] < 20, "Lf/Rt should be +X/-X"
    assert mid("SkyboxUp")[1] > 235 and mid("SkyboxDn")[1] < 20, "Up/Dn should be +Y/-Y"
    # Shared edges match: Ft's right column == Lf's left column (+X side).
    assert np.abs(f["SkyboxFt"][:, -1] - f["SkyboxLf"][:, 0]).max() < 12, "Ft/Lf seam"
    assert np.abs(f["SkyboxFt"][0] - f["SkyboxUp"][-1]).max() < 12, "Ft/Up seam"
    assert np.abs(f["SkyboxFt"][-1] - f["SkyboxDn"][0]).max() < 12, "Ft/Dn seam"
    assert np.abs(f["SkyboxLf"][:, -1] - f["SkyboxBk"][:, 0]).max() < 12, "Lf/Bk seam"
    print("selftest ok")


if __name__ == "__main__":
    a = sys.argv[1:]
    if a == ["--selftest"]:
        selftest()
    elif len(a) in (2, 4):
        main(a[0], a[1], int(a[3]) if len(a) == 4 and a[2] == "--size" else 1024)
    else:
        sys.exit(__doc__)
