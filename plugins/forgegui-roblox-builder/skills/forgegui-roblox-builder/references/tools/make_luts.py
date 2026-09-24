"""Author a few example film-style colour grades as 33^3 .cube LUTs.

Usage:
    python make_luts.py [out_dir]          (default ./luts)
    python make_luts.py --selftest

Then fit them to what Roblox can show:
    python lut_fit.py luts/*.cube --out LutGrades.luau

Optional. Any .cube from a grading suite (Resolve, Photoshop, a LUT pack) fits
the same way; these exist so a project has sensible looks to start from and so
lut_fit's error and split-tone residuals are measured against real grades.

Each grade is built the way a colourist would, in display space (the LUT maps
the displayed image to the graded one), as a chain of small operations:
  s_curve     filmic contrast around a pivot, x^g / (x^g + k(1-x)^g), which
              keeps 0 and 1 fixed and bends mid-tones without clipping
  lift/gain   raise the black point toward a colour, pull the white point in
  rolloff     soft highlight shoulder, so bright surfaces and sky compress
              instead of clipping
  split       tint shadows and highlights separately (luma-weighted), keeping
              each pixel's luma
  hue_tweak   saturation / value / hue changes centred on one hue, with a
              smooth falloff
  saturation  global, around Rec.709 luma
The operations are deliberately more than a Roblox ColorCorrectionEffect can
express (split toning, hue-dependent changes, curve shapes).

Looks: neutral, golden_hour, moonlight, overcast, neon_night.
"""

import os
import sys
import tempfile

import numpy as np

SIZE = 33
REC709 = np.array([0.2126, 0.7152, 0.0722])
MAX_FIT_RMS = 20.0  # levels; a look that fits worse than this is not worth shipping


# --- operations (all take and return Mx3 display rgb) ------------------------

def luma(x):
    return (x @ REC709)[:, None]


def smoothstep(e0, e1, v):
    t = np.clip((v - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def s_curve(x, gamma, pivot=0.5):
    """Contrast around pivot with 0, pivot and 1 fixed; gamma > 1 adds contrast.

    k is chosen so s(pivot) = pivot. (With k = (p / (1 - p)) ** gamma the pivot
    lands on 0.5 instead, which quietly brightens every midtone.)
    """
    x = np.clip(x, 0.0, 1.0)
    k = pivot ** (gamma - 1) * (1 - pivot) ** (1 - gamma)
    a = x ** gamma
    return a / (a + k * (1 - x) ** gamma + 1e-12)


def lift_gain(x, lift=(0, 0, 0), gain=(1, 1, 1)):
    lift, gain = np.asarray(lift), np.asarray(gain)
    return lift + (gain - lift) * x


def rolloff(x, knee, top=1.0):
    """Soft shoulder above knee that approaches top."""
    span = top - knee
    over = np.maximum(x - knee, 0.0)
    return np.where(x > knee, knee + span * (1 - np.exp(-over / span)), x)


def split(x, shadow, highlight, amount_s=1.0, amount_h=1.0):
    """Tint shadows and highlights by a colour, then restore the pixel's luma."""
    lum = luma(x)
    ws = (1 - smoothstep(0.0, 0.5, lum)) * amount_s
    wh = smoothstep(0.45, 1.0, lum) * amount_h
    tinted = x * (1 + ws * (np.asarray(shadow) - 1) + wh * (np.asarray(highlight) - 1))
    return tinted * (lum / np.maximum(luma(tinted), 1e-6))


def saturation(x, s):
    lum = luma(x)
    return lum + s * (x - lum)


def _hsv(x):
    mx, mn = x.max(axis=1), x.min(axis=1)
    d = mx - mn
    r, g, b = x[:, 0], x[:, 1], x[:, 2]
    safe = np.maximum(d, 1e-9)
    h = np.where(mx == r, ((g - b) / safe) % 6, np.where(mx == g, (b - r) / safe + 2, (r - g) / safe + 4))
    h = np.where(d < 1e-9, 0.0, h / 6.0)
    s = np.where(mx > 1e-9, d / np.maximum(mx, 1e-9), 0.0)
    return h, s, mx


def _rgb(h, s, v):
    i = np.floor(h * 6) % 6
    f = h * 6 - np.floor(h * 6)
    p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    choices = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]
    out = np.zeros((len(h), 3))
    for k, (r, g, b) in enumerate(choices):
        m = i == k
        out[m] = np.stack([r[m], g[m], b[m]], axis=1)
    return out


def hue_tweak(x, centre_deg, width_deg, sat=1.0, val=1.0, shift_deg=0.0):
    """Change saturation/value/hue of colours near one hue (smooth falloff)."""
    h, s, v = _hsv(np.clip(x, 0, 1))
    dist = np.abs(((h * 360 - centre_deg) + 180) % 360 - 180)
    w = np.exp(-0.5 * (dist / width_deg) ** 2) * smoothstep(0.02, 0.2, s)
    h = (h + w * shift_deg / 360.0) % 1.0
    s = np.clip(s * (1 + w * (sat - 1)), 0, 1)
    v = np.clip(v * (1 + w * (val - 1)), 0, 1)
    return _rgb(h, s, v)


# --- looks ------------------------------------------------------------------------

def neutral(x):
    return x


def golden_hour(x):
    """Rich and gently warm, lifted blacks. A low sun already paints the scene
    orange, so the grade adds richness and warm highlights, not more orange."""
    x = s_curve(x, 1.1, pivot=0.45)
    x = lift_gain(x, lift=(0.02, 0.016, 0.014), gain=(1.0, 0.985, 0.96))
    x = split(x, shadow=(0.98, 0.99, 1.03), highlight=(1.03, 0.995, 0.95), amount_h=1.0)
    x = hue_tweak(x, 25, 30, sat=1.06)                  # oranges and reds glow
    x = hue_tweak(x, 210, 35, sat=0.85, shift_deg=-10)  # blues to teal, quieter
    x = rolloff(x, 0.85, 1.0)
    return saturation(x, 0.97)


def moonlight(x):
    """Cool, quiet shadows and deep but readable darks; the blue lives in the
    shadows only, so firelight and lamps stay warm (as night grades in modern
    games do)."""
    x = saturation(x, 0.78)
    x = x * 0.92
    x = s_curve(x, 1.1, pivot=0.32)
    x = lift_gain(x, lift=(0.008, 0.014, 0.03), gain=(0.97, 0.97, 1.0))
    x = split(x, shadow=(0.88, 0.96, 1.14), highlight=(1.04, 1.0, 0.94), amount_s=1.0, amount_h=0.8)
    return rolloff(x, 0.75, 0.95)


def overcast(x):
    """Soft, low-contrast grey daylight: lifted blacks, cool-neutral shadows,
    greens and skies muted, whites held just under clipping."""
    x = s_curve(x, 0.9, pivot=0.5)
    x = lift_gain(x, lift=(0.03, 0.032, 0.036), gain=(0.97, 0.975, 0.98))
    x = split(x, shadow=(0.97, 0.99, 1.04), highlight=(1.0, 1.0, 0.99), amount_s=0.8, amount_h=0.5)
    x = hue_tweak(x, 110, 40, sat=0.8)                  # foliage quieter
    x = hue_tweak(x, 210, 35, sat=0.75)                 # sky toward grey
    x = rolloff(x, 0.8, 0.97)
    return saturation(x, 0.82)


def neon_night(x):
    """Deep blacks and strong contrast so emissives carry the frame; teal
    shadows, magenta-leaning highlights, neon hues pushed."""
    x = s_curve(x, 1.25, pivot=0.35)
    x = lift_gain(x, lift=(0.0, 0.004, 0.012), gain=(1.0, 0.97, 1.0))
    x = split(x, shadow=(0.86, 1.0, 1.12), highlight=(1.06, 0.95, 1.04), amount_s=1.0, amount_h=0.9)
    x = hue_tweak(x, 300, 35, sat=1.15)                 # magenta and pink signage
    x = hue_tweak(x, 185, 30, sat=1.12)                 # cyan
    x = rolloff(x, 0.82, 1.0)
    return saturation(x, 1.08)


GRADES = {
    "neutral": neutral,
    "golden_hour": golden_hour,
    "moonlight": moonlight,
    "overcast": overcast,
    "neon_night": neon_night,
}


# --- output -------------------------------------------------------------------

def grid(n):
    a = np.linspace(0.0, 1.0, n)
    b, g, r = np.meshgrid(a, a, a, indexing="ij")
    return np.stack([r.ravel(), g.ravel(), b.ravel()], axis=1)


def write_cube(path, name, out, n):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(f'TITLE "{name}"\n# generated by make_luts.py\n')
        f.write(f"LUT_3D_SIZE {n}\nDOMAIN_MIN 0.0 0.0 0.0\nDOMAIN_MAX 1.0 1.0 1.0\n")
        f.writelines(f"{r:.6f} {g:.6f} {b:.6f}\n" for r, g, b in out)


def write_all(out_dir, size=SIZE, quiet=False):
    os.makedirs(out_dir, exist_ok=True)
    pts = grid(size)
    paths = []
    for name, grade in GRADES.items():
        out = np.clip(grade(pts.copy()), 0.0, 1.0)
        path = os.path.join(out_dir, name + ".cube")
        write_cube(path, name, out, size)
        paths.append(path)
        if not quiet:
            print(f"wrote {path}  (mean shift {np.abs(out - pts).mean() * 255:.1f} levels)")
    return paths


def selftest():
    """Every look writes a valid cube, stays in range, and fits with lut_fit."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import lut_fit  # sibling tool

    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        results = []
        for path in write_all(tmp, size=17, quiet=True):
            result = lut_fit.fit_cube(path)
            name = result["name"]
            moved = float(np.max(np.abs(result["params"] - lut_fit.IDENTITY)))
            if name == "neutral":
                passed = result["rms"] < 0.5 and moved < 0.01
            else:
                passed = result["rms"] < MAX_FIT_RMS and moved > 0.01
            ok = ok and passed
            results.append(result)
            print(f"{name:<12} rms {result['rms']:6.2f} lvl  p95 {result['p95']:6.2f}  {'ok' if passed else 'FAIL'}")
        text = lut_fit.to_luau(results)
        has_all = all(f"\t{name} = {{" in text for name in GRADES)
        ok = ok and has_all
        print(f"luau module  {'ok' if has_all else 'FAIL'} ({len(results)} grades)")
    print("SELFTEST " + ("PASSED" if ok else "FAILED"))
    return ok


def main(argv):
    if len(argv) > 1 and argv[1] == "--selftest":
        return 0 if selftest() else 1
    out_dir = argv[1] if len(argv) > 1 else "luts"
    write_all(out_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
