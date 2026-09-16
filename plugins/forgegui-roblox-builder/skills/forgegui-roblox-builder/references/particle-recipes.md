# Particle and VFX recipes

Seven declarative recipes built by one reviewed constructor in `luau/ParticleRecipes.luau`. No downloaded scripts, no executable asset descendants; the module tags its own instances with `ForgeGUIRecipe` and `ForgeGUIRecipeOwned`. An existing target Attachment is borrowed without changing its attributes.

| Recipe | Kind | Attach to | Fire with |
| --- | --- | --- | --- |
| `hit_impact` | burst | the struck part or an attachment at the contact point | `burst(holder)` or `burstAt("hit_impact", pos)` |
| `muzzle_flash` | burst | barrel-tip attachment, local +Y aimed along the barrel | `burst(holder)` |
| `pickup_sparkle` | loop | the collectible's part | — (loops until destroyed) |
| `ambient_dust` | loop | a part or attachment at the desired emission point | — |
| `embers` | loop | the fire/forge part, with a `PointLight` beside it | — |
| `footstep_puff` | burst | — | `burstAt("footstep_puff", footPosition, 1)` |
| `portal_aura` | loop | the portal or shrine part | — |

## Using it

`burst` and `burstAt` call `ParticleEmitter:Emit()`, which renders only on the machine that calls it. Fire bursts from a LocalScript, sending the position through a RemoteEvent when the server decides the hit; looping recipes attached in Edit mode or on the server replicate normally.

Persistent module: create `ReplicatedStorage.ParticleRecipes` with the file contents, then from a server or client script. Resolve the example's object paths to inspected instances in your place:

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

One-off through `execute_luau`: paste the module body and replace the final `return M` with this code, replacing the target path with a previously inspected BasePart. It uses the module's local `M` directly and does not require a persistent ModuleScript:

```lua
local target = workspace:FindFirstChild("InspectedPickup")
assert(target and target:IsA("BasePart"), "Choose an inspected pickup BasePart")
local holder = M.attach("pickup_sparkle", target)
print(holder:GetFullName())
```

In the two recorded Studio MCP trials, freshly created owned modules initially failed `require` because of capability mismatches. The successful setup used `Sandboxed = true` on those modules and restricted capabilities `Basic`, `CreateInstances`, `AccessOutsideWrite`, `Environment`, `RunServerScript`, and `RunClientScript`; the gladiator setup also included `Physics`. These are recorded configurations, not a universal minimum. Inspect the current capability error and limit changes to the reviewed modules you created. Do not grant `LoadUnownedAsset` merely because it appears in inherited metadata, change unrelated modules, or disable global Studio security. If the session cannot configure the owned module through supported tools, use the one-off route or report the setup blocker.

Overrides: `FX.attach("embers", part, { texture = "rbxassetid://<published sprite>", rate = 6 })` applies to every emitter in the recipe; `{ emitters = { smoke = { rate = 2 } } }` targets one emitter. Rates are clamped to the recipe's `maxRate`.

## Cleanup rules

- Looping emitters live under an `Attachment` on the owning part. Destroying the part destroys the effect. Never parent an emitter to `workspace` or a folder that outlives the object.
- Transient bursts go under `workspace.Terrain` and are removed by `Debris` after their lifetime. Do not use `wait`-and-destroy loops.
- `detach(target)` removes recipe-owned emitters on or under `target`, then empty recipe-owned attachments, including `target` itself when owned. Borrowed attachments and unrelated children are preserved. An owned attachment that has gained unrelated children is retained until empty.
- `burst(holder)` fires only recipe-owned emitters, using each emitter's recipe count unless a count is supplied. Repeated `attach` calls add emitters; detach before replacing a persistent recipe.
- Older instances without the `ForgeGUIRecipeOwned` marker are not adopted or deleted automatically; inspect and remove those legacy effects explicitly if upgrading an existing place.
- Verify in a playtest that no `FX_*` attachments remain after the triggering object is destroyed (`search_game_tree` for `FX_`).

## Textures

Defaults use engine-bundled textures (`sparkles_main`, `smoke_main`, `fire_main`) so no upload is needed. For a distinctive look, generate a sprite with ForgeGUI `generation_image`, publish it to a Roblox image id through a verified route, and pass it as `texture`. The constructor does not support flipbook properties in `overrides`. For a published flipbook sheet, explicitly set `FlipbookLayout`, `FlipbookMode` and `FlipbookFramerate` on the resulting inspected ParticleEmitter and verify the animation in Play.

All recipes emit from an Attachment position. A large owning Part does not turn `ambient_dust` into room-volume emission, and spherical shape settings on an attachment do not establish a volumetric portal. Room-volume effects need a separate reviewed emitter parented directly to a BasePart; verify that effect separately.

## Performance caps

Keep total live particles in view under a few thousand. Rules of thumb: looping recipes 4–20 particles/s each, at most one `ambient_dust` per room, bursts under 20 particles. `LightEmission = 1` with `LightInfluence = 0` reads bright in `night_neon` and `dungeon_torchlit` without adding lights.

## Verify

`attach`, then `screen_capture` from a close camera; for bursts, run `burst` inside a playtest and capture within the same second. Confirm the emitter count with `inspect_instance` on the holder. Report the recipe name, the holder path, and the capture.
