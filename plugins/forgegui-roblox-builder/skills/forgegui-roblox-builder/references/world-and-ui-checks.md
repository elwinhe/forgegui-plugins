# World and UI checks

Some faults look fine in every screenshot and still reach a play-tester. Two of them did, after a
visual pass that looked finished:

- **A player spawned inside the ground.** The Baseplate template's `SpawnLocation` was still at the
  origin, and a terrain island had been built over it. Roblox picks among enabled spawns at random,
  so it happened only sometimes, and a screenshot cannot show a buried pad.
- **The shop and settings closed on any click that missed a button**, and icons sat in borders
  they did not need: a stroked card inside a framed panel, an icon on a framed plate.

`luau/WorldCheck.luau` and `luau/UiCheck.luau` catch these from the place itself. Run them after
any visual pass and before you report it. Their findings go in the report next to the captures.
For the full UI procedure and its gates, see `ui-pass.md`.

## What each check reports

A finding is either an `error`, which means the pass is not done, or a `warning`, which you fix or
explain in the report.

| Check | Severity | Meaning |
| --- | --- | --- |
| `spawn_buried` | error | Something solid sits over an enabled spawn's top, within `coverHeight` (60 studs) above it |
| `spawn_clearance` | error | A collidable part or solid terrain fills the 4x6x4 stud space a character needs above the spawn |
| `spawn_small` | warning | The spawn's top is under 4 studs on a side. Roblox then puts every player on its centre |
| `multiple_spawns` | warning | The neutral pool or a team pool has more than one enabled spawn. Roblox picks one at random, so every one must be valid |
| `floor_covered` | error | Terrain or a prop covers a walkable floor you listed |
| `interactive_covered` | error | Something covers a pad, pickup or prompt part you listed. Models are checked by their bounding box |
| `art_background` | error | Generated art has a visible Roblox background behind it |
| `art_stroke` | error | A `UIStroke` draws a rectangle around art that already has its own rim |
| `bordered_icon` | error | An icon sits in a small chip that has a stroke or fill |
| `icon_on_plate` | error | An icon is laid on other framed art (a plate), so it is framed twice |
| `stroke_in_framed_art` | error | A stroked container or label sits inside art that already frames it |
| `text_overflow` | warning | Visible text does not fit its box |
| `modal_closes_on_stray_click` | error | Source connects a click or input signal on a backdrop, scrim, overlay or dimmer |
| `unregistered_image` | error | An image element shows an asset that is not in the art registry, so its provenance cannot be shown |
| `primitive_surface` | warning | A container or label draws its own Roblox fill or border where generated art was expected. Mark deliberate chrome `AllowPrimitive = true` |
| `provenance_no_registry` | warning | `UiCheck.provenance` ran without a registry, so its percentage is not evidence |

When something is meant to be that way, mark it on the instance instead of ignoring the finding:

- `AllowCovered = true` on a spawn with a roof over it. `spawn_clearance` still applies.
- `MultipleSpawnsIntended = true` on a spawn in a pool that is supposed to have several.
- `UiCheckIgnore = true` on UI chrome that is meant to be there.
- `AllowPrimitive = true` on a frame or label that is meant to draw its own fill or border, such as a
  progress bar, a glass pill or a divider. It silences `primitive_surface` and still counts toward
  the primitive tally, so the ratio stays honest.

## When to run them

- **`WorldCheck.run`**: after anything reshapes or redecorates the world, such as terrain, props,
  trees, replaced geometry or moved spawns. Run it after each layer of a pass, not only at the end.
  Use Edit mode, or the server during play. Characters are ignored, so a player standing on a spawn
  does not block it. Pass `floors` (walkable parts that terrain or props must not cover) and
  `interactives` (pads, pickups and prompt parts the scripts use), or those checks have nothing to
  check.
- **`UiCheck.audit`**: after you build or restyle a screen. Run it in play on the Client, with every
  modal you are checking open. It reads rendered sizes, and it treats art as framing only when that
  art is visible.
- **`UiCheck.provenance`**: after a screen is built, in play on the Client, passing the place's art
  registry module. It reports where each visible surface came from and what share of them is
  generated art. Without a registry every image counts as art and the number means nothing, which is
  why running it bare emits `provenance_no_registry`.
- **`UiCheck.lintSource`**: in Edit, over every client script, before and after a UI change.
- **`UiCheck.strayClickPoints`**: in play, for each transactional modal. It returns points inside
  the panel that are not over a button, plus points on the screen around the panel. Click each
  point, then confirm the modal is still open and nothing underneath it fired. Then click the close
  button and confirm the modal closes.

**The fidelity pass runs these too.** A fidelity pass changes terrain, props, materials, lighting or
VFX. Run `WorldCheck` after each of those layers and again before reporting, with `floors` set to the
walkable floor parts and `interactives` set to the pads, pickups and prompt parts. The pass is done
when:

- there is no `spawn_buried`, `spawn_clearance`, `spawn_small`, `floor_covered` or
  `interactive_covered` finding;
- `multiple_spawns` appears only where the design calls for a pool and the spawns carry
  `MultipleSpawnsIntended`;
- a respawn test passes. Respawn at least max(5, 3 × enabled spawns) times, and check each time that
  the root part is above a spawn top, not in terrain, and not still falling after 3 s.

## Running them through `execute_luau`

`execute_luau` runs in a sandbox that cannot `require` place modules. So you paste the module,
followed by a runner that takes the place of its final `return`:

```sh
python references/tools/paste_module.py references/luau/WorldCheck.luau runner.luau > paste.luau
```

The tool drops the module's `--!strict` line and its final `return WorldCheck`, then appends the
runner, so the runner can use the module's table by name. Send the contents of `paste.luau` as the
`execute_luau` code. Paste into Edit for the world. For the UI, paste into the Client datamodel
during play. `lintSource` is the exception: run it in Edit.

A world runner. Replace the paths with the place's own:

```lua
local floors, interactives = {}, {}
for _, island in ipairs(workspace.Map.Islands:GetChildren()) do
	table.insert(floors, island.PrimaryPart)
end
for _, pad in ipairs(workspace.Map.LaunchPads:GetChildren()) do
	table.insert(interactives, pad) -- a model is checked by its bounding box
end
return WorldCheck.format(WorldCheck.run({ floors = floors, interactives = interactives }))
```

UI runners, each sent in its own call. Structure, in play on the Client, with the modals open:

```lua
return UiCheck.format(UiCheck.audit(game.Players.LocalPlayer.PlayerGui.MainHUD))
```

Provenance, in the same call shape. The sandbox cannot `require` the place's registry module, so
hand the ids over directly — `provenance` takes the GuiArt registry table, a map of name to id, or a
plain list, and reads `rbxassetid://123`, a bare `123` and an asset URL as the same upload:

```lua
local ids = { "rbxassetid://18273645", "rbxassetid://18273699" } -- from ArtRegistry
return UiCheck.format(UiCheck.provenance(game.Players.LocalPlayer.PlayerGui.MainHUD, ids))
```

In Edit, where script sources are readable, scrape them instead of pasting a list that can drift:

```lua
local ids = {}
for id in string.gmatch(game.ReplicatedStorage.Game.ArtRegistry.Source, "rbxassetid://(%d+)") do
	table.insert(ids, id)
end
return UiCheck.format(UiCheck.provenance(game.StarterGui, ids))
```

Wiring, in Edit:

```lua
local reports = {}
for _, script in ipairs(game.StarterPlayer:GetDescendants()) do
	if script:IsA("LuaSourceContainer") then
		table.insert(reports, UiCheck.lintSource(script.Source, script:GetFullName()))
	end
end
return UiCheck.format(UiCheck.merge(reports))
```

Stray-click points, in play:

```lua
local hud = game.Players.LocalPlayer.PlayerGui.MainHUD
local out = {}
for _, point in ipairs(UiCheck.strayClickPoints(hud.Shop.Panel, hud.AbsoluteSize)) do
	table.insert(out, ("%d,%d %s"):format(point.position.X, point.position.Y, point.label))
end
return table.concat(out, "\n")
```

The world options are `clearance` (the space above a spawn, default 4x6x4), `tolerance` (how far
above a top a surface may sit, default 0.5), and `coverHeight` (how high to look for cover, default
60 studs). With `coverHeight` at 60, an island floating far overhead counts as sky, not as a roof.

## Reading the report

`format` puts the totals on the first line, then writes one line per finding:
`[severity] check subject: detail`. The subject is the instance's full name, or `script:line` for a
lint finding. `WorldCheck` also prints how many objects each check covered. This was the first run
after a pass that rebuilt floating islands in terrain. Paths are renamed and details shortened:

```
WorldCheck: 4 error(s), 1 warning(s)
checked floor_covered=7 interactive_covered=32 spawns=2
[warning] multiple_spawns neutral: 2 enabled spawns (Workspace.SpawnLocation, Workspace.Map.Spawn) ...
[error] spawn_buried Workspace.SpawnLocation: Workspace.Map.Islands.Hub.Top surface is 20.5 studs above the spawn top (1.0) ...
[error] interactive_covered Workspace.Map.LaunchPads.Pad_Isle2_to_Isle3: Workspace.Map.Decor.Tree.Canopy covers it ...
[error] interactive_covered Workspace.Map.LaunchPads.Pad_Isle4_to_Isle5: ... Canopy covers it ...
[error] interactive_covered Workspace.Map.Crystals.Crystal: ... Canopy covers it ...
```

- Compare the `checked` counts with what you meant to check. `floor_covered=0` means the runner
  listed no floors. It does not mean the floors passed.
- Fix each error, then run the check again in a **separate** call. A raycast in the same
  `execute_luau` call as a terrain write still sees the old terrain.
- Report the final output as it came back. Explain each remaining warning, and each instance you
  marked with an opt-out attribute.

The buried spawn was the bug the play-tester reported. Nobody had noticed the other three. Two trees
stood about a stud from launch pads, with their collidable canopies hanging over the pads, and one
canopy hid a crystal. The fix was to remove the template spawn and move the two trees to open
ground. The next run showed `0 error(s), 0 warning(s)` with `spawns=1`.

## Known false positives and blind spots

- **The floor and interactive checks cast one ray, straight down at the centre.** If a gate, arch or
  statue stands at the centre of a floor by design, the floor reports `floor_covered`. Terrain grown
  over the floor's edge is missed. For a large floor, drop it from `floors` and sweep a grid in the
  runner instead, with an allow-list of what is there on purpose:

  ```lua
  -- floors: Block parts lying flat. ALLOWED: full names (or name prefixes, for a model) of
  -- things built on a floor by design.
  local ALLOWED = { "Workspace.Map.Hub.Gate" }
  local STEPS, HEIGHT, TOLERANCE = 6, 60, 0.5
  local adapter = WorldCheck.robloxAdapter()
  local function allowed(name: string): boolean
  	for _, prefix in ipairs(ALLOWED) do
  		if string.sub(name, 1, #prefix) == prefix then
  			return true
  		end
  	end
  	return false
  end
  local found = {}
  for _, floor in ipairs(floors) do
  	local top = floor.Position.Y + floor.Size.Y / 2
  	for i = 1, STEPS do
  		for j = 1, STEPS do
  			local offset = Vector3.new(floor.Size.X * ((i - 0.5) / STEPS - 0.5), 0, floor.Size.Z * ((j - 0.5) / STEPS - 0.5))
  			local point = floor.CFrame:PointToWorldSpace(offset)
  			local hit = adapter.raycast(Vector3.new(point.X, top + HEIGHT, point.Z), Vector3.new(0, -HEIGHT, 0), { floor })
  			if hit and hit.position.Y > top + TOLERANCE and not allowed(hit.name) then
  				table.insert(found, ("%s at %d,%d: %s is %.1f above the top"):format(floor:GetFullName(), i, j, hit.name, hit.position.Y - top))
  			end
  		end
  	end
  end
  return if #found == 0 then "floor sweep: clear" else table.concat(found, "\n")
  ```

- **`AllowCovered` works only on spawns.** A pad that sits under a roof by design stays out of
  `interactives`. Say so in the report.
- **Only collidable parts and solid terrain count.** Community reports say that a non-collidable
  part over a spawn can still push the character up onto it. Treat any part over a spawn as
  suspect.
- **`lintSource` matches names, line by line.** It flags `<name>.<signal>:Connect` when the name
  contains Backdrop, Scrim, Overlay or Dimmer and the signal is a click or input signal. A backdrop
  stored under another name, or wired up through a helper, gets past it. The stray-click test in
  play is the real proof. A variable for a genuine button whose name includes "Overlay" is flagged
  too. Rename it or explain it.
- **`audit` flags any stroked `Frame`, `ScrollingFrame`, `CanvasGroup` or `TextLabel` inside framed
  art.** Buttons are skipped, so a switch track built as a `TextButton` keeps its outline. A track
  built as a stroked `Frame` is flagged. Build controls as buttons, or set `UiCheckIgnore` on
  deliberate chrome such as a badge that is meant to have a chip.
- **Stray-click coordinates.** The points are in `AbsolutePosition` space. The module's comment
  says to add the GUI inset when the ScreenGui does not ignore it. In the tested workflow, though,
  `user_mouse_input` took `AbsolutePosition` coordinates directly, so the points could be clicked as
  returned. Click one known button first to confirm which case you are in.
- **What Studio cannot test.** Studio's virtual input refuses gamepad `ButtonB`. To verify B, read
  the input handler instead, and say that in the report. `GuiObject.Active` does not reliably stop
  clicks reaching UI underneath, and `InputSink` is documented but not enabled. What stops the
  clicks is a full-screen `GuiButton` backdrop, so test it.

## Seeing the UI: what can and cannot be captured

`screen_capture` photographs the Studio viewport at edit time. Three facts, each learned the hard
way:

- **A `ScreenGui` under `StarterGui` IS captured** in Edit mode, composited over the 3D view exactly
  as a player would see it. Mount the real screen modules into a throwaway `StarterGui.DevPreview`
  and capture that. It is the same class the game ships, so colours, `ViewportFrame`s, `CanvasGroup`
  fades and letterboxing are all real.
- **A Play-mode capture comes back black**, and a `ScreenGui` in a player's `PlayerGui` is not
  reachable from Edit. Verify Play-mode UI by reading properties (`Visible`, `AbsolutePosition`,
  `IsLoaded`, text) and by running `UiCheck` inside the running client.
- **Do not mirror the UI onto a `SurfaceGui`** to look at it. An earlier version of this workflow
  did, believing a ScreenGui could not be captured. The mirror is lossy in ways that hide real
  defects: world `ColorCorrection`, `Atmosphere` and `Bloom` tint it, and a SurfaceGui does not draw
  `ViewportFrame`s at all, so a 3D weapon preview showed as an empty panel. A mirror also scales to
  fit its part, which hid every letterboxing bug below.

**Studio only steps tweens and finishes image loads while its viewport is actually drawing.** With
the display asleep or the window covered, `screen_capture` hangs for minutes, `PreloadAsync` never
returns, and every screen sits at `GroupTransparency = 1` with the previous screen still on top of
it, so a layout check reports phantom overlaps between two screens. Keep the display awake
(`caffeinate -d -u` on macOS), and run layout checks with the UI's reduced-motion path on, which
applies every tween goal at once and needs no frames. The same stall is a robustness lesson for the
game itself: never make a screen's removal depend on its exit tween completing.

Delete the preview gui before saving or publishing. Because it lives in `StarterGui` it would
otherwise ship to every player.

## Blurry UI: do not build pages out of CanvasGroups

A `CanvasGroup` is drawn to an off-screen texture and then composited, and Roblox sizes that
texture by the client's graphics quality. At anything below the top setting, every label and
hairline inside it is visibly soft. Using one as a screen root (so the whole page can fade through
`GroupTransparency`) makes the ENTIRE interface blurry, and nothing reports it: layout, palette and
provenance checks all pass, and a 1080p Studio capture at maximum quality looks fine. The user's
report was simply "the UI is super blurry".

- Screen roots, cards and bleed layers are plain `Frame`s. Use `ClipsDescendants` plus a `UICorner`
  on the image itself where a rounded card was the reason for the CanvasGroup.
- Replace the group fade with a **curtain**: a host-sized sheet in the ground colour that snaps
  opaque and fades off the new screen (the dip-to-black every console shooter uses). Give it a
  `task.delay` fallback that clears it, because tweens do not step when the client is not drawing.
- A checker rule worth having: flag any `CanvasGroup` that contains a `TextLabel`.

## The lighting is not ready on the frame after a camera jump

`screen_capture` with `camera_position` moves the camera and photographs the next frame. Local
lights (SpotLight, PointLight) had not been evaluated for that region yet: a set lit by three
spotlights captured pitch black, and adding more lights changed nothing. Park the Studio camera at
the shot first (`CurrentCamera.CFrame = ...`, wait two or three seconds), then capture without
moving it. Judging a lighting setup from a jump-capture will send you chasing a bug that is not
there.

## Fixed-stage layouts: four bugs that pass every per-screen check

Laying screens out on a fixed 1920x1080 stage and scaling it to fit the window is a sound way to get
consistent composition. It has four characteristic failures. None is visible at exactly 16:9, which
is where screens are usually designed and reviewed, so **capture at a second aspect (4:3 or a
phone) before calling any screen done.**

1. **The world shows through the letterbox.** Behind a ScreenGui the bars are not black, they are
   the live game. A full-screen menu needs a host-sized layer behind the stage, and the screen's
   backdrop and scrims belong in that layer (where "edge" means the edge of the window), not inside
   the stage. A flat-colour fill still reads as bars when it does not match the art between them.
2. **HUDs and overlays must not be letterboxed.** A HUD is furniture on the glass: ammo belongs in
   the corner of the window, and a modal's dim must reach the window's edges. Give them the same
   scale but let the stage grow to cover the host, so edge-anchored children land on real edges.
   The checker then has to judge those stages against their own size, not against 1920x1080, or it
   reports the ammo counter as off-screen.
3. **An entrance tween can throw the centring away.** `fitToHost` centred the stage; one line later
   the present animation tweened `Position` to (0, 0). On every window that was not 16:9 the whole
   interface sat in the top-left. Animate from and to the fitted position.
4. **Scaling 9-slice art: multiply, never overwrite.** Slice borders draw at native texture size, so
   the stage scale must be applied to `SliceScale`. Writing it over the image's own value discards
   the radius-matched scale each button asked for. At 1080p that put 106 px of fixed border into an
   84 px button, which drew with its lower edge crushed. Store the base value once and set
   `base * stageScale`.

Two checker lessons from the same pass:

- **Overlap checks must respect layers.** A modal is supposed to cover the screen that opened it.
  Compare elements only within one screen, or between two ordinary screens, never across an overlay
  boundary; otherwise every modal reports the title underneath as "printed over" its own heading.
- **Nothing reports dead motion code.** A staggered menu entrance was written, reviewed and never
  called; the screen simply appeared and every check passed. When a screen module exports `show` or
  `entrance`, grep for a call site.

## Flow bugs that only show up when someone else presses the buttons

Three from one build, all invisible to per-screen checks and to a developer who always takes the
same path:

- **"It queues me immediately."** The server turned `Players.CharacterAutoLoads` off near the END
  of its bootstrap. Building the map took long enough that a player could finish joining first, get
  a default body, and the client took "I have a body" to mean "I deployed". Turn auto-load off on
  the FIRST line (and save the place with it off), and route the client off an explicit
  server-set attribute, never off `CharacterAdded`.
- **"Changing loadout immediately disappears."** Screens were routed by server phase every second:
  "phase is Live and you are not on the HUD, so go to the HUD". Opening the loadout screen from the
  death screen lasted under a second. Anything the player opens deliberately must be exempt from
  phase routing; here it became a stand-down (body removed, redeploy from the screen).
- **Streaming hides your set.** A menu stage built 400 studs from the map existed on the server and
  not on the client: `StreamingEnabled` was on, parts that far from the player never arrived, and
  the camera looked at an empty spot. Publish positions as attributes on a Folder (folders always
  replicate) and set `Player.ReplicationFocus` to the set while the player is in the menus.

Click through the real flow with `user_mouse_input` and an `instance_path`, as a new player would,
before calling any of it done.

## Self-tests that tell the truth

A Studio-only self-test that drives the live services is worth having, and its failures are harness
bugs at least as often as game bugs. From one project: a check fired during the weapon's 0.45 s
draw time and blamed the raycast; another aimed from a character that a phase change had already
respawned elsewhere; a third waited a fixed 15 s for a loadout that is granted a 20 s intermission
after joining. The rule that fixes all three: **wait for the thing being tested, not for a guess at
how long it takes**, re-acquire anything a respawn can replace, and print `NOT RUN` with the reason
rather than a false pass or a false fail. When AI combatants exist, stand them down for the
duration: a bot shooting the tester corrupts every exact-damage assertion.

## Evidence and hygiene

- After writing a script's `Source` through the MCP, compare its length and a hash with the local
  file before you test it.
- `screen_capture` returns an image to you only. If the capture needs to be kept as evidence, take
  it of Studio's own window, not the whole screen. Cover the player list first, because it shows
  the tester's display name.

## Tests

`lune run references/tests/qa`, run from the skill root, tests both modules headless against stub
worlds and stub GUI trees. Each check is tested against the fault that motivated it.
`python references/tools/test_tools.py` includes checks for `paste_module.py`.
