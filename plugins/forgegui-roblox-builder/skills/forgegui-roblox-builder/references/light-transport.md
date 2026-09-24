# Light transport: bounce light, contact shadows, firelight, water, covered passages

Roblox lights a scene with a sun, three flat ambient colours and whatever local lights you place. It has no bounce light, no ambient occlusion, and its sky light barely dims inside a roofed passage. A scene lit only by those reads as clean but weightless: shaded walls glow the same colour over grass and over snow, props look set down on the ground rather than standing in it, and a gatehouse tunnel is as bright as the street. Five reviewed modules approximate what is missing. None of them needs an asset to work, each owns only what it creates, and each gives back what it borrowed.

| Module | Runs | What it adds | Level setting |
| --- | --- | --- | --- |
| `luau/GlobalIllumination.luau` | client, every frame | ground-bounce colour, colour bleed from sunlit surfaces, darker ambient under cover | `setLevel(0..1)`: off / low / high |
| `luau/ContactShadows.luau` | client, every frame | soft dark blob where props, buildings and characters meet the ground | `setEnabled(bool)` |
| `luau/FireLight.luau` | client, every frame | flicker, moving shadows, soft plume and bright embers on fires near the camera | `setShadowLevel(0..1)`: 0 / 4 / 8 shadowed |
| `luau/WaterReflections.luau` | client or Edit, once | terrain water reflection strength | `setLevel(0..1)`: 0.08 / 0.3 / 0.5 |
| `luau/PassageShade.luau` | Edit, once per model | baked gradient shade on the floor, walls and ceiling of walk-through landmarks | `strength` option |

Reach for them after a lighting preset is chosen (`lighting-presets.md`) and the world is built, as part of the lighting-mood step. They suit any ground: the bounce colour comes from what the ground actually is.

## Using them

Ship the four runtime modules as ModuleScripts in `ReplicatedStorage` and start them from one LocalScript. Wire each level to your settings menu. The modules never read a settings store themselves.

```lua
local RS = game:GetService("ReplicatedStorage")
local GI = require(RS.GlobalIllumination)
local Contact = require(RS.ContactShadows)
local Fire = require(RS.FireLight)
local Water = require(RS.WaterReflections)

GI.start({
	level = 1,
	ignore = function() return { workspace.NPCs, workspace.Effects } end, -- moving things rays skip
})
Contact.start({
	roots = { workspace.World },
	kinds = { -- by model name, minus a trailing _<n>
		house = { shape = "rect", spread = 1.18, strength = 0.5 },
		wall = { shape = "rect", spread = 1.12, strength = 0.45 },
		crate = { shape = "round", spread = 1.3, strength = 0.5 },
		tree = { shape = "round", spread = 0.32, strength = 0.45 }, -- trunk, not crown
	},
	characterFolders = { workspace.NPCs },
	textures = { round = "rbxassetid://<round id>", rect = "rbxassetid://<rect id>" },
})
Fire.start({ shadowLevel = 0.5 })
Water.setLevel(1)

-- From the settings menu:
settings.changed:Connect(function(key, value)
	if key == "globalIllumination" then GI.setLevel(value)
	elseif key == "contactShadows" then Contact.setEnabled(value)
	elseif key == "fireShadows" then Fire.setShadowLevel(value)
	elseif key == "reflections" then Water.setLevel(value) end
end)
```

Tagging instead of naming: add the CollectionService tag `ForgeGUIContactShadow` to any Model or BasePart (optional attributes `ContactShadowShape` = `"rect"`/`"round"`, `ContactShadowSpread`, `ContactShadowStrength`), and `ForgeGUIFire` to any fire part or Attachment (optional `FireScale` 0.5–3). Tags stream in and out with the instance.

Passage shade is an Edit-time step. Paste the module body into `execute_luau` (drop the final `return PassageShade`) and call it for each walk-through model, then save:

```lua
local report = PassageShade.apply(workspace.World.Gatehouse, { texture = "rbxassetid://<rect id>" })
print(report.ceiling, report.halfWidth, table.concat(report.guessed, ","))
```

It raycasts the model to find the floor, the ceiling and the inner walls. If it could not find a value it falls back to a fraction of the bounding box and lists it in `guessed`. When anything is guessed, check it in a capture, or pass `frame`, `halfWidth` and `ceiling` yourself.

### Textures

Contact shadows and passage shade look best with a soft black-alpha gradient PNG. Make one and upload it (`asset-upload.md`):

```
python references/tools/make_gradient.py --shape round contact_round.png   # props, trees, characters
python references/tools/make_gradient.py --shape rect  contact_rect.png    # buildings, walls, passages
```

`--shape band` fades along one axis only and `--shape vertical` goes from opaque at the bottom to clear at the top. `--size` defaults to 256 and `--power` to 1.4, which matches the curve that shipped. Without textures the modules still work:

- ContactShadows draws each blob as five nested rounded SurfaceGui frames, a stepped radial falloff.
- PassageShade uses a SurfaceGui UIGradient that fades along the passage only.

The textures look smoother and cost less, so upload them before shipping.

### Stop and clear

`GI.stop()`, `Contact.stop()`, `Fire.stop()`, `Water.clear()` and `PassageShade.clear(model)` are idempotent and return `false` when there was nothing to undo.

## Settings and defaults

| Setting | Off | Low | High | Notes |
| --- | --- | --- | --- | --- |
| GI level (`setLevel`) | ≤ 0.01: ambients eased back to the base, bounce lights fade out | < 0.75: 10-stud cells, ±4 cells, 24 bounce lights, 24 cells traced a frame | 6-stud cells, ±7 cells, 64 lights, 48 cells a frame | the ground probe runs every 0.25 s at both levels: 28 down rays and 16 up rays |
| Fire shadows (`setShadowLevel`) | 0 shadowed | 4 nearest | 8 nearest | at most 10 fires within 140 studs are upgraded; the set is re-picked every 0.5 s |
| Water (`setLevel`) | `WaterReflectance` 0.08 | 0.3 | 0.5 | high stops at 0.5 (see below) |
| Contact shadows | `setEnabled(false)` | — | nearest 140 statics within 170 studs; 24 characters within 90 | blob opacity 0.5 statics, 0.55 characters; fades out over a 10-stud jump |
| Passage shade | `clear` | `strength` < 1 | default: floor 0.7, walls 0.6, ceiling 0.65 opacity | aim for a covered floor 40–55 % darker than open ground |

GI options with defaults:

- `albedo`: terrain material → texture mean colour, merged over built-in approximations (sand, snow, grass, rock, asphalt and more), then multiplied by `Terrain:GetMaterialColor`. The built-in means are estimates. With custom MaterialVariants, measure each colour map's mean offline and pass it here.
- `ForgeGUIAlbedo`: a Color3 attribute on a part or any ancestor gives its albedo. A generated mesh needs one, because a SurfaceAppearance texture cannot be read at run time. Without it the mesh uses `fallbackAlbedo` (default 150, 140, 125). A plain part uses its `Color`.
- `referenceAlbedo`: the ground your base `ColorShift_Bottom` was tuned over (default neutral 150, 140, 125). Ground brighter than this raises the bounce, up to 1.6x; darker ground lowers it, down to 0.35x.
- `bounceLevel` (0.3): the bounce brightness used when the place leaves `ColorShift_Bottom` black, which is the Roblox default.
- `getSunColour`: defaults to `Lighting.ColorShift_Top`.
- `getBase`: pass it when a day/night cycle writes the ambients every frame (see Ownership).

## How it works, and the facts behind it

- **Ground bounce.** Rays over the lower hemisphere around the camera focus find the ground and nearby walls. Each hit contributes albedo × (sun if it reaches the point, plus sky). The average sets `Lighting.ColorShift_Bottom`, at the base value's brightness scaled by how bright the ground is. Shaded sides go warm over sand, cool white over snow and green over grass.
- **Sky openness → covered passages.** Rays over the upper hemisphere measure how much sky is open. `OutdoorAmbient` scales from 45 % (fully covered) to 100 %, and `Ambient` leans toward the bounce colour under cover. Measured: Roblox's own sky light hardly dims inside a narrow roofed passage, and adding hidden occluding geometry changed nothing. The probe only darkens while the camera is inside. `PassageShade` is what makes a passage read darker from the street. Recorded with its defaults on a 30-stud gatehouse at noon, the roofed floor went from 51 % to 58 % darker than open ground. That is slightly past the 40–55 % target, so lower `strength` when the passage is already in sun shadow.
- **Colour bleed.** A grid of rays is traced from the sun onto the area around the camera. Each sunlit hit that has a receiver within 14 studs becomes a hemisphere SpotLight (170°, 16-stud range, unshadowed) in the surface's colour. Cells snap to a world grid so the lights do not swim as the camera moves, and they ease in and out.
- **Lights are cheap numbers.** Measured in Studio, 128 unshadowed SpotLights cost no measurable frame time, and 16 shadowed PointLights cost ≤ 0.5 ms a frame. That is why GI can spend 64 lights on High, and why FireLight rations *shadows* rather than lights.
- **Grading goes in the lights, not in stacked grades.** Several `ColorCorrectionEffect`s do not chain: Roblox adds their contrast, saturation and brightness and multiplies their tints, so the whole grade is effectively one CC. Put split toning in the ambients (shadow tone) and `ColorShift_Top` (highlight tone). GI keeps whatever shadow tone the base ambients carry.
- **Frame time, full stack on High** (GI, contact shadows, fires, water and the rest of the source build's effects): about 6 ms median in an open yard with around 60 ground patches, and about 11 ms median in a dense town. The auto-quality thresholds that worked were 18 ms for High and 26 ms for Medium.

## Tried and retired (do not rebuild)

- **Planar-mirror water.** The build tried a ViewportFrame of copied scenery laid on the pond as a mirror, then retired it. Side by side with native terrain water (`Terrain.WaterReflectance`), the native reflection put every pillar in the right place with natural ripples. The mirror added a hard edge along the far bank, dropped some reflections and cost frame time. The cost is structural: moving any part inside a ViewportFrame re-prepares every mesh in it, and one part moved per frame beside about 150 heavy meshes cost 250 ms a frame. Also measured: a SurfaceGui under a Workspace part did not draw its ViewportFrame at all. Such a SurfaceGui has to sit in PlayerGui with `Adornee` set.
- **Water reflectance above 0.5.** Stronger reflectance turns nearby trunks and pillars into mirror images across half a pond at grazing angles.
- **Painted smoke sprites for fire.** A generated smoke sprite with dark outlines reads as a cartoon cloud up close. The engine's soft `smoke_main.dds` reads as smoke, so it is the default. Supply `textures.ember` only for a streak texture: it is drawn `VelocityParallel`.
- **Hidden geometry to darken a passage.** It changed nothing measurable. Use PassageShade.

## Ownership and restore

The conventions are the same as in `LightingPresets.luau`. Only attribute-tagged instances are ever destroyed, never matched by name, and borrowed properties are recorded as `ForgeGUIPrior_<Property>` on the instance they belong to.

| Module | Creates (ownership attribute) | Borrows (prior recorded) |
| --- | --- | --- |
| GlobalIllumination | Attachments + SpotLights under `Workspace.Terrain` (`ForgeGUIGlobalIllumination`) | `Lighting.Ambient`, `OutdoorAmbient`, `ColorShift_Bottom` |
| ContactShadows | one Folder in Workspace (`ForgeGUIContactShadows`) holding the blob parts | nothing |
| FireLight | holder Attachments, emitters, lights for fires that had none (`ForgeGUIFireLight`) | an existing PointLight's `Brightness`/`Range`/`Shadows`; a ParticleRecipes `embers` smoke emitter's `Enabled` |
| WaterReflections | nothing | `Terrain.WaterReflectance` |
| PassageShade | panel Parts inside the model (`ForgeGUIPassageShade`) | nothing |

GI and LightingPresets share Lighting:

- GI writes a prior only when none exists yet, so whichever module touches Lighting first keeps the true original.
- While a preset is applied (`Lighting.ForgeGUIPreset` is set), GI leaves its priors in place on stop, because the preset's `clear()` still needs them.
- GI treats any outside write to the three ambients as the new base, so `LightingPresets.apply` or a day cycle that writes occasionally just works.
- A day cycle that writes every frame should pass `getBase` and stop writing those three properties. Otherwise the two fight and the bounce flickers.

## FireLight and ParticleRecipes

`ParticleRecipes`' `embers` recipe is the always-on, server-replicated part of a fire: embers and dark smoke next to a PointLight. It is how the fire looks from far away or with FireLight off. FireLight is the client-side close-up layered on top:

- While a fire is one of the nearest, FireLight switches the recipe's `smoke` emitter off and runs a lighter, wind-leaning plume instead.
- It adds brighter embers.
- It flickers the light with layered noise and occasional gutters, never a clean sine.

When the fire leaves range, everything goes back. Smoke and embers lean with `workspace.GlobalWind` (`WindAffectsDrag`). Keep GlobalWind in step with your own wind so every fire leans the same way as the grass. `getGust` (0–1) raises the draught, which lifts both the flicker and the ember rate.

## Performance cost

- **GI.** The probe casts 44 rays every 0.25 s, plus up to 28 sun-visibility rays. The colour-bleed sweep casts one ray per cell plus up to four receiver rays: at most 240 rays a frame on High and 120 on Low. Ambients are written 10 times a second, and a light is only written when its brightness moves by more than 0.004.
- **ContactShadows.** The static set is re-picked twice a second from a reused pool. Characters get one downward ray each per frame.
- **FireLight.** Zero work when no fire is in range. Otherwise each active fire costs one noise flicker and two rate writes a frame.
- **WaterReflections and PassageShade.** Nothing per frame.

## Verification recipe

1. Run the regression in an owned test place. Bundle the five modules ahead of `docs/evidence/light-transport-regression.luau` as its header shows, paste the result into `execute_luau`, and expect `PASS … checks passed`. It checks ownership, restore and idempotence for every module, and puts back everything it touched.
2. In Play, on the client:
   - **Captures.** Take `screen_capture` of the same shaded wall with GI at 0 and at 1, both over light ground (sand, snow) and over dark ground (grass, asphalt). The shaded side should take the ground's hue. Read `GI.stats()` from a LocalScript and check that `bounce` matches the ground and `lights` > 0 near sunlit walls.
   - **Stats reach.** `require` from `execute_luau` returns a fresh module, not the running one, so read the stats through the live game (a debug RemoteFunction or the in-game UI), or inspect `Workspace.Terrain` for `ForgeGUIGlobalIllumination` attachments.
   - **Passages.** Stand one capture inside a PassageShade'd passage and one on open ground at noon. The covered floor should read 40–55 % darker.
   - **Fires.** Take a night capture near 3+ fires with `setShadowLevel(1)`: walls should show moving shadows. `Fire.stats().shadowed` must not exceed the budget.
   - **Contact shadows.** Every building and prop should sit in a soft dark footprint, and characters keep a blob that fades as they jump.
3. Measure frame time with the full stack on High, in your densest area and in an open one, and compare against the 18 ms / 26 ms auto-quality thresholds above.
