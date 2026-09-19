# GUI art: prompts that import cleanly, and placement that stays clean

Generated 2D art fails in Studio in three ways, and all three are fixable before anyone looks at a
screenshot: a Roblox background drawn under art that already has its own shape, art stretched to an
aspect it was not drawn at, and a packed sheet applied as one image. The prompt templates below
close the first, `luau/GuiArt.luau` closes the second and third structurally, and `tools/` turns a
sheet into pieces with measured metadata.

The templates and tooling were used in two full Studio builds (September 16–17, 2026) and produced
art that went in without a stacked background, a nested border or a stretched corner.

## The pipeline

1. **Generate** with the template for the type (below). Carry one art direction through a session by
   passing the first accepted artifact as `reference_asset_ids` on every later `generation_gui`
   call; `generation_gui` has no `game_style`, so the style words belong in the prompt.
2. **Split and trim.** Sheets come back as one image even when the prompt asks for separate objects.
   `python references/tools/separate_sheet.py sheet.png --out-dir pieces/` writes one trimmed PNG
   per object and prints each native aspect. Objects are found by fully transparent rows and
   columns, so the "wide transparent gaps" clause in the icon template is what makes it work.
3. **Measure slices** for anything that must resize (panels, wide buttons):
   `python references/tools/slice_metadata.py panel.png --preview 720x400` prints `size` and
   `sliceCenter` and renders a preview at that size to check by eye. Roblox stores an upload at no
   more than 1024 px on the longer side and reads `SliceCenter` in stored pixels, so the tool
   measures at that size: a 1496x659 panel is measured as 1024x451 (checked against
   `AssetService:CreateEditableImageAsync`). Metadata taken from the original file slices the wrong
   pixels in game.
4. **Upload** by a route the connected server actually exposes — see the skill's import-route step.
   Studio's `upload_image` rejected a ForgeGUI storage URL as untrusted; serving the pieces locally
   (`python -m http.server --bind 127.0.0.1`) and uploading `http://localhost:<port>/<file>.png`
   worked, as did Open Cloud with `assetType: "Image"`.
5. **Record** each asset id with its aspect and slice metadata in one registry module, and place art
   only through `luau/GuiArt.luau`.

Both tools need Pillow; `slice_metadata.py` also needs NumPy. They run locally on the artifact file
and never call a network service.

## Templates by type

Every template ends with the same clauses, and they are what keep the output import-ready: "fully
transparent background", "no text", "no drop shadow outside the shape", "no surrounding frame or
border around the artwork".

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
  `paste_module.py`. That is 22 checks, with no arguments and no network.
- `lune run references/tests/qa`, run from the skill root, checks `UiCheck` against stubbed GUI
  trees. `UiCheck` audits a live ScreenGui against the screen templates above: art chrome, icons in
  chips or on plates, strokes inside framed art, and backdrops wired to close. The same run checks
  `WorldCheck`. That is 46 checks.
- In Studio, run `UiCheck` on each screen you built, as described in `world-and-ui-checks.md`.
- In Studio, `screen_capture` at the target viewport *and* at a phone-sized one. A HUD that is
  correct at 1920x1080 and broken at 390x844 is the normal failure.
- Read the slice metadata off the `--preview` render before uploading, not off a panel that is
  already in a place.
