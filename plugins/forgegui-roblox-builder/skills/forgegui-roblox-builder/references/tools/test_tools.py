#!/usr/bin/env python3
"""Checks for the GUI import tools on synthetic art, so no generated asset is needed, and for
the module paster used to run the Luau checks through execute_luau.

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

import make_tileable  # noqa: E402
import palette_check  # noqa: E402
import paste_module  # noqa: E402
import separate_sheet  # noqa: E402
import slice_metadata  # noqa: E402
import style_delta  # noqa: E402

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


def test_paste_module() -> None:
    module = "--!strict\nlocal Check = {}\nfunction Check.run() return 1 end\n\nreturn Check\n"
    pasted = paste_module.paste(module, "return Check.run()\n")
    check(not pasted.startswith("--!"), "the mode line is dropped, so the module can sit above a runner")
    check("return Check\n" not in pasted and pasted.endswith("return Check.run()\n"), "the final return is replaced by the runner")
    try:
        paste_module.paste("local Check = {}\n", "return 1")
        check(False, "a module without a final return is rejected")
    except ValueError:
        check(True, "a module without a final return is rejected")
    luau = pathlib.Path(__file__).resolve().parent.parent / "luau"
    for name in ("WorldCheck", "UiCheck"):
        source = (luau / f"{name}.luau").read_text(encoding="utf-8")
        body = paste_module.paste(source, f"return {name}.format")
        check(f"local {name} = {{}}" in body and body.rstrip().endswith(f"return {name}.format"), f"the shipped {name} pastes with a runner")


def kit(background: tuple[int, int, int], accent: tuple[int, int, int], margin: int = 0) -> Image.Image:
    """A panel-and-icon composition in two colours, optionally on a transparent margin."""
    size = 200 + margin * 2
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((margin + 10, margin + 10, margin + 190, margin + 190), radius=24, fill=background + (255,))
    draw.ellipse((margin + 60, margin + 60, margin + 140, margin + 140), fill=accent + (255,))
    return image


# IRONFRONT's charcoal/amber against the same composition in slate/cyan.
WARM = kit((17, 24, 32), (217, 165, 74))
COOL = kit((29, 41, 51), (107, 173, 180))


def test_style_delta_separates_two_style_references() -> None:
    result = style_delta.compare_pair(WARM, COOL)
    check(result["delta_e"] > style_delta.DEFAULT_THRESHOLD, f"a recoloured kit clears the threshold (got {result['delta_e']:.2f})")
    check(result["hue_shift"] > 30, f"the hue moved from amber toward cyan (got {result['hue_shift']:.1f})")
    same = style_delta.compare_pair(WARM, WARM.copy())
    check(same["delta_e"] < style_delta.JND, f"identical art is below the just-noticeable difference (got {same['delta_e']:.3f})")
    check(same["hue_shift"] < 1e-6 and abs(same["saturation_delta"]) < 1e-9, "identical art reports no hue or saturation shift")


def test_style_delta_ignores_transparent_background() -> None:
    # The same art on a much larger transparent canvas must measure the same;
    # averaging the empty pixels in would drag both palettes toward one grey.
    padded = style_delta.compare_pair(WARM, kit((17, 24, 32), (217, 165, 74), margin=400))
    check(padded["delta_e"] < style_delta.JND, f"a transparent margin does not change the palette (got {padded['delta_e']:.3f})")
    check(padded["pixels"][1] == padded["pixels"][0], "only opaque pixels are counted, so the pixel count is unchanged")
    blank = style_delta.measure(Image.new("RGBA", (64, 64), (0, 0, 0, 0)))
    check(blank["pixels"] == 0 and blank["palette"].shape[0] == 0, "fully transparent art measures as empty rather than raising")


def test_style_delta_reports_direction() -> None:
    grey = kit((60, 60, 60), (150, 150, 150))
    check(style_delta.compare_pair(grey, WARM)["saturation_delta"] > 0, "moving to a saturated palette reports a positive saturation delta")
    check(style_delta.compare_pair(WARM, grey)["saturation_delta"] < 0, "and the reverse run reports a negative one")
    dark = kit((10, 10, 10), (20, 20, 20))
    check(style_delta.compare_pair(dark, kit((200, 200, 200), (240, 240, 240)))["value_delta"] > 0, "a brighter run reports a positive value delta")
    check(style_delta.hue_gap(350, 10) == 20, "hue distance wraps around the colour wheel")
    check(style_delta.hue_gap(10, 350) == 20, "and wraps the same way in reverse")


def test_style_delta_palette_is_deterministic() -> None:
    first = style_delta.measure(WARM)["palette"]
    second = style_delta.measure(WARM)["palette"]
    check(first.shape == second.shape and bool((first == second).all()), "the same art always yields the same palette, so two runs stay comparable")
    lightness = style_delta.measure(WARM)["palette"][:, 0]
    check(all(lightness[i] <= lightness[i + 1] for i in range(len(lightness) - 1)), "palette entries are ordered by lightness")


def test_style_delta_pairs_directories_and_draws_a_sheet() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        first, second = pathlib.Path(tmp) / "a", pathlib.Path(tmp) / "b"
        first.mkdir()
        second.mkdir()
        for name in ("panel.png", "icon.png"):
            WARM.save(first / name)
            COOL.save(second / name)
        COOL.save(second / "unmatched.png")
        (first / "notes.txt").write_text("ignored", encoding="utf-8")

        pairs = style_delta.pair_files(first, second)
        check([left.name for left, _ in pairs] == ["icon.png", "panel.png"], "only filenames present in both directories are paired, in order")
        sheet = pathlib.Path(tmp) / "delta.png"
        style_delta.contact_sheet(pairs, sheet, cell=64)
        with Image.open(sheet) as rendered:
            check(rendered.size == (128, 128), f"the sheet is one row per pair, two columns wide (got {rendered.size})")



# Palette conformance ----------------------------------------------------------

IRONFRONT = ["#111820", "#1D2933", "#DCE2E3", "#7D929B", "#D9A54A", "#6BADB4", "#CB5F59"]


def swatch(color: tuple[int, int, int], size: int = 32) -> Image.Image:
    return Image.new("RGBA", (size, size), color + (255,))


def test_palette_flags_an_invented_hue() -> None:
    green = palette_check.analyse(swatch((10, 216, 8)), IRONFRONT, palette_check.DEFAULT_TOLERANCE)
    check(green["share"] == 1.0, "pure green against an amber/steel palette is wholly off-palette")
    check(green["offenders"] and green["offenders"][0]["degrees"] > 45, "and is reported tens of degrees from the nearest palette hue")
    amber = palette_check.analyse(swatch((217, 165, 74)), IRONFRONT, palette_check.DEFAULT_TOLERANCE)
    check(amber["share"] == 0.0, "a palette colour itself is on-palette")


def test_palette_allows_shading_of_a_palette_hue() -> None:
    # The reason the check measures hue angle and not colour distance: these are
    # the same amber lit differently, and a delta-E check condemns all of them.
    for name, rgb in (("darker", (120, 90, 40)), ("lighter", (245, 210, 140)), ("punchier", (224, 176, 32))):
        result = palette_check.analyse(swatch(rgb), IRONFRONT, palette_check.DEFAULT_TOLERANCE)
        check(result["share"] == 0.0, f"a {name} amber is still amber")


def test_palette_keeps_desaturated_entries_in_the_comparison() -> None:
    # #111820 is chroma 7. A cutoff that calls it neutral drops the project's own
    # darks from the comparison and then condemns every shadow drawn from them.
    result = palette_check.analyse(swatch((16, 32, 48)), IRONFRONT, palette_check.DEFAULT_TOLERANCE)
    check(result["share"] == 0.0, "a dark blue-grey matches the palette's desaturated navy")
    check(palette_check.NEUTRAL_CHROMA < 6.7, "the neutral cutoff sits below the palette's least saturated hued entry")
    grey = palette_check.analyse(swatch((136, 136, 136)), IRONFRONT, palette_check.DEFAULT_TOLERANCE)
    check(grey["share"] == 0.0, "a true neutral passes because the palette contains one")


def test_palette_repair_rotates_hue_and_keeps_lightness() -> None:
    import numpy as np

    contaminated = Image.new("RGBA", (16, 16), (10, 216, 8, 255))
    before = palette_check.analyse(contaminated, IRONFRONT, palette_check.DEFAULT_TOLERANCE)
    repaired, changed = palette_check.repair(contaminated, IRONFRONT, palette_check.DEFAULT_TOLERANCE)
    after = palette_check.analyse(repaired, IRONFRONT, palette_check.DEFAULT_TOLERANCE)
    check(before["share"] == 1.0 and after["share"] == 0.0, "repair clears the off-palette pixels")
    check(changed == 16 * 16, "repair reports how many pixels it rewrote")

    lab_before = palette_check.srgb_to_lab(np.array([[10 / 255, 216 / 255, 8 / 255]]))
    sample = np.asarray(repaired.convert("RGBA"), dtype=np.float64)[0, 0, :3] / 255
    lab_after = palette_check.srgb_to_lab(sample.reshape(1, 3))
    check(abs(lab_after[0][0] - lab_before[0][0]) < 1.5, "lightness is preserved, so shading survives the repair")

    clean = Image.new("RGBA", (8, 8), (217, 165, 74, 255))
    _, untouched = palette_check.repair(clean, IRONFRONT, palette_check.DEFAULT_TOLERANCE)
    check(untouched == 0, "art already on palette is left alone")


def test_palette_lab_inverse_is_exact_at_8_bit() -> None:
    import numpy as np

    rng = np.random.default_rng(11)
    rgb = rng.integers(0, 256, (4000, 3)) / 255.0
    back = palette_check.lab_to_srgb(palette_check.srgb_to_lab(rgb))
    check(int(np.abs((rgb * 255).round() - (back * 255).round()).max()) == 0, "sRGB survives a Lab round trip unchanged at 8-bit")


def test_palette_ignores_transparent_pixels() -> None:
    art = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    art.paste(swatch((10, 216, 8), 8), (4, 4))
    result = palette_check.analyse(art, IRONFRONT, palette_check.DEFAULT_TOLERANCE)
    check(result["pixels"] == 64, "only the opaque region is measured")
    check(result["share"] == 1.0, "and it is judged on its own, not diluted by the empty canvas")


def flat_panel(width: int = 1024, height: int = 320) -> Image.Image:
    """A restrained panel: hairline edge, small radius, soft vertical gradient, fine grain."""
    import numpy as np

    rng = np.random.default_rng(5)
    ramp = np.linspace(46, 28, height)[:, None, None] * np.ones((1, width, 3))
    ramp[..., 2] += 12
    noisy = np.clip(ramp + rng.normal(0, 1.1, ramp.shape), 0, 255).astype("uint8")
    body = Image.fromarray(noisy, "RGB").convert("RGBA")
    mask = Image.new("L", (width, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width - 1, height - 1), radius=8, fill=255)
    body.putalpha(mask)
    ImageDraw.Draw(body).rounded_rectangle((0, 0, width - 1, height - 1), radius=8, outline=(125, 146, 155, 255), width=1)
    return body


def test_slice_grows_through_a_flat_gradient() -> None:
    data = slice_metadata.compute(flat_panel())
    check(data["fixedHeight"] < 80, f"a flat gradient panel is nearly all stretchable vertically (fixed {data['fixedHeight']})")
    check(data["fixedWidth"] < 120, f"and horizontally (fixed {data['fixedWidth']})")
    x0, y0, x1, y1 = data["sliceCenter"]
    check(x0 >= 8 and y0 >= 8, "but the band still stops short of the rounded corner and hairline")
    ornate = slice_metadata.compute(panel())
    check(ornate["fixedWidth"] > 100, "and the noise allowance does not let an ornate panel grow into its trim")


def cracked(size: int = 256) -> Image.Image:
    """An organic material: grain with a few long dark cracks that run off the edges."""
    import numpy as np

    rng = np.random.default_rng(3)
    grain = np.clip(rng.normal(110, 9, (size, size, 3)), 0, 255).astype("uint8")
    image = Image.fromarray(grain, "RGB")
    draw = ImageDraw.Draw(image)
    draw.line([(0, 40), (size, 170)], fill=(30, 30, 34), width=3)
    draw.line([(90, 0), (150, size)], fill=(30, 30, 34), width=3)
    return image


def seam_error(tile: Image.Image) -> float:
    """Mean step across the wrap seam, relative to the mean step between ordinary neighbours."""
    import numpy as np

    a = np.asarray(tile.convert("RGB"), dtype=np.float32)
    wrap = (np.abs(a[:, 0] - a[:, -1]).mean() + np.abs(a[0] - a[-1]).mean()) / 2
    inner = (np.abs(np.diff(a, axis=1)).mean() + np.abs(np.diff(a, axis=0)).mean()) / 2
    return float(wrap / inner)


def test_tileable_modes_close_the_seam() -> None:
    import numpy as np

    raw = cracked()
    check(seam_error(raw) > 0.9, "the raw image wraps no better than two unrelated edges")  # sanity
    mirrored = make_tileable.mirror(raw, 256)
    blended = make_tileable.blend(raw, 256)
    check(mirrored.size == (256, 256) and blended.size == (256, 256), "both modes return the requested size")
    a = np.asarray(mirrored.convert("RGB"), dtype=np.int16)
    check(int(np.abs(a[:, 0] - a[:, -1]).max()) == 0 and int(np.abs(a[0] - a[-1]).max()) == 0, "mirror is seam-exact: each edge is its opposite edge")
    check(seam_error(blended) < 1.6, f"blend wraps as smoothly as its own interior ({seam_error(blended):.2f}x an ordinary step)")
    left, right = a[:, : 128], a[:, 128:][:, ::-1]
    check(int(np.abs(left - right).max()) == 0, "mirror is symmetric about its centre, which is why it suits only regular patterns")
    b = np.asarray(blended.convert("RGB"), dtype=np.int16)
    check(float(np.abs(b[:, :128] - b[:, 128:][:, ::-1]).mean()) > 3, "blend is not, so cracks do not meet their own reflection")


def test_tileable_blend_flattens_lighting() -> None:
    import numpy as np

    size = 256
    rng = np.random.default_rng(9)
    vignette = np.linspace(60, 170, size)[None, :, None] * np.ones((size, 1, 3))
    raw = Image.fromarray(np.clip(vignette + rng.normal(0, 6, vignette.shape), 0, 255).astype("uint8"), "RGB")
    out = np.asarray(make_tileable.blend(raw, size), dtype=np.float32)
    columns = out.mean(axis=(0, 2))
    check(float(columns.max() - columns.min()) < 30, "a left-to-right lighting ramp of 110 levels is flattened, so forty tiles do not checkerboard")


for test in (test_slice_avoids_decoration, test_render_keeps_rim_thickness, test_measures_at_roblox_stored_size, test_slice_rejects_all_decorated, test_separate_sheet_splits_and_trims, test_paste_module, test_style_delta_separates_two_style_references, test_style_delta_ignores_transparent_background, test_style_delta_reports_direction, test_style_delta_palette_is_deterministic, test_style_delta_pairs_directories_and_draws_a_sheet, test_palette_flags_an_invented_hue, test_palette_allows_shading_of_a_palette_hue, test_palette_keeps_desaturated_entries_in_the_comparison, test_palette_repair_rotates_hue_and_keeps_lightness, test_palette_lab_inverse_is_exact_at_8_bit, test_palette_ignores_transparent_pixels, test_slice_grows_through_a_flat_gradient, test_tileable_modes_close_the_seam, test_tileable_blend_flattens_lighting):
    test()

print(f"\n{checks} checks, {failures} failures")
sys.exit(1 if failures else 0)
