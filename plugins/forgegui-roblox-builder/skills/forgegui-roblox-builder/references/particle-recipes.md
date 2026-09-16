# Particle and VFX recipes

Seven declarative recipes built by one reviewed constructor in `luau/ParticleRecipes.luau`. No downloaded scripts, no executable asset descendants; the module creates only `Attachment` and `ParticleEmitter` instances and tags them with the `ForgeGUIRecipe` attribute.

| Recipe | Kind | Attach to | Fire with |
| --- | --- | --- | --- |
| `hit_impact` | burst | the struck part or an attachment at the contact point | `burst(holder)` or `burstAt("hit_impact", pos)` |
| `muzzle_flash` | burst | barrel-tip attachment, +Z forward | `burst(holder)` |
| `pickup_sparkle` | loop | the collectible's part | — (loops until destroyed) |
| `ambient_dust` | loop | a large invisible part spanning the room | — |
| `embers` | loop | the fire/forge part, with a `PointLight` beside it | — |
| `footstep_puff` | burst | — | `burstAt("footstep_puff", footPosition, 1)` |
| `portal_aura` | loop | the portal or shrine part | — |

## Using it

Persistent module: create `ReplicatedStorage.ParticleRecipes` with the file contents, then from a server or client script:

```lua
local FX = require(game:GetService("ReplicatedStorage").ParticleRecipes)

-- looping effect owned by the object
FX.attach("pickup_sparkle", workspace.Coins.Coin1)

-- burst effect prepared once, fired many times
local flash = FX.attach("muzzle_flash", tool.Handle.MuzzleAttachment)
FX.burst(flash)

-- transient burst at a position, auto-cleaned after 1 s
FX.burstAt("footstep_puff", humanoidRootPart.Position - Vector3.new(0, 3, 0), 1)
```

One-off through `execute_luau`: paste the module body, replace the final `return M` with the calls above.

Overrides: `FX.attach("embers", part, { texture = "rbxassetid://<published sprite>", rate = 6 })` applies to every emitter in the recipe; `{ emitters = { smoke = { rate = 2 } } }` targets one emitter. Rates are clamped to the recipe's `maxRate`.

## Cleanup rules

- Looping emitters live under an `Attachment` on the owning part. Destroying the part destroys the effect. Never parent an emitter to `workspace` or a folder that outlives the object.
- Transient bursts go under `workspace.Terrain` and are removed by `Debris` after their lifetime. Do not use `wait`-and-destroy loops.
- `detach(target)` removes only what this module created under `target`.
- Verify in a playtest that no `FX_*` attachments remain after the triggering object is destroyed (`search_game_tree` for `FX_`).

## Textures

Defaults use engine-bundled textures (`sparkles_main`, `smoke_main`, `fire_main`) so every recipe works with no upload. For a distinctive look, generate a sprite with ForgeGUI `generation_image` (transparent background, single centered shape, or a 4×4 flipbook grid), publish it to a Roblox image id through a verified route, and pass it as `texture`. Flipbooks additionally need `FlipbookLayout`, `FlipbookMode` and `FlipbookFramerate` set on the emitter; add them through `overrides` once the sheet exists.

## Performance caps

Keep total live particles in view under a few thousand. Rules of thumb: looping recipes 4–20 particles/s each, at most one `ambient_dust` per room, bursts under 20 particles. `LightEmission = 1` with `LightInfluence = 0` reads bright in `night_neon` and `dungeon_torchlit` without adding lights.

## Verify

`attach`, then `screen_capture` from a close camera; for bursts, run `burst` inside a playtest and capture within the same second. Confirm the emitter count with `inspect_instance` on the holder. Report the recipe name, the holder path, and the capture.
