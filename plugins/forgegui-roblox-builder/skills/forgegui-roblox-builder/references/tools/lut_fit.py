"""Fit .cube LUTs to the one colour grade Roblox can actually apply.

Usage:
    python lut_fit.py luts/*.cube --out LutGrades.luau
    python lut_fit.py --selftest

Reads any .cube (3D or 1D, any size, DOMAIN_MIN/MAX honoured) and writes a
Luau ModuleScript `{ grades = { [name] = Grade }, order = { name } }` that
references/luau/ColourGrade.luau consumes. Needs numpy only.

Roblox has no LUT support. Measured in Studio, a displayed pixel is
    d = T(lin(c) * 2^E)
with T a filmic tone curve (TONE_POINTS, measured linear -> display pairs), then
ONE ColorCorrectionEffect in display space: contrast, saturation (Roblox luma
weights W), brightness, tint, clamp. Several CC effects merge (C, S, B add,
tints multiply), so a grade is one CC. The best approximation of a LUT (display
in -> graded display out) is therefore
    G(x) = CC(T(T^-1(x) * 2^dE))
seven parameters: exposure dE (slides pixels along the tone curve, which is
the only curve shape available), contrast C, saturation S, brightness B and a
per-channel tint.

Non-obvious choices:
  tone curve   monotone cubic (Fritsch-Carlson PCHIP) in log-x through the
               measured points, linear through the origin below the first
               point, 1.0 above the last; the 0.2032 bin was noisy and is
               taken as 0.494. The inverse is a dense-table lookup.
  weights      w = 1 - 0.6 * chroma of the grid input, so the saturated cube
               corners (which no scene contains) do not outvote skin, earth and
               sky tones.
  solver       Levenberg-Marquardt with a central-difference Jacobian in numpy
               (no scipy). It runs on the LUT's own nodes (33 per axis at most).
  domain       DOMAIN_MIN/MAX are honoured; grid inputs outside 0..1 are not
               fitted (the display never holds them). LUT_1D_SIZE files are
               expanded to a 3D grid.
  split tone   what the CC cannot do, shadows and highlights tinted apart, is
               measured as sum(target) / sum(fitted) per channel over grid
               points with luma < 0.25 (shadowTint) and > 0.7 (highlightTint).
               That is the mean of target/fitted weighted by the fitted value,
               which stays finite near black. Clamped to 0.85..1.15, 3 decimals.
               ColourGrade multiplies them into the ambient and sun colours.
  tone curve   TONE_POINTS were measured in Studio (2026-09) by reading the
  source       displayed pixel back from captures at known linear values.
               Re-measure if Roblox changes its tonemapper.
Errors are reported in 0..255 levels over every grid point and channel.
"""

import argparse
import os
import re
import sys
import tempfile

import numpy as np

# Measured Roblox tone curve: linear scene value -> displayed sRGB.
TONE_POINTS = [
    (0.005, 0.016), (0.0095, 0.031), (0.020, 0.067), (0.0254, 0.098), (0.0482, 0.176),
    (0.1018, 0.322), (0.1529, 0.410), (0.2032, 0.494), (0.2613, 0.545), (0.4281, 0.718),
    (0.50, 0.733), (0.7467, 0.824), (0.9483, 0.894), (1.2742, 0.933), (1.5748, 0.941),
    (2.045, 0.975), (3.15, 1.0),
]
LUMA_W = np.array([0.34, 0.548, 0.112])  # Roblox ColorCorrection saturation weights
FIT_SIZE = 33
SHADOW_LUMA, HIGHLIGHT_LUMA = 0.25, 0.7
SPLIT_RANGE = (0.85, 1.15)
IDENTITY = np.array([0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0])
LOWER = np.array([-4.0, -0.95, -1.0, -1.0, 0.0, 0.0, 0.0])
UPPER = np.array([4.0, 3.0, 3.0, 1.0, 2.0, 2.0, 2.0])


# --- tone curve ---------------------------------------------------------------

def _pchip_slopes(x, y):
    """Fritsch-Carlson slopes: a cubic Hermite through them never overshoots."""
    h = np.diff(x)
    delta = np.diff(y) / h
    m = np.zeros_like(y)
    for k in range(1, len(x) - 1):
        if delta[k - 1] * delta[k] > 0:
            w1, w2 = 2 * h[k] + h[k - 1], h[k] + 2 * h[k - 1]
            m[k] = (w1 + w2) / (w1 / delta[k - 1] + w2 / delta[k])
    m[0], m[-1] = delta[0], delta[-1]
    return m


_LX = np.log(np.array([p[0] for p in TONE_POINTS]))
_TY = np.array([p[1] for p in TONE_POINTS])
_TM = _pchip_slopes(_LX, _TY)
X_MAX = TONE_POINTS[-1][0]
LOW_SLOPE = TONE_POINTS[0][1] / TONE_POINTS[0][0]


def tone(x):
    """T: linear scene value -> display value in 0..1."""
    x = np.asarray(x, dtype=np.float64)
    u = np.log(np.clip(x, TONE_POINTS[0][0], X_MAX))
    k = np.clip(np.searchsorted(_LX, u) - 1, 0, len(_LX) - 2)
    h = _LX[k + 1] - _LX[k]
    s = (u - _LX[k]) / h
    s2, s3 = s * s, s * s * s
    y = ((2 * s3 - 3 * s2 + 1) * _TY[k] + (s3 - 2 * s2 + s) * h * _TM[k]
         + (-2 * s3 + 3 * s2) * _TY[k + 1] + (s3 - s2) * h * _TM[k + 1])
    y = np.where(x < TONE_POINTS[0][0], np.maximum(x, 0) * LOW_SLOPE, y)
    return np.where(x >= X_MAX, 1.0, y)


_INV_X = np.concatenate([[0.0], np.geomspace(1e-6, X_MAX, 16384)])
_INV_Y = tone(_INV_X)


def tone_inv(y):
    """T^-1: display value -> linear scene value (1.0 maps to the curve's end)."""
    return np.interp(np.clip(y, 0.0, 1.0), _INV_Y, _INV_X)


# --- forward model ------------------------------------------------------------

def color_correct(x, contrast, saturation, brightness, tint):
    """Roblox ColorCorrectionEffect in display space, clamped at the end."""
    x = (x - 0.5) * (1 + contrast) + 0.5
    luma = (x @ LUMA_W)[:, None]
    x = luma + (1 + saturation) * (x - luma)
    x = (x + brightness) * np.asarray(tint)
    return np.clip(x, 0.0, 1.0)


def forward(rgb, p):
    """G(x): exposure shift along the tone curve, then the CC."""
    shifted = tone(tone_inv(rgb) * 2.0 ** p[0])
    return color_correct(shifted, p[1], p[2], p[3], p[4:7])


# --- .cube io -----------------------------------------------------------------

def read_cube(path):
    """Parse a .cube file -> (inputs Mx3, outputs Mx3) in 0..1 display space."""
    size3 = size1 = None
    dmin, dmax = np.zeros(3), np.ones(3)
    rows = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            parts = line.split()
            key = parts[0].upper()
            if key == "LUT_3D_SIZE":
                size3 = int(parts[1])
            elif key == "LUT_1D_SIZE":
                size1 = int(parts[1])
            elif key == "DOMAIN_MIN":
                dmin = np.array([float(v) for v in parts[1:4]])
            elif key == "DOMAIN_MAX":
                dmax = np.array([float(v) for v in parts[1:4]])
            elif key in ("LUT_3D_INPUT_RANGE", "LUT_1D_INPUT_RANGE"):
                dmin, dmax = np.full(3, float(parts[1])), np.full(3, float(parts[2]))
            elif re.match(r"^[-+.\d]", line):
                rows.append([float(v) for v in parts[:3]])
    table = np.array(rows, dtype=np.float64)
    if size3:
        if len(table) != size3 ** 3:
            raise ValueError(f"expected {size3 ** 3} rows, found {len(table)}")
        return _resample3d(table.reshape(size3, size3, size3, 3), dmin, dmax)
    if size1:
        if len(table) != size1:
            raise ValueError(f"expected {size1} rows, found {len(table)}")
        return _expand1d(table, dmin, dmax)
    raise ValueError("no LUT_3D_SIZE or LUT_1D_SIZE header")


def fit_grid(n=FIT_SIZE):
    """The display-space points a 1D LUT is sampled at, red fastest like .cube."""
    a = np.linspace(0.0, 1.0, n)
    b, g, r = np.meshgrid(a, a, a, indexing="ij")
    return np.stack([r.ravel(), g.ravel(), b.ravel()], axis=1)


def _inside(pts, dmin, dmax):
    return np.all((pts >= dmin - 1e-9) & (pts <= dmax + 1e-9), axis=1)


def _resample3d(lut, dmin, dmax):
    """The LUT's own grid points inside 0..1 (no interpolation error).

    Tables finer than 33 keep 33 of their own nodes per axis, which is plenty
    for 7 parameters and keeps a 65^3 file as fast as a 33^3 one.
    """
    n = lut.shape[0]
    keep = np.unique(np.round(np.linspace(0, n - 1, min(n, FIT_SIZE))).astype(int))
    bi, gi, ri = np.meshgrid(keep, keep, keep, indexing="ij")
    idx = np.stack([ri.ravel(), gi.ravel(), bi.ravel()], axis=1)
    pts = dmin + idx / (n - 1) * (dmax - dmin)
    inside = np.all((pts >= -1e-9) & (pts <= 1 + 1e-9), axis=1)
    idx, pts = idx[inside], np.clip(pts[inside], 0.0, 1.0)
    if len(pts) < 27:
        raise ValueError("too few grid points inside 0..1")
    out = lut[idx[:, 2], idx[:, 1], idx[:, 0]]
    return pts, np.clip(out, 0.0, 1.0)


def _expand1d(table, dmin, dmax):
    """Per-channel curves applied to the 33^3 grid."""
    pts = fit_grid()
    pts = pts[_inside(pts, dmin, dmax)]
    out = np.empty_like(pts)
    for c in range(3):
        xs = np.linspace(dmin[c], dmax[c], len(table))
        out[:, c] = np.interp(pts[:, c], xs, table[:, c])
    return pts, np.clip(out, 0.0, 1.0)


def write_cube(path, fn, size, title, domain=(0.0, 1.0)):
    """Write fn(display rgb Mx3) as a .cube (used by the self-test)."""
    lo, hi = domain
    a = np.linspace(lo, hi, size)
    b, g, r = np.meshgrid(a, a, a, indexing="ij")
    pts = np.stack([r.ravel(), g.ravel(), b.ravel()], axis=1)
    out = fn(np.clip(pts, 0, 1))
    with open(path, "w", encoding="utf-8") as f:
        f.write(f'TITLE "{title}"\nLUT_3D_SIZE {size}\n')
        f.write(f"DOMAIN_MIN {lo} {lo} {lo}\nDOMAIN_MAX {hi} {hi} {hi}\n")
        for row in out:
            f.write(f"{row[0]:.6f} {row[1]:.6f} {row[2]:.6f}\n")


# --- fit ----------------------------------------------------------------------

def fit_weights(rgb):
    """Down-weight saturated corners: w = 1 - 0.6 * chroma."""
    return 1.0 - 0.6 * (rgb.max(axis=1) - rgb.min(axis=1))


def _jacobian(resid, q, step=1e-5):
    """Central differences, one column per parameter."""
    cols = []
    for k in range(len(q)):
        dq = np.zeros_like(q)
        dq[k] = step
        cols.append((resid(q + dq) - resid(q - dq)) / (2 * step))
    return np.stack(cols, axis=1)


def canonical(p):
    """The same grade with its tint scaled so the brightest channel is 1.

    The CC has one exact degeneracy: its output is tint * ((1 + C) * sat(x)
    + B - C / 2), so scaling the tint by k and (1 + C) and (B - C / 2) by 1/k
    changes nothing. Pinning max(tint) = 1 keeps TintColor a plain 0..1 colour.
    """
    dE, C, S, B = p[:4]
    k = float(np.max(p[4:7]))
    c2 = (1 + C) * k - 1
    b2 = (B - C / 2) * k + c2 / 2
    return np.concatenate([[dE, c2, S, b2], p[4:7] / k])


def _expand(q):
    """6 free parameters (tint mean fixed at 1 while fitting) -> 7."""
    return np.concatenate([q[:6], [3.0 - q[4] - q[5]]])


def fit(rgb, target, iters=300):
    """Weighted Levenberg-Marquardt, gauge-fixed, returned in canonical form."""
    sw = np.sqrt(np.repeat(fit_weights(rgb), 3))
    q = IDENTITY[:6].copy()
    q_lo, q_hi = LOWER[:6], UPPER[:6]

    def resid(q):
        return (forward(rgb, _expand(q)) - target).ravel() * sw

    r = resid(q)
    cost, lam = r @ r, 1e-3
    for _ in range(iters):
        J = _jacobian(lambda v: resid(v), q)
        A, g = J.T @ J, J.T @ r
        accepted = None
        while lam < 1e10 and accepted is None:
            step = np.linalg.solve(A + lam * np.diag(np.diag(A) + 1e-12), -g)
            trial = np.clip(q + step, q_lo, q_hi)
            rt = resid(trial)
            if rt @ rt < cost:
                accepted = (trial, rt)
            else:
                lam *= 4
        if accepted is None:
            break
        trial, rt = accepted
        moved = np.max(np.abs(trial - q))
        q, r, cost, lam = trial, rt, rt @ rt, max(lam / 3, 1e-12)
        if moved < 1e-10:
            break
    return canonical(_expand(q))


def split_tone(rgb, target, fitted):
    """Per-channel residual ratios in the shadows and highlights."""
    luma = rgb @ LUMA_W
    result = []
    for mask in (luma < SHADOW_LUMA, luma > HIGHLIGHT_LUMA):
        ratio = target[mask].sum(axis=0) / np.maximum(fitted[mask].sum(axis=0), 1e-6)
        result.append(np.round(np.clip(ratio, *SPLIT_RANGE), 3))
    return result


def error_levels(fitted, target):
    """(RMS, 95th percentile) absolute error in 0..255 levels."""
    err = np.abs(fitted - target).ravel() * 255
    return float(np.sqrt(np.mean(err ** 2))), float(np.percentile(err, 95))


def fit_cube(path):
    rgb, target = read_cube(path)
    p = fit(rgb, target)
    fitted = forward(rgb, p)
    rms, p95 = error_levels(fitted, target)
    shadow, highlight = split_tone(rgb, target, fitted)
    name = os.path.splitext(os.path.basename(path))[0]
    return {"name": name, "source": os.path.basename(path), "params": p,
            "rms": rms, "p95": p95, "shadow": shadow, "highlight": highlight}


# --- Luau output --------------------------------------------------------------

def _num(v, digits=4):
    s = f"{round(float(v), digits):.{digits}f}"
    return "0" if float(s) == 0 else s


def _color3(c, digits):
    return "Color3.new(" + ", ".join(_num(v, digits) for v in c) + ")"


def _quote(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _key(name):
    return name if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name) else f"[{_quote(name)}]"


LUAU_HEADER = """--!strict
-- LutGrades
--
-- GENERATED by references/tools/lut_fit.py from .cube files. Do not edit by
-- hand; regenerate with:
--   python lut_fit.py <luts>/*.cube --out LutGrades.luau
--
-- Each grade is the closest Roblox gets to its LUT: an exposure shift (added
-- to Lighting.ExposureCompensation) and ONE ColorCorrectionEffect (contrast,
-- saturation, brightness, tint). shadowTint and highlightTint are the split
-- toning a CC cannot express: multiply them into the ambient and sun colours.
-- rmsError is the fit error in 0..255 levels. Pass `grades` to
-- ColourGrade.start, which blends and scales them.

export type Grade = {
\texposure: number,
\tcontrast: number,
\tsaturation: number,
\tbrightness: number,
\ttint: Color3,
\tshadowTint: Color3,
\thighlightTint: Color3,
\trmsError: number,
\tsource: string,
}

local grades: { [string]: Grade } = {
"""


def to_luau(results):
    body = []
    for r in results:
        p = r["params"]
        body += [
            f"\t{_key(r['name'])} = {{",
            f"\t\texposure = {_num(p[0])},",
            f"\t\tcontrast = {_num(p[1])},",
            f"\t\tsaturation = {_num(p[2])},",
            f"\t\tbrightness = {_num(p[3])},",
            f"\t\ttint = {_color3(p[4:7], 4)},",
            f"\t\tshadowTint = {_color3(r['shadow'], 3)},",
            f"\t\thighlightTint = {_color3(r['highlight'], 3)},",
            f"\t\trmsError = {_num(r['rms'], 2)},",
            f"\t\tsource = {_quote(r['source'])},",
            "\t},",
        ]
    order = ", ".join(_quote(r["name"]) for r in results)
    tail = ["}", "", f"local order: {{ string }} = {{ {order} }}", "",
            "return {", "\tgrades = grades,", "\torder = order,", "}", ""]
    return LUAU_HEADER + "\n".join(body + tail)


def report(results):
    print(f"{'grade':<14}{'dE':>8}{'C':>8}{'S':>8}{'B':>8}  {'tint':<19}{'rms':>6}{'p95':>6}  shadow / highlight")
    for r in results:
        p = r["params"]
        tint = " ".join(f"{v:.3f}" for v in p[4:7])
        sh = " ".join(f"{v:.3f}" for v in r["shadow"])
        hi = " ".join(f"{v:.3f}" for v in r["highlight"])
        print(f"{r['name']:<14}{p[0]:8.3f}{p[1]:8.3f}{p[2]:8.3f}{p[3]:8.3f}  {tint:<19}"
              f"{r['rms']:6.2f}{r['p95']:6.2f}  {sh} / {hi}")


# --- self-test ----------------------------------------------------------------

SELFTEST_CASES = [
    ("warm_push", [0.30, 0.10, -0.10, 0.02, 1.00, 0.97, 0.92], 33, (0.0, 1.0)),
    ("cool_down", [-0.40, -0.15, 0.20, -0.03, 0.88, 0.93, 1.00], 17, (0.0, 1.0)),
    ("flat_desat", [0.00, 0.20, -0.30, 0.00, 1.00, 1.00, 1.00], 65, (0.0, 1.0)),
    ("wide_domain", [0.15, -0.05, 0.10, 0.01, 1.00, 0.96, 0.98], 25, (-0.1, 1.1)),
    ("identity", list(IDENTITY), 33, (0.0, 1.0)),
]


def selftest():
    """Truths are canonical (max tint 1), the only form the fit can return."""
    y = np.linspace(0, 1, 1001)
    inv_err = float(np.max(np.abs(tone(tone_inv(y)) - y)))
    monotone = bool(np.all(np.diff(tone(np.geomspace(1e-4, 4, 4000))) >= 0))
    ok = inv_err < 1e-4 and monotone
    print(f"tone curve   monotone={monotone}  max |T(T^-1(y)) - y| = {inv_err:.1e}  {'ok' if ok else 'FAIL'}")
    with tempfile.TemporaryDirectory() as tmp:
        for name, params, size, domain in SELFTEST_CASES:
            truth = np.array(params)
            path = os.path.join(tmp, name + ".cube")
            write_cube(path, lambda rgb: forward(rgb, truth), size, name, domain)
            result = fit_cube(path)
            worst = float(np.max(np.abs(result["params"] - truth)))
            passed = worst < 0.01
            ok = ok and passed
            got = " ".join(f"{v:+.4f}" for v in result["params"])
            print(f"{name:<12} size {size:<3} max |dp| = {worst:.5f}  rms {result['rms']:.3f} lvl  "
                  f"{'ok' if passed else 'FAIL'}   got {got}")
        ok = _selftest_1d(tmp) and ok
        ok = _selftest_luau(tmp) and ok
    print("SELFTEST " + ("PASSED" if ok else "FAILED"))
    return ok


def _selftest_1d(tmp):
    """A 1D identity LUT parses, expands to 3D and fits to no correction."""
    path = os.path.join(tmp, "identity_1d.cube")
    with open(path, "w", encoding="utf-8") as f:
        f.write("TITLE \"identity 1d\"\nLUT_1D_SIZE 16\n")
        for v in np.linspace(0, 1, 16):
            f.write(f"{v:.6f} {v:.6f} {v:.6f}\n")
    result = fit_cube(path)
    worst = float(np.max(np.abs(result["params"] - IDENTITY)))
    passed = worst < 0.01 and result["rms"] < 0.5
    print(f"identity_1d  size 16  max |dp| = {worst:.5f}  rms {result['rms']:.3f} lvl  {'ok' if passed else 'FAIL'}")
    return passed


def _selftest_luau(tmp):
    """The Luau writer emits every field ColourGrade reads, for odd names too."""
    path = os.path.join(tmp, "odd name.cube")
    write_cube(path, lambda rgb: forward(rgb, IDENTITY), 9, "odd")
    text = to_luau([fit_cube(path)])
    fields = ("exposure =", "contrast =", "saturation =", "brightness =", "tint = Color3.new(",
              "shadowTint = Color3.new(", "highlightTint = Color3.new(", "rmsError =", '["odd name"] = {')
    missing = [f for f in fields if f not in text]
    passed = not missing and text.startswith("--!strict") and text.rstrip().endswith("}")
    print(f"luau output  {'ok' if passed else 'FAIL missing ' + ', '.join(missing)}")
    return passed


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("cubes", nargs="*", help=".cube files, e.g. luts/*.cube")
    ap.add_argument("--out", help="write the LutGrades.luau module here")
    ap.add_argument("--selftest", action="store_true", help="fit synthetic LUTs with known parameters")
    args = ap.parse_args(argv)
    if args.selftest:
        return 0 if selftest() else 1
    if not args.cubes:
        ap.error("no .cube files given")
    paths = sorted(set(args.cubes), key=lambda p: (os.path.basename(p) != "neutral.cube", os.path.basename(p)))
    results = []
    for path in paths:
        try:
            results.append(fit_cube(path))
        except (OSError, ValueError) as exc:
            print(f"skip {path}: {exc}", file=sys.stderr)
    if not results:
        return 1
    report(results)
    if args.out:
        with open(args.out, "w", encoding="utf-8", newline="\n") as f:
            f.write(to_luau(results))
        print(f"wrote {args.out} ({len(results)} grades)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
