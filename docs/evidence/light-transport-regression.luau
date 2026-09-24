-- Light-transport regression: GlobalIllumination, ContactShadows, FireLight,
-- WaterReflections and PassageShade in one run, in an owned test place (Edit mode
-- is fine: every runtime module is driven with `manual = true` and step()).
--
-- execute_luau cannot require place modules, so bundle the five module sources
-- ahead of this runner, each wrapped in a function so their locals stay apart:
--
--   cd plugins/forgegui-roblox-builder/skills/forgegui-roblox-builder
--   { for m in GlobalIllumination ContactShadows FireLight WaterReflections PassageShade; do
--       printf 'local %s = (function()\n' "$m"; tail -n +2 "references/luau/$m.luau"; printf '\nend)()\n'
--     done; cat ../../../../docs/evidence/light-transport-regression.luau; } > /tmp/light-transport-paste.luau
--
-- and pass the file's contents to execute_luau. It prints PASS with the check list
-- or raises FAIL with the first failed check.
--
-- Covers, per module: ownership (only attribute-tagged instances are destroyed; a
-- same-named stranger survives), prior capture and restore, and idempotent
-- start/stop (apply/clear). Everything it builds sits in one scratch folder high
-- above the place, and Lighting / Terrain values it touches are put back whether
-- it passed or failed.
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Terrain = workspace.Terrain
local checks: { string } = {}

local function check(condition: boolean, label: string)
	assert(condition, label)
	table.insert(checks, label)
end

local function near(a: number, b: number, tolerance: number, label: string)
	check(math.abs(a - b) <= tolerance, `{label} (expected {b}, got {a})`)
end

local function sameColour(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 0.01 and math.abs(a.G - b.G) < 0.01 and math.abs(a.B - b.B) < 0.01
end

local function ownedCount(root: Instance, attribute: string): number
	local count = 0
	for _, d in root:GetDescendants() do
		if d:GetAttribute(attribute) == true then
			count += 1
		end
	end
	return count
end

-- What the place had, handed back at the end.
local SAVED_LIGHTING = { "Ambient", "OutdoorAmbient", "ColorShift_Bottom", "ClockTime", "Brightness" }
local saved: { [string]: any } = {}
for _, property in SAVED_LIGHTING do
	saved[property] = (Lighting :: any)[property]
end
local savedReflectance = Terrain.WaterReflectance
local savedAttributes = { [Lighting] = Lighting:GetAttributes(), [Terrain] = Terrain:GetAttributes() }

local ORIGIN = Vector3.new(0, 5000, 0) -- well clear of anything in the place
local scratch = Instance.new("Folder")
scratch.Name = "ForgeGUILightTransportRegression_" .. HttpService:GenerateGUID(false)
scratch.Parent = workspace

local function block(name: string, size: Vector3, offset: Vector3, colour: Color3?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = ORIGIN + offset
	part.Color = colour or Color3.fromRGB(200, 200, 200)
	part.Parent = scratch
	return part
end

local floor = block("Floor", Vector3.new(200, 1, 200), Vector3.new(0, -0.5, 0), Color3.fromRGB(60, 220, 60))

local function testWater()
	local W = WaterReflections
	Terrain:SetAttribute("ForgeGUIPrior_WaterReflectance", nil)
	Terrain.WaterReflectance = 0.2
	near(W.setLevel(1), 0.5, 1e-6, "water: high is 0.5")
	near(Terrain.WaterReflectance, 0.5, 1e-3, "water: high applied")
	near(W.setLevel(0.5), 0.3, 1e-6, "water: low is 0.3")
	near(W.setLevel(0), 0.08, 1e-6, "water: off is a faint 0.08 sheen")
	near(Terrain:GetAttribute("ForgeGUIPrior_WaterReflectance") :: number, 0.2, 1e-3, "water: the first prior survives later levels")
	check(W.clear() == true, "water: clear reports work done")
	near(Terrain.WaterReflectance, 0.2, 1e-3, "water: the place's reflectance is restored")
	check(W.clear() == false, "water: a second clear has nothing to do")
end

-- A gatehouse: roof on two walls, passage along X, 6 studs wide, 10 high.
local function gatehouse(): Model
	local model = Instance.new("Model")
	model.Name = "TestGate"
	local function piece(size: Vector3, offset: Vector3)
		local part = block("Piece", size, offset)
		part.Parent = model
	end
	piece(Vector3.new(20, 10, 4), Vector3.new(60, 5, 5)) -- +Z wall, inner face at z = 3
	piece(Vector3.new(20, 10, 4), Vector3.new(60, 5, -5)) -- -Z wall, inner face at z = -3
	piece(Vector3.new(20, 2, 14), Vector3.new(60, 11, 0)) -- roof, underside at y = 10
	model.Parent = scratch
	return model
end

local function testPassage()
	local P = PassageShade
	local gate = gatehouse()
	local stranger = block("ForgeGUI_PassageShade", Vector3.one, Vector3.new(60, 20, 0))
	stranger.Parent = gate -- same name, no ownership attribute
	local frame = CFrame.new(ORIGIN + Vector3.new(60, 0, 0))
	local report = P.apply(gate, { frame = frame, length = 18 })
	check(report.panels == 4, "passage: four panels laid")
	check(#report.guessed == 0, `passage: nothing guessed ({table.concat(report.guessed, ", ")})`)
	near(report.ceiling, 10, 0.1, "passage: ceiling measured by raycast")
	near(report.halfWidth, 3, 0.1, "passage: inner walls measured by raycast")
	check(ownedCount(gate, "ForgeGUIPassageShade") == 4, "passage: panels carry the ownership attribute")
	P.apply(gate, { frame = frame, length = 18, texture = "rbxassetid://1" })
	check(ownedCount(gate, "ForgeGUIPassageShade") == 4, "passage: a second apply replaces, never stacks")
	check(gate:FindFirstChildWhichIsA("Decal", true) ~= nil, "passage: a texture id lays Decals")
	check(P.clear(gate) == 4, "passage: clear removes its four panels")
	check(P.clear(gate) == 0, "passage: a second clear removes nothing")
	check(stranger.Parent == gate, "passage: a same-named stranger survives clear")
end

local function ownedFolder(): Instance?
	for _, child in workspace:GetChildren() do
		if child:GetAttribute("ForgeGUIContactShadows") == true then
			return child
		end
	end
	return nil
end

local function testContactShadows()
	local CS = ContactShadows
	local crate = block("Crate", Vector3.new(4, 4, 4), Vector3.new(-40, 2, 0))
	CollectionService:AddTag(crate, "ForgeGUIContactShadow")
	local hut = Instance.new("Model")
	hut.Name = "hut_2"
	block("Body", Vector3.new(10, 8, 10), Vector3.new(-40, 4, 30)).Parent = hut
	hut.Parent = scratch
	local impostor = Instance.new("Folder")
	impostor.Name = "ForgeGUI_ContactShadows"
	impostor.Parent = workspace
	local focus = ORIGIN + Vector3.new(-40, 3, 10)
	local started = CS.start({
		manual = true,
		ground = { floor },
		roots = { scratch },
		kinds = { hut = { shape = "rect", spread = 1.2 } },
		getFocus = function()
			return focus
		end,
	})
	check(started == true, "contact: start")
	check(CS.start() == false, "contact: a second start is a no-op")
	CS.step(0.6)
	local stats = CS.stats()
	check(stats.watched == 2, `contact: the tagged part and the named model are watched (got {stats.watched})`)
	check(stats.active == 2, `contact: both get a blob (got {stats.active})`)
	local owned = ownedFolder()
	check(owned ~= nil and #(owned :: Instance):GetChildren() == 2, "contact: blobs live in the owned folder")
	CS.setEnabled(false)
	CS.step(0.1)
	check(CS.stats().active == 0, "contact: disabled clears the static blobs")
	CS.setEnabled(true)
	check(CS.stop() == true, "contact: stop")
	check(owned ~= nil and (owned :: Instance).Parent == nil, "contact: the owned folder is destroyed")
	check(impostor.Parent == workspace, "contact: a same-named stranger folder survives")
	check(CS.stop() == false, "contact: a second stop is a no-op")
	impostor:Destroy()
	CollectionService:RemoveTag(crate, "ForgeGUIContactShadow")
end

local function fireScene(): (Part, Part, PointLight, ParticleEmitter, Attachment)
	local lit = block("Brazier", Vector3.new(2, 2, 2), Vector3.new(20, 1, -30))
	local light = Instance.new("PointLight")
	light.Brightness, light.Range, light.Shadows = 3, 12, false
	light.Parent = lit
	local recipe = Instance.new("Attachment")
	recipe.Parent = lit
	local recipeSmoke = Instance.new("ParticleEmitter") -- stands in for ParticleRecipes' embers smoke
	recipeSmoke.Name = "smoke"
	recipeSmoke:SetAttribute("ForgeGUIRecipe", "embers")
	recipeSmoke.Enabled = true
	recipeSmoke.Parent = recipe
	local bare = block("Campfire", Vector3.new(2, 1, 2), Vector3.new(26, 0.5, -30))
	CollectionService:AddTag(lit, "ForgeGUIFire")
	CollectionService:AddTag(bare, "ForgeGUIFire")
	return lit, bare, light, recipeSmoke, recipe
end

local function testFireLight()
	local F = FireLight
	local lit, bare, light, recipeSmoke, recipe = fireScene()
	local started = F.start({ manual = true, shadowLevel = 1, getFocus = function()
		return ORIGIN + Vector3.new(23, 4, -20)
	end })
	check(started == true, "fire: start")
	check(F.start() == false, "fire: a second start is a no-op")
	F.step(0.6)
	local stats = F.stats()
	check(stats.fires == 2 and stats.active == 2, "fire: both tagged sources are active")
	check(stats.shadowed == 2, "fire: high shadow level lets both cast shadows")
	near(light:GetAttribute("ForgeGUIPrior_Brightness") :: number, 3, 1e-6, "fire: the borrowed light's brightness is recorded")
	check(recipeSmoke.Enabled == false, "fire: the recipe's smoke is off while the plume runs")
	check(bare:FindFirstChildWhichIsA("PointLight", true) ~= nil, "fire: a source with no light gets one")
	check(ownedCount(scratch, "ForgeGUIFireLight") >= 6, "fire: plumes, embers, holders and the new light are owned")
	F.setShadowLevel(0)
	F.step(0.1)
	check(F.stats().shadowed == 0, "fire: shadow level 0 turns every shadow off")
	check(F.stop() == true, "fire: stop")
	check(ownedCount(scratch, "ForgeGUIFireLight") == 0, "fire: everything it made is gone")
	near(light.Brightness, 3, 1e-6, "fire: the borrowed light's brightness is restored")
	near(light.Range, 12, 1e-6, "fire: the borrowed light's range is restored")
	check(light.Shadows == false, "fire: the borrowed light's shadows are restored")
	check(light:GetAttribute("ForgeGUIPrior_Brightness") == nil, "fire: restored priors are cleaned up")
	check(recipeSmoke.Enabled == true and recipeSmoke.Parent == recipe, "fire: the recipe's smoke is back on and untouched")
	check(F.stop() == false, "fire: a second stop is a no-op")
	CollectionService:RemoveTag(lit, "ForgeGUIFire")
	CollectionService:RemoveTag(bare, "ForgeGUIFire")
end

local function testGlobalIllumination()
	local GI = GlobalIllumination
	Lighting.ClockTime, Lighting.Brightness = 12, 3
	block("Wall", Vector3.new(30, 12, 2), Vector3.new(0, 6, 8), Color3.fromRGB(220, 60, 60))
	local stranger = Instance.new("Attachment")
	stranger.Name = "ForgeGUI_GIBounce"
	stranger.Parent = Terrain
	local sentinel = Color3.fromRGB(1, 2, 3)
	Lighting:SetAttribute("ForgeGUIPrior_Ambient", sentinel) -- another module's prior
	local outdoor, bottom = Lighting.OutdoorAmbient, Lighting.ColorShift_Bottom
	local options = { manual = true, level = 1, getFocus = function()
		return ORIGIN + Vector3.new(0, 3, 0)
	end }
	GI.start(options)
	GI.start(options)
	check(Lighting:GetAttribute("ForgeGUIGlobalIllumination") == true, "gi: Lighting is marked while running")
	check(Lighting:GetAttribute("ForgeGUIPrior_Ambient") == sentinel, "gi: another module's prior is never overwritten")
	check(sameColour(Lighting:GetAttribute("ForgeGUIPrior_OutdoorAmbient") :: Color3, outdoor), "gi: OutdoorAmbient prior recorded")
	for _ = 1, 40 do
		GI.step(0.1)
	end
	local stats = GI.stats()
	check(stats.running == true, "gi: running")
	check(stats.bounce.G > stats.bounce.R and stats.bounce.G > stats.bounce.B, "gi: the bounce takes the green ground's colour")
	check(stats.lights > 0, `gi: the sunlit floor beside a wall becomes bounce lights (got {stats.lights})`)
	check(ownedCount(Terrain, "ForgeGUIGlobalIllumination") > 0, "gi: bounce lights are owned attachments under Terrain")
	local external = Color3.fromRGB(40, 50, 60)
	Lighting.Ambient = external -- someone else (a day cycle) writes the ambient
	GI.step(0.1)
	check(GI.stop() == true, "gi: stop")
	check(sameColour(Lighting.Ambient, external), "gi: an outside write became the base it restores")
	check(sameColour(Lighting.OutdoorAmbient, outdoor), "gi: OutdoorAmbient restored")
	check(sameColour(Lighting.ColorShift_Bottom, bottom), "gi: ColorShift_Bottom restored")
	check(ownedCount(Terrain, "ForgeGUIGlobalIllumination") == 0, "gi: every bounce light is destroyed")
	check(stranger.Parent == Terrain, "gi: a same-named stranger under Terrain survives")
	check(Lighting:GetAttribute("ForgeGUIPrior_OutdoorAmbient") == nil, "gi: the priors it wrote are cleaned up")
	check(Lighting:GetAttribute("ForgeGUIPrior_Ambient") == sentinel, "gi: a prior it did not write is left alone")
	check(Lighting:GetAttribute("ForgeGUIGlobalIllumination") == nil, "gi: the running marker is removed")
	check(GI.stop() == false, "gi: a second stop is a no-op")
	stranger:Destroy()
	Lighting:SetAttribute("ForgeGUIPrior_Ambient", nil)
end

local ok, failure = xpcall(function()
	testWater()
	testPassage()
	testContactShadows()
	testFireLight()
	testGlobalIllumination()
end, debug.traceback)

pcall(GlobalIllumination.stop)
pcall(ContactShadows.stop)
pcall(FireLight.stop)
pcall(WaterReflections.clear)
scratch:Destroy()
for _, property in SAVED_LIGHTING do
	pcall(function()
		(Lighting :: any)[property] = saved[property]
	end)
end
Terrain.WaterReflectance = savedReflectance
for instance, attributes in savedAttributes do
	for key in instance:GetAttributes() do
		if attributes[key] == nil then
			instance:SetAttribute(key, nil)
		end
	end
	for key, value in attributes do
		instance:SetAttribute(key, value)
	end
end

if not ok then
	error(`FAIL light-transport regression after {#checks} checks:\n{failure}`)
end
print(`PASS light-transport regression: {#checks} checks passed`)
for _, label in checks do
	print("  ok", label)
end
