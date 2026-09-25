# Lighting and VFX lab

A look change judged in the live world is judged against whatever happened to be in shot: a different
hour, a different wall, a cloud of dust. The lab is a flat plate far outside the world. It holds the
same reference objects side by side, so a before/after pair of captures differs only by the change
under test. Build it once per place, send admins there, and do every lighting, material, post-effect
and VFX comparison in it before judging the change in the world.

Reviewed code: `luau/LightingLab.luau` (server side: a Script, or `execute_luau` in Edit).

## Building it

```lua
local LightingLab = require(ServerStorage.LightingLab)
local lab, report = LightingLab.build({
	origin = Vector3.new(6000, 0, 0),              -- keep it clear of the world and of streaming targets
	place = function(kind, name, cframe, parent)  -- optional: your game's kit
		local source = ServerStorage.Kit:FindFirstChild(name)
		if not source then
			return nil
		end
		local copy = source:Clone()
		copy:PivotTo(cframe)
		copy.Parent = parent
		return copy
	end,
	props = { "crate_stack", "cart" }, windItems = { "palm", "banner" },
	detailTexture = "rbxassetid://<fine grain>", tilingTexture = "rbxassetid://<tiled brick>",
})
print(table.concat(report.built, ", "), table.concat(report.skipped, "; "), report.terrain)
```

`build()` clears an earlier lab first. `clear()` removes it and pastes back the terrain it replaced.
`find()` returns the lab root found by ownership, and `spawnCFrame(origin)` gives the visitor pose in
front of the welcome sign.

| Station | What it shows | Needs the kit? |
| --- | --- | --- |
| `materials` | balls in plastic (white, grey, black, red, blue), metal, glass and neon, plus one swatch per `MaterialVariant` in MaterialService (up to 16) | no |
| `terrain` | one 20 × 40 stud strip per terrain material: tiling and colour at a glance | no |
| `bounce` | a white wall and a red wall in a sunlit corner under a roof: GI colour bleed | no |
| `passage` | a covered walk-through: interior darkness and contact shadow | optional (`place("passage", "passage", …)`) |
| `pond` | terrain water with red, white and blue pillars on the bank: reflections | no (needs terrain) |
| `fire` | two braziers (`Fire` plus a shadowed `PointLight`) against a wall, plus a kit campfire if given | optional |
| `wind` | primitive trees, a palm, a shrub and a banner tagged `ForgeGUISway`, plus kit items in `windItems` | optional |
| `props` | crates, barrels, a rock and a low wall, plus kit items in `props`: contact shadows | optional |
| `tiling` | the same kit building three ways: A as placed, B with `detailTexture` overlaid, C with `tilingTexture` blended over | yes (skipped without `place`) |

Options: `origin` (default `(6000, 0, 0)`), `half` (plate half-size, default 240, minimum 200),
`groundMaterial` (default `Ground`), `stations` (subset, in order), `place`, `parent` (default Workspace),
`terrainMaterials`, `materialVariants`, `windItems`, `props`, `detailTexture`, `tilingTexture`, `swayTag`.

**The `place` contract.** `place(kind, name, cframe, parent)` is called with the station name, an item
name, the target CFrame and the station model. It returns a fresh copy it placed (or nil to skip). The
lab marks what it returns as its own and removes it on `clear()`, so never return a shared original. An
error inside `place` is caught and listed in `report.skipped`; the rest of the lab still builds.

**Ownership.** Every instance the lab makes, and every model `place` returns, carries
`ForgeGUILightingLab = true` under one root folder that also carries `ForgeGUILightingLabRoot = true`.
Terrain is borrowed. Before filling anything, the lab copies the whole region it will touch into an
owned `TerrainRegion` (`Terrain:CopyRegion`), and `clear()` pastes it back (`PasteRegion`, empty cells
included). A lab built over existing terrain therefore leaves it as found. If the snapshot fails, the
lab uses a part plate instead, skips the terrain-dependent stations, and says so in `report.terrain`.
A stranger's instance inside the root survives `clear()`, and the root is then unclaimed rather than
destroyed.

The wind station's primitives are tagged for `FoliageSway`, so starting the ambient stack
(`ambient-motion.md`) makes the whole station move. The pond is plain terrain water, and its
reflections come from `Terrain.WaterReflectance`, which the lab does not change.

## Admin-only teleport

The lab is a debug tool: only admins may go there, and the **server** decides who is an admin. The
client only asks. The button's visibility is cosmetic; the server checks again on every request, never
reads a destination from the client, and rate-limits requests.

```lua
-- ServerScriptService/LabTeleport (Script)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local LightingLab = require(ServerStorage.LightingLab)

local ADMIN_USER_IDS: { number } = {} -- fill in your team's user ids; keep them server-side
local LAB_ORIGIN = Vector3.new(6000, 0, 0)
local LAB_RADIUS = 400 -- inside this, the button takes you home instead
local HOME = CFrame.new(0, 5, 0) -- your normal spawn
local COOLDOWN = 2
local lastUse: { [Player]: number } = {}

local function isAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if table.find(ADMIN_USER_IDS, player.UserId) then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

local remote = Instance.new("RemoteEvent")
remote.Name = "LabTeleport"
remote.Parent = ReplicatedStorage

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("IsAdmin", isAdmin(player)) -- for showing the button only
end)
Players.PlayerRemoving:Connect(function(player)
	lastUse[player] = nil
end)

remote.OnServerEvent:Connect(function(player: Player) -- every client argument is ignored
	if not isAdmin(player) then
		return
	end
	local now = os.clock()
	if lastUse[player] and now - lastUse[player] < COOLDOWN then
		return
	end
	lastUse[player] = now
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and root and root:IsA("BasePart")) then
		return
	end
	if not LightingLab.find() then
		LightingLab.build({ origin = LAB_ORIGIN }) -- or build at server start behind a flag
	end
	local offset = Vector2.new(root.Position.X - LAB_ORIGIN.X, root.Position.Z - LAB_ORIGIN.Z)
	local target = if offset.Magnitude < LAB_RADIUS then HOME else LightingLab.spawnCFrame(LAB_ORIGIN)
	pcall(player.RequestStreamAroundAsync, player, target.Position) -- StreamingEnabled: load the far end first
	character:PivotTo(target)
end)
```

On the client, show a "DEBUG MAP" button (the pause menu is a good home) only while
`player:GetAttribute("IsAdmin") == true`, and have it call `ReplicatedStorage.LabTeleport:FireServer()`
with no arguments. A chat command or a key works the same way: it asks, and the server decides.
Building the lab's terrain takes a moment, so in a live server build it at startup (for example only in
Studio or on private servers) rather than on the first click.

## Capture recipe: before/after in identical light

Studio's `screen_capture` lands 3–5 s after the call, and Studio redraws only while its window is in
front. A free camera will have moved by the time the capture lands. Pin the camera, hide the HUD, and
change one thing between two captures.

1. Play, teleport to the lab, and in a **Client** `execute_luau` pin the camera after every other camera
   script. The default camera runs at `RenderPriority.Camera`, and a cinematic director usually at
   `Camera + 1`, so bind at `Camera + 5`. Drive the pose from Workspace attributes so later calls can
   move it:

   ```lua
   local RunService = game:GetService("RunService")
   local camera = workspace.CurrentCamera
   local lab = Vector3.new(6000, 0, 0)
   workspace:SetAttribute("CaptureShot", CFrame.lookAt(lab + Vector3.new(-62, 7, 24), lab + Vector3.new(-84, 6, 44)))
   RunService:BindToRenderStep("ForgeGUICapturePin", Enum.RenderPriority.Camera.Value + 5, function()
   	local shot = workspace:GetAttribute("CaptureShot")
   	if typeof(shot) == "CFrame" then
   		camera.CameraType = Enum.CameraType.Scriptable
   		camera.CFrame = shot
   	end
   end)
   ```

   If the game's own camera binds later than `Camera + 5`, bind above it (`RenderPriority.Last + 50` also
   worked).
2. Hide the HUD. Disable every enabled ScreenGui in `PlayerGui`, recording each one as
   `ForgeGUIPrior_Enabled` so it can be put back. `CameraPath.hideGuis(true)` does exactly this. Also
   call `StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)`.
3. Freeze what would otherwise differ between shots: pin `Lighting.ClockTime` (record the prior), turn
   off a running storm, and `WindVfx.stop()` if the change is not about wind. Random ribbons make two
   captures differ for no reason.
4. Capture A with `screen_capture` (no camera arguments). Make the one change (apply a lighting preset,
   swap a MaterialVariant, toggle a post effect). Wait a second, then capture B. Capture each state twice
   and keep the second, so a capture that caught a frame mid-change is not the one you judge.
5. Unpin: `RunService:UnbindFromRenderStep("ForgeGUICapturePin")`, set `CameraType` back to `Custom`,
   `CameraPath.hideGuis(false)`, re-enable the CoreGui, and restore `ClockTime`.

Keep both captures with the change described in one line. Captures can include the Roblox player list
and display names: check each image before committing it.

## Measured facts worth re-checking in the lab

These were measured in Studio on the build this lab came from (2026-09-22/23). The lab stations are
where to confirm them again when a Roblox update might have changed them:

- **ColorCorrectionEffect works in display space**, in the order contrast → saturation → brightness →
  tint, and clamps only at the end: `(x − 0.5)(1 + C) + 0.5`, then a luma mix with W = (0.34, 0.548,
  0.112), then `+ B`, then `× tint`. Check it on the materials station's grey and white balls.
- **Several ColorCorrectionEffects do not chain.** Roblox adds their C, S and B and multiplies their
  tints, so the whole grade is effectively one CC. Split toning has to go into the lights instead:
  ambients carry the shadow tone and the sun's `ColorShift_Top` carries the highlight tone. The bounce
  station shows it.
- **ExposureCompensation acts before a filmic tone curve**: linear 0.1 → display 0.32, 0.5 → 0.73,
  1.0 → 0.9, and ≥ 3 → 1.0.
- **No velocity buffer and no LUT support.** Motion blur has to be built on `DepthOfFieldEffect`. For an
  orbiting camera, screen speed ∝ |1 − f/d|, which is the shape of a depth of field focused on the pivot.
- **ViewportFrames are expensive to animate.** Moving any part inside a ViewportFrame re-prepares every
  mesh in it: one part moved per frame beside about 150 heavy meshes cost 250 ms per frame. Planar-mirror
  water reflections built on a ViewportFrame were retired for that reason. Native terrain water
  (`Terrain.WaterReflectance`) put every reflection in the right place with ripples, while the mirror
  added a hard far-bank edge, dropped reflections and cost frame time. Judge water at the pond station.
- **A SurfaceGui under a Workspace part did not draw its ViewportFrame.** Put the SurfaceGui in
  `PlayerGui` with `Adornee` set to the part. Text-only SurfaceGuis, like the lab's signs, draw fine in
  Workspace.
- **Lights are cheap.** 128 unshadowed SpotLights cost no measurable time, and 16 shadowed PointLights
  cost ≤ 0.5 ms. The fire station's braziers are shadowed on purpose.
- **Terrain cannot displace a texture.** Close-up ground reads flat whatever the normal map; the terrain
  strip shows it. Real 3D ground patches scattered near the camera fix it. A grid-snapped patch must be
  laid only where its whole footprint (centre and 4 corners) is the same terrain material. On narrow
  strips (roads about 14 studs wide against 12-stud patches) it otherwise straddles the edge and reads
  as loose tiles strewn over the next material.
- **Frame time with the full stack on High**: about 6 ms median in an open yard with about 60 ground
  patches, and about 11 ms in a dense town. The automatic preset chose High below 18 ms median and
  Medium below 26 ms.
- **`require` from `execute_luau` returns fresh module instances, not the running game's.** Verify by
  inspecting live instances or driving the real UI. Calling `LightingLab.build` from a fresh copy is
  fine, because the lab is found by ownership attributes, not by module state.

## Verification

1. Regression (Studio MCP `execute_luau`, Edit mode):
   `python references/tools/paste_module.py references/luau/LightingLab.luau docs/evidence/lighting-lab-regression.luau`,
   then run the output. It builds at a far origin under a scratch folder and checks that every station
   builds, everything is marked, a rebuild replaces the lab, terrain comes back exactly (pre-existing
   rock stays rock, air stays air), and strangers survive. It prints `N checks passed`.
2. After `build()` in your place: `inspect_instance` on the `ForgeGUI_LightingLab` root, read
   `report.skipped`, then capture the welcome sign from `report.spawn`.
3. After `clear()`: the root is gone and the terrain at the origin matches what was there before (read
   one voxel with `Terrain:ReadVoxels`).
4. Teleport: with a non-admin test account (in Studio, temporarily make `isAdmin` return false for it),
   show the button and press it, and confirm nothing happens. Then confirm an admin lands at the lab and
   a second press returns them home.
