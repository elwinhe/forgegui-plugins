# GUI art: prompts that import cleanly, and placement that stays clean

Generated 2D art fails in Studio in three ways, and all three are fixable before anyone looks at a
screenshot: a Roblox background drawn under art that already has its own shape, art stretched to an
aspect it was not drawn at, and a packed sheet applied as one image. The prompt templates below
close the first, `luau/GuiArt.luau` closes the second and third structurally, and `tools/` turns a
sheet into pieces with measured metadata.

The templates and tooling were used in two full Studio builds (September 16–17, 2026) and produced
art that went in without a stacked background, a nested border or a stretched corner.

## The pipeline

Use `preparation-installation.md` first: server `asset_prepare` handles supported
alpha conversion and resizing, and `artifact_publish` publishes the prepared
PNG member. Do not repeat these transformations locally. The local tools below
remain for sheet splitting and nine-slice measurement, which #606 does not
provide. Re-register locally changed bytes before server publication; preserve
their provenance separately.

1. **Generate** with the template for the type (below). Carry one art direction through a session by
   passing the first accepted artifact as `reference_asset_ids` on every later `generation_gui`
   call; `generation_gui` has no `game_style`, so the style words belong in the prompt.
2. **Split and trim.** Sheets come back as one image even when the prompt asks for separate objects.
   `python references/tools/separate_sheet.py sheet.png --out-dir pieces/` writes one trimmed PNG
   per object and prints each native aspect. Objects are found by fully transparent rows and
   columns, so the "wide transparent gaps" clause in the icon template is what makes it work.
   An icon drawn as *disconnected strokes* — a crosshair, a dashed ring — gets split apart by the
   same rule. The tell is a piece with an extreme aspect ratio and a grid index that skips a row.
   Raise `--min-gap` above the gaps inside the icon but below the gaps between icons (80 worked on a
   1520 px sheet with 250 px icons), or ask the prompt for one connected shape.
3. **Measure slices** for anything that must resize (panels, wide buttons):
   `python references/tools/slice_metadata.py panel.png --preview 720x400` prints `size` and
   `sliceCenter` and renders a preview at that size to check by eye. Roblox stores an upload at no
   more than 1024 px on the longer side and reads `SliceCenter` in stored pixels, so the tool
   measures at that size: a 1496x659 panel is measured as 1024x451 (checked against
   `AssetService:CreateEditableImageAsync`). Metadata taken from the original file slices the wrong
   pixels in game.
4. **Publish** the prepared/registered member with `artifact_publish` when usable.
   Otherwise upload by a route the connected server actually exposes — see the skill's import-route step.
   Studio's `upload_image` rejected a ForgeGUI storage URL as untrusted; serving the pieces locally
   (`python -m http.server --bind 127.0.0.1`) and uploading `http://localhost:<port>/<file>.png`
   worked, as did Open Cloud with `assetType: "Image"`.
5. **Record** each asset id with its aspect and slice metadata in one registry module, and place art
   only through `luau/GuiArt.luau`.

Both tools need Pillow; `slice_metadata.py` also needs NumPy. They run locally on the artifact file
and never call a network service.

## Style references, and the user's own image

The inspected `generation_gui` contract accepts `prompt`, `type`, `count`, `reference_asset_ids` and
`request_id`. There is no `game_style`, and there are no style fields — the schema is
`additionalProperties: false`, so passing `style_id`, `style_version` or `style_brief` is a hard
rejection rather than a silently ignored extra. Style words go in the prompt; style *images* go in
`reference_asset_ids`, which holds up to **8** entries and accepts **owned asset UUIDs and
`mcp-artifact:<job>:<index>` references only**. Every reference must resolve to an image;
finished model and audio artifacts are invalid even when their identifier format is valid.
Re-check the live schema before use. Style pins on `generation_image` and `generation_model_3d`
do not imply support on `generation_gui`; their separate limits and image-family restrictions
are documented in `references/style-identity.md`.

That last constraint is the one that shapes the whole procedure: **a file on disk is not a
reference.** A PNG the user pasted, screenshotted or downloaded cannot be passed to
`generation_gui` at all until something has put it into ForgeGUI's ID space.

### When the upload family is exposed

`image_upload_authorize` → upload the bytes → `image_upload_register` returns an immutable owned
asset UUID, and that UUID goes straight into `reference_asset_ids`. `references/style-identity.md`
has the full procedure. Discover the live tool list first (SKILL.md §1) — do not assume.

### When it is not: the style-plate substitute

The 2026-09-19 staging discovery reported neither the upload pair nor the `style_*` family.
Use this substitute only if fresh discovery still finds no supported upload route; this dated
observation does not establish current availability. Do not hunt for a workaround that uploads
the file somewhere else. Include the paid plate and any comparison generations in the approved
asset/call budget before generating. Use a style plate:

1. **Read the user's image and write it down.** Palette as hex, material language, line weight,
   shading, corner treatment, the mood in one sentence. This is the only step where the user's image
   is actually consulted, so be specific — everything downstream inherits these words.
2. **Generate the plate.** One `generation_image` call, type `thumbnail`, prompting for a style
   sheet rather than a screen: a few swatches, a rim treatment, one representative shape. Keep the
   completed job's image-backed `mcp-artifact:` ref. If a project style pin is available and the
   live image schema supports it, apply it using `references/style-identity.md`.
3. **Pin every GUI call to it.** Pass that ref in `reference_asset_ids` on every `generation_gui`
   call for the project, and record it as the manifest's `style_refs` entry. One plate, every
   screen.
4. **Disclose it.** Say in the report that the reference was reconstructed from a description
   because no image-upload route was exposed, and name the two tools that would remove the step.

This substitute tests generated-image references, not direct conditioning on the user's original
image. Report measured results only after running the comparison; the recipe alone is not evidence.
When the upload family is exposed, replace steps 1 and 2 with the full authorize → upload bytes →
register sequence, then pass the returned owned image UUID to GUI calls.

### Show that it worked

Adherence is judged against the reference itself: put each screen beside the reference image or
plate, say where it follows and where it drifts, and record the conditioning evidence the calls
returned, where supported — the style pin echoed back, the `style_application` in force, which
reference IDs were accepted, or an `unsupported_style_conditioning` rejection. `generation_gui`
has no style-identity fields: record accepted image references and the Studio comparison instead
of requiring `style_application`. Accepted input does not demonstrate visual adherence.

When two comparable runs already exist — one per reference, in two directories with matching
filenames — the palette diagnostic adds a number:

```sh
python references/tools/style_delta.py runs/ref-a/ runs/ref-b/ --contact-sheet delta.png
```

It reports an **unweighted palette-center distance** in CIELAB delta-E, plus absolute hue distance
and signed saturation/value deltas, and writes the side-by-side sheet. Hue is unsigned:
350→10 and 10→350 both measure 20 degrees, not clockwise/counterclockwise motion.
The palette distance ignores color proportions, spatial arrangement and causality. A near-zero
value means matched centers are close, not that color distribution or style is the same; reversed
90/10 red/blue shares can score nearly zero. Use the visual comparison/contact sheet as well.
The tool's 5.0 is an advisory comparison point, not a validated whole-image or style-adherence
threshold (nor is a single-color just-noticeable difference one): ordinary generation variance can
clear it with no style effect, and a reference
that moved shape, material or composition while holding the colours can land below it. Read it as a
description of a colour difference, never as proof of one, and do not commission extra paid
generations solely to produce it. Only opaque pixels are measured, because averaging in a
transparent background drags every palette toward the same grey and makes two different styles look
identical.

## Templates by type

Every template ends with the same clauses, and they are what keep the output import-ready: "fully
transparent background", "no text", "no drop shadow outside the shape", "no surrounding frame or
border around the artwork".

`type` accepts five values: `gui_button`, `gui_icon`, `gui_panel`, `gui_asset` (the default) and
`gui_frame`. The four below have been exercised on real builds. `gui_frame` has not — it is in the
live schema and presumably returns a border or window chrome, but nothing here has tested what it
returns or how it slices, so treat a first use as an experiment and write down what comes back
rather than assuming it behaves like `gui_panel`. (Submit GUI jobs one at a time and wait for each to finish. Twice, a second job submitted within a
few seconds of the first ended `outcome_unknown` while the first succeeded. The one `gui_frame` attempt so far, a hairline window frame
referenced to an existing button, ended `outcome_unknown` with `retryable: false`. Per the job
rules it was not retried, so the type is still unverified.)

### `gui_button`: a matched pair

```text
A game UI kit for a <genre and setting>: one wide rounded button and one square icon button, in <two
or three palette colours>, with <one motif> detailing and a subtle <accent> rim. Clean flat vector
style, centered, fully transparent background, no text, no drop shadow outside the shape, no
surrounding frame or border around the artwork.
```

`count: 2` returns two variants of the pair; pick one as the style reference for the rest of the
session. Text goes on top in Luau, never in the art, so one button serves every label.

### `gui_icon`: a sheet of eight

```text
A game icon sheet: eight separate, individually centered icons arranged in a 4 by 2 grid with wide
fully transparent gaps between every icon so none touch or overlap. Icons, in order: <eight short
noun phrases>. Polished stylized <genre> game UI style matching <palette>, soft highlights, subtle
<accent> rim light. No text, no background, no frame, no shadow outside each icon.
```

"Wide fully transparent gaps ... so none touch" is the clause the splitter depends on. Icons came
back in the listed reading order (left to right, top row first), so pieces can be named from the
list. Eight per call is one generation instead of eight.

### `gui_panel`: a window background

```text
A large empty game menu panel for a <genre and setting>: a wide rounded rectangle window with a
<interior colour> interior, an ornate <accent> rim, <corner motif> from the lower corners, a small
<crest> centered on the top edge. The interior is empty and clean so text and buttons can sit on
it. Polished stylized <genre> game UI, fully transparent background outside the panel, no text, no
buttons inside, no drop shadow outside the shape.
```

The panel carries its own rim, so it is the whole window background; never put it inside a Roblox
frame that has its own background or stroke. Decoration painted into the interior (clouds, scenery)
limits how far it can stretch: past roughly 1.5 times its native aspect, generate a plain interior.

### `gui_panel`, restrained: when the brief is not a fantasy game

The template above asks for "an ornate rim", a corner motif and a crest, and that is exactly what
comes back. For a stylized casual game it is right. For anything grounded (a military shooter, a
sim, a productivity-flavoured tycoon) it is the single biggest source of the "AI-looking UI"
complaint: a thick gold rim with corner ornaments around every window. Ask for the opposite, in as
many words, and reference the project's flat button so the two are one family:

```text
A large empty menu window panel for a <genre and setting>, in the same family as the reference flat
<colour> button bar: one wide rectangle with a small <n> pixel corner radius, a flat <interior
colour> interior shading very slightly darker toward the bottom, and a single thin one-pixel
<hairline colour> edge with a faintly brighter top edge. Completely restrained and flat: no ornate
rim, no gold, no corner brackets, no rivets, no crest, no notches, no bevel, no glow, no scanlines,
no inner frame. The interior is perfectly empty and uniform so it can be nine-slice stretched to any
size. Clean flat vector UI, centered, fully transparent background outside the panel, no text, no
buttons, no icons, no drop shadow outside the shape, no surrounding frame or border around the
artwork.
```

The negatives are doing the work; each one names something the model adds by default. Generate
`count: 2` and choose by **how it slices**, not by eye: on the tested pair one variant carried two
stray marks on its bottom edge that were invisible at a glance and pinned the stretchable band at
x = 266 of 1024. Run `slice_metadata.py` on each and keep the one with the small fixed border.

Once the panel changes family, sweep every other surface still on the old one: the square icon
button, selection cards, the modal. A flat menu in front of an ornate loadout screen reads as two
games. `GuiArt` accepts any 9-slice art, so a flat bar sliced square replaces the square plate with
no new generation.

`slice_metadata.py` grows the stretchable band while neighbouring lines stay calm. On flat art the
calmest window scores about the same as every other interior line (grain, dither, a soft gradient),
so a purely relative rule stops at the first line a hair noisier and reports most of the panel as
fixed border. The band therefore also grows through anything below twice the interior's own
typical line score, capped so an ornate interior cannot use the allowance to grow into its
decoration, and growth may run past the search margin because the rim's own scores stop it.

### `gui_asset`: logos and ribbons

```text
A game title logo reading <TITLE> in bold chunky <genre> letters: <letter colour> letterforms with a
<glow colour> inner glow, a thick <outline colour> outline, <one emblem> behind the word, and <one
small scene element> beneath the text. Centered, polished stylized game logo, fully transparent
background, no extra text, no frame.
```

```text
A wide horizontal game ribbon banner for a <genre and setting>: a long <colour> fabric ribbon with
folded <accent>-trimmed tails on both ends and a clean empty center band for a title, a small
<accent> gem at the top center. Polished stylized <genre> game UI, fully transparent background, no
text, no drop shadow outside the shape, no frame.
```

Short text inside a logo rendered correctly. Keep every other label out of the art.

### Full-bleed backdrops: `generation_image`, not `generation_gui`

Loading splashes and title backdrops are scenes, not UI parts. `generation_image` with type
`thumbnail` accepts `game_style`, which carries the same art direction:

```text
A wide cinematic game title backdrop: <scene>, <lighting>. Painterly stylized <genre> art, vibrant
but soft, lots of open sky in the upper third for a logo, no text, no characters, no UI.
```

Place it with `ScaleType.Crop`; it is the one piece of art that should fill the screen at any aspect.

The same call makes map cards and mode tiles. Ask for "calm darker space on the left for overlaid
interface text" and lay the title over a bottom-up gradient; a card built from generated key art and
real config values (mode, team size, score limit) fills the dead half of a title screen with
something true. It also gives you a **lighting target**: if the key art shows overcast dusk with
sodium floods and the playable map is lit like a stock noon baseplate, the map is the thing that is
wrong.

### Tiling materials: `thumbnail` again, then make it tile

There is no texture or material type. The type decides what kind of image comes back far more than
the prompt does:

| `type` | The same "flat weathered concrete wall, edge to edge, no objects" prompt returned |
| --- | --- |
| `mixed` | A gold dollar coin on transparency. It is an object generator; a material is not an object. |
| `thumbnail` | A true edge-to-edge photograph of formwork concrete, tie holes and all. |

So generate materials as `thumbnail` with `game_style: "general"`, and say "flat, straight-on
orthographic", "even overcast lighting with no shadows and no vignette", "uniform density across the
whole image so it can tile", and list what must not appear (objects, horizon, text, perspective).

Nothing comes back seamless, whatever the prompt says. `tools/make_tileable.py` fixes that, and the
method has to match the material:

```bash
python references/tools/make_tileable.py raw.png tile.png --mode mirror --preview check.jpg
python references/tools/make_tileable.py raw.png tile.png --mode blend  --preview check.jpg
```

- `mirror` (a 2x2 of the image and its reflections) is seam-exact by construction and right for
  **regular** patterns: corrugated sheet, formwork panels, planks, brick.
- `blend` (the image cross-faded with itself rolled by half) is right for **organic** materials:
  asphalt, dirt, rust, plaster. Mirroring those makes every crack meet its own reflection, and the
  result reads as a kaleidoscope from across the map. `blend` also flattens large-scale lighting
  first, because a gradient invisible in one tile is a checkerboard across forty.

Always look at the 3x3 preview before uploading. In Studio, apply the tile as `Texture` instances at
a fixed `StudsPerTile` on the faces of ordinary Parts, so a 60-stud wall is as sharp as a 6-stud one
and the collision stays exact. Do not generate a building-sized mesh to carry a wall material: one
1024 px map across a whole building goes soft the moment a player walks up to it.

## Colour the generator invented

Every sheet from a real IRONFRONT run came back carrying a hue the project never
asked for. A weapon sheet prompted for off-white and amber was **21% off-palette**,
mostly pure green. Adding "absolutely no green" to the next prompt worked — and
the sheet came back with magenta instead. The contamination sits in **opaque**
pixels, not in the anti-aliased edge, so it is painted by the generator rather
than prompted, and negative prompts only move it.

This is the single most reliable tell that a UI was generated rather than
authored. At icon size it reads as dirt on the silhouette; across a screen it is
what makes a set look assembled instead of designed.

Check it, and repair it rather than re-rolling:

```sh
python references/tools/palette_check.py art/*.png --project forgegui-project.json
python references/tools/palette_check.py art/*.png --project forgegui-project.json --fix
```

It judges **hue angle only** — lightness and saturation are ignored on purpose, so
shading, highlights and a punchier accent all pass while a foreign hue fails.
`--fix` rotates each off-palette pixel onto the nearest palette hue, keeping its
lightness and clamping chroma to the palette's own maximum, so the silhouette and
shading survive. On that run it took five sheets from 3–21% off-palette to 0.00%.

Two things to keep straight. Keep the originals: the repair is lossy and a
reviewer may want the before. And set the project palette's darks carefully —
the check treats an entry below chroma 4 as a neutral with no hue, and a moody
palette's darks are desaturated but *still hued* (`#111820` is chroma 7 at hue
265), so a higher cutoff drops them from the comparison and then condemns every
shadow drawn from them.

## Placing art: `GuiArt`

```lua
local GuiArt = require(ReplicatedStorage.Visuals.GuiArt)
local Art = GuiArt.new(require(ReplicatedStorage.Game.ArtRegistry))

local window = Art.panel("panel", { Size = UDim2.fromOffset(720, 400), Parent = screen })
local coin = Art.image("coin", { Size = UDim2.fromOffset(48, 48), Parent = hud })
local buy = Art.button("buttonWide", { Size = UDim2.fromOffset(196, 80), Parent = card })
```

A registry entry is `{ id = "rbxassetid://...", aspect = 2.27 }`, plus `size` and `sliceCenter` from
`slice_metadata.py` for anything placed with `panel`. `GuiArt.new` validates the registry and
refuses malformed ids or slice rectangles, which otherwise render as blank or smeared elements with
no error at all.

What it enforces:

- **No Roblox shape under art.** Background transparency 1, no border, no `UICorner`, `UIStroke` or
  `UIGradient`, even when the caller's props ask for one.
- **Native aspect.** `image` and `button` are fitted and aspect-locked, so they cannot be stretched.
- **Slices from measurement.** `panel` uses `ScaleType.Slice` with the measured centre and keeps
  `SliceScale` in step with the rendered size, so corners stay in proportion and never overlap. A
  panel with no slice metadata falls back to fitted art rather than stretching.
- **No `AutoButtonColor`.** Art has no background to tint, so press feedback belongs to motion
  (`ui-motion.md`, `Motion.pressable`), not to a colour change on an invisible frame.

Text and chrome (glass pills, progress bars, dividers) are ordinary Roblox frames and keep their
corners. They are drawn beside or on top of art, never under it. Inside framed art, chrome also
drops its stroke (see Screen templates).

## Read the UI before decorating it

Generated backgrounds stacked on existing ones because nothing looked at what was already there.
Before placing art on or inside an existing element, call `GuiArt.conflicts(element)`. It lists a
visible background, any `UICorner`/`UIStroke`/`UIGradient`, and any child that already shows an
image. Replace what it reports, or place the art elsewhere; never add a layer on top.

## Screen templates

A shop, a settings screen and an action bar were rebuilt on these templates. A play-test had found
modals that closed on any click that missed a button, and icons inside borders they did not need.
`luau/UiCheck.luau` checks screens against the templates (see `world-and-ui-checks.md`),
`ui-pass.md` is the procedure that uses them, and `Motion.modal` applies the modal input rule. The
numbers from that build appear below as examples only. Measure your own art.

### Modal: shop, upgrades, settings, confirmations

```lua
local function new(className: string, props: { [string]: any }): Instance -- parent last
	local object = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then
			(object :: any)[key] = value
		end
	end
	object.Parent = props.Parent
	return object
end

-- Backdrop: dims the world and sinks every click that misses the panel. No handler.
local backdrop = new("TextButton", {
	Name = "ShopBackdrop", Text = "", AutoButtonColor = false, Active = true, Modal = true,
	Selectable = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 80, Parent = screen,
})
local anchor = new("Frame", { -- carries the responsive UIScale
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.53), Size = UDim2.fromOffset(1000, 560), ZIndex = 90, Parent = screen,
})
local panel = new("Frame", { -- Active: clicks on empty space stop here
	Active = true, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = anchor,
})
Art.panel("panel", { Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = panel })
-- header ribbon and title over the top rim; close button over the top-right corner
local modal = Motion.modal(panel, { backdrop = backdrop, blur = 16 })
close.Activated:Connect(modal.close)
```

- **What closes it.** The close button, which uses the same art and sits top right on every modal.
  The screen's own key. Gamepad B. Handle B even when `InputBegan` reports it as processed, because
  gamepad selection marks it that way. **Never** close from the backdrop, and never from Escape,
  which Roblox's menu owns.
- **One modal at a time.** Opening one closes the other.
- **Measure the inner area** of the panel art at the size you place it. Content stays inside that
  area and off the crests. For example, one panel placed at 1000x560 had an inner area of x 35 to
  965 and y 69 to 525. A crest hung below its header ribbon and another rose above the bottom edge.

### Content inside framed art

- The panel art is the only frame. Cards and rows inside it are **borderless fills**: ink colour,
  a corner radius of about 20, a soft vertical gradient, and no `UIStroke`. A stroked card inside a
  framed panel reads as a frame inside a frame.
- Check fills over painted detail. In one build, rows at 0.42 transparency over clouds painted in
  the panel art read as a different kind of row; at 0.12 they matched.
- A stroke on text for legibility is fine. A control's own outline, such as a switch track, is part
  of the control.

### Icons

- An icon stands alone, with **no chip, ring, disc or plate behind it**. Depth comes from a drop
  shadow: a sibling copy of the art, ink-coloured, with `ImageTransparency` 0.6, 3 to 5 px lower
  and one `ZIndex` below. It has to be a sibling because a child always renders above its parent.
- Do not mix framed icon art with bare icons in one row. For example, one action bar put a hub icon
  that draws its own frame beside bare chest, gear and star icons. It was fixed by swapping in a
  bare icon.
- An action bar slot is a transparent frame holding four things: the shadow, the icon as an
  `ImageButton` with `Motion.pressable`, the label under it, and the key hint at its top left.

### Upgrade card

From top to bottom:

1. the icon;
2. the title;
3. the level (`LEVEL 4 / 20`) with a progress bar;
4. the effect, in one RichText label: `Carry 44 > 52`, with the current value dimmed, the arrow
   gold and the next value green;
5. a one-line note;
6. the buy button, with the coin and price on the wide button art.

The card answers three questions without arithmetic: what do I get, what does it cost, can I
afford it.

| State | Buy button | Price | Note | On tap |
| --- | --- | --- | --- | --- |
| Affordable | Full colour | White | "Ready to upgrade", green | Click sound, purchase request |
| Unaffordable | Dimmed | Soft red | "Need 51 more coins", red | Low click, the button wobbles (rotation), the note pulses; no request |
| Maxed | Replaced by a check icon and MAXED | Hidden | "Fully upgraded", gold | Nothing |
| Just purchased | Updates when the level attribute rises | | | Card and icon pulse, sparkle burst, purchase sound |

- Put the balance in a badge over the panel's top-left corner, mirroring the close button. The
  HUD's own counter is dimmed behind the backdrop.
- A locked section lists each requirement with its progress and a state icon (a lock, then a
  check). Its button reads LOCKED until every requirement is met.

### Settings toggles

- The whole row is the button, and the switch inside it takes no input. A small target inside a
  large row makes players miss.
- The switch is fills only: a track colour for the state, a cream knob with a shadow, and ON/OFF
  text.
- A footer line says how to close the screen ("Press M or B to close") and what the settings apply
  to.

## Checking the result

- `python references/tools/test_tools.py` checks the splitter and the slice tool on synthetic art.
  The slice centre avoids a crest, side gems and painted clouds, a sliced preview keeps its rim
  thickness, and a split icon closer than `--min-gap` stays whole. It also checks
  `paste_module.py`. That is 65 checks, with no arguments and no network.
- `lune run references/tests/qa`, run from the skill root, checks `UiCheck` against stubbed GUI
  trees. `UiCheck` audits a live ScreenGui against the screen templates above: art chrome, icons in
  chips or on plates, strokes inside framed art, and backdrops wired to close. The same run checks
  `WorldCheck`. The suite includes provenance visibility and coverage regressions.
- In Studio, run `UiCheck` on each screen you built, as described in `world-and-ui-checks.md`.
- In Studio, run `UiCheck.provenance` on every screen whose generated-art provenance was put in
  scope during planning, even if it ended up primitive-only. Include the registry, findings and
  unresolved substitutions. Coverage is registered image surfaces / counted surfaces (registered
  images, unregistered images and primitive surfaces). Text is tallied separately, although a
  label's fill/border also counts as a primitive. This is caller-maintained **registry-backed
  attribution**, not proof of generation; retain ForgeGUI job/artifact/publication records in the
  ledger. Missing registry means unverified provenance. `AllowPrimitive` suppresses a warning
  without turning a primitive into art. There is no minimum ratio: valid native controls remain
  allowed. The ratio counts structurally visible elements, not screen area, pixels or quality;
  see `world-and-ui-checks.md` for visibility limits.
- In Studio, `screen_capture` at the target viewport *and* at a phone-sized one. A HUD that is
  correct at 1920x1080 and broken at 390x844 is the normal failure.
- Read the slice metadata off the `--preview` render before uploading, not off a panel that is
  already in a place.
