--!strict
-- WindVfx: the wind made visible as part of the air, around the camera.
-- Client only. Ship as a ModuleScript and start it from a LocalScript:
--
--   local Wind = require(ReplicatedStorage.Wind)
--   local WindVfx = require(ReplicatedStorage.WindVfx)
--   Wind.start()
--   WindVfx.start({ wind = Wind, palette = "snow" })   -- "sand" | "snow" | "leaves" | "ash"
--
-- What it draws (all lit by the scene, LightInfluence 1, so they show where light
-- falls on them and vanish in shade, like real dust):
-- - Ribbons: faint Trails on moving anchors that skim 0.5-4 studs above the
--   ground 15-90 studs ahead of the camera, glide downwind at wind speed with a
--   side-to-side meander, follow the ground height and fade in, out and with
--   distance. More in gusts; in a storm many more, darker and denser.
-- - Ground wisps: very faint, large soft smoke particles dragging downwind near
--   the ground from a volume upwind of the camera, tinted like the terrain under
--   it, scaled by how loose that ground material is (sand streams, paving not).
-- - Motes: fine specks in a box round the camera, visible only in sunlight.
-- - Crest spray: thin streams of grains blown off the lee edge of ridges of a
--   loose material (dune crests, snow cornices) near the camera.
-- - Leaves (optional): fragments from a source point the game reports
--   (FoliageSway's onLeafSource), only when a leaf texture is configured.
--
-- Why not ParticleRecipes.ambient_dust: that recipe is a static emitter at one
-- attachment for a room or a light shaft. This module is camera-local weather:
-- a handful of reusable volumes follow the camera, particles are world-space so
-- moving the volumes never drags them, and every rate is driven by the wind,
-- the ground under the camera and shelter. Use both: ambient_dust in interiors,
-- WindVfx outdoors.
--
-- Tried and retired: flat "swirl streak" sprites for wind. They read as
-- stickers on the lens; the air reads through lit smoke, 3D ribbons and moving
-- things instead.
--
-- Budget: everything is built once at start (`ribbons` trails, `crests`
-- emitters, three dust emitters) and reused; per frame only CFrames move.
-- Ribbon ground probes are a few raycasts per ribbon per second; the crest scan
-- is 12 probes x 3 raycasts every 1.5 s; the shelter/ground look is 2 raycasts
-- every 0.3 s.
--
-- Ownership: every instance it creates carries ForgeGUIWindVfx = true, under
-- one owned Folder. stop() destroys only owned instances and removes the folder
-- only once it is empty, so anything a stranger parented into it survives. It
-- borrows no properties. start() and stop() are idempotent.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

export type WindSource = {
	sample: () -> (Vector3, number, number),
	speed: ((strength: number) -> number)?,
	storm: (() -> number)?,
}
export type Palette = {
	ribbon: Color3,
	ribbonStorm: Color3,
	dustLight: Color3,
	dustDark: Color3,
	mote: Color3,
	grain: Color3,
}
export type Textures = { dust: string?, mote: string?, grain: string?, leaf: string? }
export type Options = {
	wind: WindSource?, -- default: read Workspace.GlobalWind
	palette: (string | Palette)?,
	textures: Textures?, -- rbxassetid overrides; leaf particles only appear with a leaf texture
	ribbons: number?, -- pool size, default 14
	crests: number?, -- crest emitters, default 4; 0 turns crest spray off
	crestMaterials: { Enum.Material }?, -- default { Sand, Snow }
	loose: { [Enum.Material]: number }?, -- 0..1 how much each ground material gives the wisps
	tintFromTerrain: boolean?, -- tint wisps like the terrain material under the camera
	isPaused: (() -> boolean)?, -- true: spawn nothing (pause menu open)
	getExposure: (() -> number)?, -- 0..1; default 0.1 under a roof, else 1
	groundFilter: { Instance }?, -- raycast include list; default { Terrain }
	parent: Instance?, -- default Workspace
	quality: number?, -- 0..1 scales counts and rates, default 1
}
type Ribbon = {
	anchor: Part, trail: Trail, alive: boolean, age: number, life: number, base: Vector3, y: number,
	groundY: number, hover: number, pace: number, phase: number, amp: number, freq: number,
	peak: number, level: number, sinceGround: number,
}
type Crest = { part: Part, grains: ParticleEmitter, used: boolean }
type Spot = { position: Vector3, score: number, colour: Color3 }
type Air = { dir: Vector3, strength: number, gust: number, speed: number, storm: number }
type Rig = {
	folder: Folder, ground: Part, cloud: Part, crown: Part,
	wisps: ParticleEmitter, motes: ParticleEmitter, leaves: ParticleEmitter?,
	ribbons: { Ribbon }, crests: { Crest },
}

local OWNED_ATTR = "ForgeGUIWindVfx"
local TAU = math.pi * 2
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds" -- soft, round, reads as lit air
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local PARK = CFrame.new(0, -10000, 0) -- idle anchors wait far below the world

local PALETTES: { [string]: Palette } = {
	sand = {
		ribbon = Color3.fromRGB(230, 205, 165), ribbonStorm = Color3.fromRGB(160, 128, 94),
		dustLight = Color3.fromRGB(240, 214, 168), dustDark = Color3.fromRGB(206, 168, 118),
		mote = Color3.fromRGB(255, 238, 204), grain = Color3.fromRGB(230, 205, 165),
	},
	snow = {
		ribbon = Color3.fromRGB(240, 246, 255), ribbonStorm = Color3.fromRGB(196, 208, 224),
		dustLight = Color3.fromRGB(248, 250, 255), dustDark = Color3.fromRGB(205, 215, 230),
		mote = Color3.fromRGB(255, 255, 255), grain = Color3.fromRGB(245, 248, 255),
	},
	leaves = {
		ribbon = Color3.fromRGB(214, 222, 196), ribbonStorm = Color3.fromRGB(150, 160, 130),
		dustLight = Color3.fromRGB(205, 200, 170), dustDark = Color3.fromRGB(150, 140, 110),
		mote = Color3.fromRGB(240, 240, 210), grain = Color3.fromRGB(170, 160, 120),
	},
	ash = {
		ribbon = Color3.fromRGB(170, 166, 160), ribbonStorm = Color3.fromRGB(90, 86, 84),
		dustLight = Color3.fromRGB(150, 146, 142), dustDark = Color3.fromRGB(80, 76, 74),
		mote = Color3.fromRGB(210, 205, 200), grain = Color3.fromRGB(120, 116, 112),
	},
}

-- How much loose material each ground gives the wisps (anything else: 0.15).
local DEFAULT_LOOSE: { [Enum.Material]: number } = {
	[Enum.Material.Sand] = 1, [Enum.Material.Snow] = 1, [Enum.Material.Salt] = 0.6,
	[Enum.Material.Ground] = 0.5, [Enum.Material.Sandstone] = 0.45, [Enum.Material.Glacier] = 0.4,
	[Enum.Material.Grass] = 0.25, [Enum.Material.LeafyGrass] = 0.3, [Enum.Material.Rock] = 0.3,
	[Enum.Material.Limestone] = 0.3, [Enum.Material.Basalt] = 0.3, [Enum.Material.Slate] = 0.25,
	[Enum.Material.Mud] = 0.2, [Enum.Material.Water] = 0,
}

-- Ribbons
local SPAWN_MIN, SPAWN_MAX = 15, 90
local SPAWN_CONE = math.rad(80) -- looked for within this yaw of the view
local SPAWN_STEP, SPAWN_PER_STEP = 0.1, 2
local HOVER_MIN, HOVER_MAX = 0.5, 4
local LIFE_MIN, LIFE_MAX = 1.5, 3.5
local PEAK, STORM_PEAK = 0.75, 0.62 -- the most opaque a ribbon gets (transparency)
local FADE_NEAR, FADE_FAR, KILL_RANGE = 45, 90, 110
local GROUND_STEP, FADE_LEVELS = 0.25, 8
-- Crests
local CREST_STEP, CREST_PROBES = 1.5, 12
local CREST_MIN, CREST_MAX = 12, 70
local CREST_REACH, CREST_RISE, CREST_SPACING = 6, 0.8, 10
local GRAIN_RATE = 45
-- Dust
local UPWIND = 22 -- the wisp volume sits this far upwind of the focus
local WISP_RATE, MOTE_RATE, LEAF_RATE = 7, 7, 1.8
local LOOK_STEP, RATE_STEP = 0.3, 0.2

local WindVfx = {}
WindVfx.PALETTES = PALETTES
WindVfx.DEFAULT_LOOSE = DEFAULT_LOOSE

local rng = Random.new()
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.IgnoreWater = false

local options: Options = {}
local palette: Palette = PALETTES.sand
local crestSet: { [Enum.Material]: boolean } = {}
local rig: Rig? = nil
local connection: RBXScriptConnection? = nil
local leafSource: Vector3? = nil
local look = { groundY = 0, material = Enum.Material.Air, sheltered = false, tint = PALETTES.sand.dustLight }
local timers = { spawn = 0, look = LOOK_STEP, rates = RATE_STEP, scan = CREST_STEP }
local appliedTint: Color3? = nil

local function kp(t: number, v: number): NumberSequenceKeypoint
	return NumberSequenceKeypoint.new(t, v)
end

local function own<T>(instance: T): T
	(instance :: any):SetAttribute(OWNED_ATTR, true)
	return instance
end

local function quality(): number
	local q = options.quality
	return if type(q) == "number" and q == q then math.clamp(q, 0, 1) else 1
end

local function anchorPart(name: string, size: Vector3, parent: Instance): Part
	local part = own(Instance.new("Part"))
	part.Name = name
	part.Anchored = true
	part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = false, false, false, false
	part.Transparency = 1
	part.Size = size
	part.CFrame = PARK
	part.Parent = parent
	return part
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = own(Instance.new("ParticleEmitter"))
	e.Rate = 0
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.LightInfluence, e.LightEmission = 1, 0
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

-- Wind -----------------------------------------------------------------------------------

-- The wind this frame, from the injected source or else Workspace.GlobalWind.
local function airNow(): Air
	local source = options.wind
	if source then
		local dir, strength, gust = source.sample()
		local speed = if source.speed then source.speed(strength) else 3 + 22 * strength
		local storm = if source.storm then source.storm() else 0
		return { dir = dir, strength = strength, gust = gust, speed = speed, storm = storm }
	end
	local v = Workspace.GlobalWind
	local flat = Vector3.new(v.X, 0, v.Z)
	local speed = v.Magnitude
	local dir = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(-1, 0, 0)
	return { dir = dir, strength = math.max(0, (speed - 3) / 22), gust = 0, speed = speed, storm = 0 }
end

-- 0..1 how windy it is: the base breeze plus the gust.
local function windiness(air: Air): number
	return math.clamp(0.2 + 0.45 * math.clamp((air.strength - 0.15) / 0.85, 0, 1) + 0.35 * air.gust, 0, 1)
end

local function exposure(): number
	local custom = options.getExposure
	if custom then
		local ok, value = pcall(custom)
		return if ok and type(value) == "number" then math.clamp(value, 0, 1) else 1
	end
	return if look.sheltered then 0.1 else 1
end

local function paused(): boolean
	local check = options.isPaused
	return check ~= nil and check() == true
end

-- Looking around -----------------------------------------------------------------------

local function groundAt(x: number, z: number, top: number): RaycastResult?
	return Workspace:Raycast(Vector3.new(x, top + 120, z), Vector3.new(0, -400, 0), rayParams)
end

local function terrainColour(material: Enum.Material, fallback: Color3): Color3
	local ok, colour = pcall(Workspace.Terrain.GetMaterialColor, Workspace.Terrain, material)
	return if ok then colour else fallback
end

-- The ground under the focus, its tint, and whether a roof is above it.
local function lookAround(focus: Vector3)
	local hit = Workspace:Raycast(focus + Vector3.new(0, 2, 0), Vector3.new(0, -252, 0), rayParams)
	look.groundY = if hit then hit.Position.Y else focus.Y - 4
	look.material = if hit then hit.Material else Enum.Material.Air
	if hit and hit.Instance == Workspace.Terrain and options.tintFromTerrain ~= false then
		look.tint = terrainColour(hit.Material, palette.dustLight)
	else
		look.tint = palette.dustLight
	end
	look.sheltered = Workspace:Raycast(focus + Vector3.new(0, 1, 0), Vector3.new(0, 60, 0), rayParams) ~= nil
end

-- A random ground point in front of the camera, `reach` studs away.
local function aheadOf(cf: CFrame, reach: number): (number, number)
	local yaw = math.atan2(-cf.LookVector.X, -cf.LookVector.Z) + rng:NextNumber(-SPAWN_CONE, SPAWN_CONE)
	return cf.Position.X - math.sin(yaw) * reach, cf.Position.Z - math.cos(yaw) * reach
end

-- Ribbons ---------------------------------------------------------------------------------

local function buildRibbon(folder: Folder): Ribbon
	local anchor = anchorPart("Ribbon", Vector3.new(0.2, 0.2, 0.2), folder)
	local gap = rng:NextNumber(0.25, 0.5)
	local low, high = own(Instance.new("Attachment")), own(Instance.new("Attachment"))
	low.Position, high.Position = Vector3.new(0, -gap / 2, 0), Vector3.new(0, gap / 2, 0)
	low.Parent, high.Parent = anchor, anchor
	local trail = own(Instance.new("Trail"))
	trail.Attachment0, trail.Attachment1 = low, high
	trail.Enabled = false
	trail.FaceCamera = true
	trail.Lifetime = rng:NextNumber(0.6, 1.1)
	trail.MinLength = 0.2
	trail.WidthScale = NumberSequence.new({ kp(0, 1), kp(0.6, 0.7), kp(1, 0.2) })
	trail.Transparency = NumberSequence.new(1)
	trail.LightInfluence, trail.LightEmission = 1, 0
	trail.Parent = anchor
	return {
		anchor = anchor, trail = trail, alive = false, age = 0, life = 0, base = Vector3.zero, y = 0, groundY = 0,
		hover = 1, pace = 1, phase = 0, amp = 0, freq = 1, peak = PEAK, level = -1, sinceGround = 0,
	}
end

local function spawnRibbon(r: Ribbon, cf: CFrame, storm: number): boolean
	local x, z = aheadOf(cf, rng:NextNumber(SPAWN_MIN, SPAWN_MAX))
	local hit = groundAt(x, z, cf.Position.Y)
	if not hit or hit.Material == Enum.Material.Water then
		return false
	end
	r.alive, r.age, r.life = true, 0, rng:NextNumber(LIFE_MIN, LIFE_MAX)
	r.base, r.groundY = Vector3.new(x, 0, z), hit.Position.Y
	r.hover = rng:NextNumber(HOVER_MIN, HOVER_MAX) * (1 - 0.5 * storm)
	r.y = r.groundY + r.hover
	r.pace, r.phase = rng:NextNumber(0.85, 1.1), rng:NextNumber(0, TAU)
	r.amp, r.freq = rng:NextNumber(0.4, 1.6), rng:NextNumber(1.2, 2.6)
	r.peak, r.level, r.sinceGround = PEAK + (STORM_PEAK - PEAK) * storm, -1, 0
	r.trail.Color = ColorSequence.new(palette.ribbon:Lerp(palette.ribbonStorm, storm))
	r.trail.Transparency = NumberSequence.new(1)
	r.anchor.CFrame = CFrame.new(x, r.y, z)
	r.trail:Clear()
	r.trail.Enabled = true
	return true
end

local function killRibbon(r: Ribbon)
	r.alive = false
	r.trail.Enabled = false
	r.anchor.CFrame = PARK
end

-- Transparency along the trail for a 0..1 visibility (head and tail fade).
local function ribbonLook(peak: number, visible: number): NumberSequence
	local t = 1 - (1 - peak) * visible
	return NumberSequence.new({ kp(0, 1), kp(0.15, t), kp(0.6, t), kp(1, 1) })
end

local function stepRibbon(r: Ribbon, dt: number, air: Air, eye: Vector3)
	r.age += dt
	if r.age >= r.life then
		killRibbon(r)
		return
	end
	local dir = air.dir
	r.base += dir * (air.speed * r.pace * dt)
	local side = Vector3.new(-dir.Z, 0, dir.X) * (r.amp * math.sin(r.age * r.freq + r.phase))
	local x, z = r.base.X + side.X, r.base.Z + side.Z
	r.sinceGround += dt
	if r.sinceGround >= GROUND_STEP then
		r.sinceGround = 0
		local ahead = dir * (air.speed * GROUND_STEP)
		local hit = groundAt(x + ahead.X, z + ahead.Z, r.y)
		r.groundY = if hit then hit.Position.Y else r.groundY
	end
	local target = r.groundY + r.hover + 0.25 * math.sin(r.age * 1.7 + r.phase)
	r.y += (target - r.y) * (1 - math.exp(-dt * 5))
	local position = Vector3.new(x, r.y, z)
	local far = (position - eye).Magnitude
	if far > KILL_RANGE then
		killRibbon(r)
		return
	end
	r.anchor.CFrame = CFrame.new(position)
	-- Visibility moves in FADE_LEVELS steps so the sequence is rebuilt a few times a life.
	local envelope = math.clamp(math.min(r.age / 0.4, (r.life - r.age) / 0.6), 0, 1)
	local distance = 1 - 0.7 * math.clamp((far - FADE_NEAR) / (FADE_FAR - FADE_NEAR), 0, 1)
	local level = math.floor(envelope * distance * FADE_LEVELS + 0.5)
	if level ~= r.level then
		r.level = level
		r.trail.Transparency = ribbonLook(r.peak, level / FADE_LEVELS)
	end
end

local function stepRibbons(ribbons: { Ribbon }, cf: CFrame, dt: number, air: Air, spawnNow: boolean)
	local alive = 0
	for _, r in ribbons do
		if r.alive then
			stepRibbon(r, dt, air, cf.Position)
			alive += if r.alive then 1 else 0
		end
	end
	if not spawnNow or paused() then
		return
	end
	local reach = math.max(exposure(), 0.5 * air.storm)
	local want = math.floor(#ribbons * math.clamp(windiness(air) + air.storm, 0, 1) * reach + 0.5)
	local spawned = 0
	for _, r in ribbons do
		if alive >= want or spawned >= SPAWN_PER_STEP then
			break
		end
		if not r.alive and spawnRibbon(r, cf, air.storm) then
			alive += 1
			spawned += 1
		end
	end
end

-- Crest spray -------------------------------------------------------------------------------

local function buildCrest(folder: Folder, texture: string): Crest
	local part = anchorPart("CrestSpray", Vector3.new(8, 0.3, 1.5), folder)
	local grains = emitter(part, {
		Name = "Grains", Texture = texture, EmissionDirection = Enum.NormalId.Front,
		Color = ColorSequence.new(palette.grain), Size = NumberSequence.new({ kp(0, 0.2), kp(1, 0.08) }),
		Transparency = NumberSequence.new({ kp(0, 0.35), kp(0.7, 0.5), kp(1, 1) }),
		Lifetime = NumberRange.new(0.5, 1.2), SpreadAngle = Vector2.new(6, 18), Acceleration = Vector3.new(0, -6, 0),
		Drag = 1.2, WindAffectsDrag = true,
	})
	return { part = part, grains = grains, used = false }
end

-- A ridge at (x, z): loose material standing above the ground upwind and
-- falling away downwind. Returns nil where there is none.
local function crestAt(x: number, z: number, top: number, dir: Vector3): Spot?
	local hit = groundAt(x, z, top)
	if not hit or not crestSet[hit.Material] then
		return nil
	end
	local h = hit.Position.Y
	local up = groundAt(x - dir.X * CREST_REACH, z - dir.Z * CREST_REACH, top)
	local down = groundAt(x + dir.X * CREST_REACH, z + dir.Z * CREST_REACH, top)
	if not up or not down or h < up.Position.Y + 0.3 or h < down.Position.Y + CREST_RISE then
		return nil
	end
	local onTerrain = hit.Instance == Workspace.Terrain
	local colour = if onTerrain then terrainColour(hit.Material, palette.grain) else palette.grain
	return { position = hit.Position, score = h - down.Position.Y, colour = colour }
end

-- Puts the emitters on the best ridges found, CREST_SPACING apart; the rest idle.
local function placeCrests(crests: { Crest }, cf: CFrame, dir: Vector3)
	local spots: { Spot } = {}
	for _ = 1, CREST_PROBES do
		local x, z = aheadOf(cf, rng:NextNumber(CREST_MIN, CREST_MAX))
		local spot = crestAt(x, z, cf.Position.Y, dir)
		if spot then
			table.insert(spots, spot)
		end
	end
	table.sort(spots, function(a: Spot, b: Spot): boolean
		return a.score > b.score
	end)
	local placed: { Vector3 } = {}
	for _, spot in spots do
		local clear = #placed < #crests
		for _, other in placed do
			clear = clear and (other - spot.position).Magnitude >= CREST_SPACING
		end
		if clear then
			local crest = crests[#placed + 1]
			local at = spot.position + Vector3.new(0, 0.3, 0)
			crest.part.CFrame = CFrame.lookAt(at, at + dir + Vector3.new(0, 0.25, 0))
			crest.grains.Color = ColorSequence.new(spot.colour:Lerp(Color3.new(1, 1, 1), 0.1))
			crest.used = true
			table.insert(placed, spot.position)
		end
	end
	for i = #placed + 1, #crests do
		crests[i].used = false
	end
end

-- Dust rig ------------------------------------------------------------------------------------

local function buildWisps(folder: Folder, texture: string?): (Part, ParticleEmitter)
	local ground = anchorPart("WispVolume", Vector3.new(150, 2.6, 150), folder)
	local wisps = emitter(ground, {
		Name = "GroundWisps", Texture = texture or TEX_SMOKE, EmissionDirection = Enum.NormalId.Front,
		Color = ColorSequence.new(palette.dustLight, palette.dustDark), Size = NumberSequence.new({ kp(0, 4), kp(1, 11) }),
		Transparency = NumberSequence.new({ kp(0, 1), kp(0.25, 0.86), kp(0.7, 0.91), kp(1, 1) }),
		Lifetime = NumberRange.new(2.2, 3.6), SpreadAngle = Vector2.new(8, 3), Acceleration = Vector3.new(0, 0.25, 0),
		Drag = 0.6, WindAffectsDrag = true, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-18, 18),
	})
	return ground, wisps
end

local function buildFloaters(folder: Folder, moteTexture: string?, leafTexture: string?): (Part, Part, ParticleEmitter, ParticleEmitter?)
	local cloud = anchorPart("MoteVolume", Vector3.new(46, 18, 46), folder)
	local motes = emitter(cloud, {
		Name = "Motes", Texture = moteTexture or TEX_SPARK, Color = ColorSequence.new(palette.mote),
		Size = NumberSequence.new({ kp(0, 0), kp(0.2, 0.14), kp(0.8, 0.1), kp(1, 0) }),
		Transparency = NumberSequence.new({ kp(0, 1), kp(0.25, 0.2), kp(0.75, 0.35), kp(1, 1) }),
		Lifetime = NumberRange.new(5, 8), Speed = NumberRange.new(0.1, 0.5), SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 0.12, 0), Drag = 0.08, WindAffectsDrag = true, LightEmission = 0.4, Brightness = 2,
	})
	local crown = anchorPart("LeafVolume", Vector3.new(12, 5, 12), folder)
	local leaves = if leafTexture
		then emitter(crown, {
			Name = "Leaves", Texture = leafTexture, Size = NumberSequence.new(0.85, 0.7),
			Transparency = NumberSequence.new({ kp(0, 1), kp(0.08, 0), kp(0.85, 0), kp(1, 1) }),
			Lifetime = NumberRange.new(5, 8), Speed = NumberRange.new(0.5, 2), SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, -2.4, 0), Drag = 0.9, WindAffectsDrag = true,
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-160, 160),
		})
		else nil
	return cloud, crown, motes, leaves
end

local function daylight(): number
	local hour = Lighting.ClockTime
	return if hour > 6 and hour < 19 then 1 else 0.35
end

local function setRates(r: Rig, air: Air)
	local stop = paused()
	local q = quality()
	local loose = (options.loose or DEFAULT_LOOSE)[look.material] or 0.15
	local breeze = math.clamp((air.strength - 0.15) / 0.85, 0, 1.4)
	r.wisps.Rate = if stop then 0 else WISP_RATE * q * exposure() * loose * (0.25 + 0.75 * breeze)
	r.wisps.Speed = NumberRange.new(air.speed * 0.6, air.speed * 0.9)
	if appliedTint ~= look.tint then
		appliedTint = look.tint
		r.wisps.Color = ColorSequence.new(look.tint:Lerp(Color3.new(1, 1, 1), 0.12), look.tint:Lerp(palette.dustDark, 0.3))
	end
	r.motes.Rate = if stop then 0 else MOTE_RATE * q * daylight() * (if look.sheltered then 1.2 else 1)
	local leaves = r.leaves
	if leaves then
		local near = leafSource ~= nil and not stop
		leaves.Rate = if near then LEAF_RATE * q * (0.25 + air.gust + 0.3 * air.strength) else 0
	end
	local blow = math.clamp(windiness(air) - 0.25 + air.storm, 0, 1.5) * exposure()
	for _, crest in r.crests do
		crest.grains.Rate = if crest.used and not stop then GRAIN_RATE * q * blow else 0
		crest.grains.Speed = NumberRange.new(air.speed * 0.35, air.speed * 0.6)
	end
end

local function follow(r: Rig, camera: Camera, dir: Vector3)
	local focus = camera.Focus.Position
	local low = Vector3.new(focus.X, look.groundY + 1.4, focus.Z) - dir * UPWIND
	r.ground.CFrame = CFrame.lookAt(low, low + dir)
	r.cloud.CFrame = CFrame.new(camera.CFrame.Position)
	local crown = leafSource
	if crown then
		r.crown.CFrame = CFrame.new(crown)
	end
end

-- Destroys owned roots under `parent`: their owned children, then the folder if
-- it is empty. A folder holding a stranger's items is kept and no longer claimed.
local function sweep(parent: Instance): number
	local found = 0
	for _, child in parent:GetChildren() do
		if child:GetAttribute(OWNED_ATTR) == true and child:IsA("Folder") then
			found += 1
			for _, item in child:GetChildren() do
				if item:GetAttribute(OWNED_ATTR) == true then
					item:Destroy()
				end
			end
			if #child:GetChildren() == 0 then
				child:Destroy()
			else
				child:SetAttribute(OWNED_ATTR, nil)
			end
		end
	end
	return found
end

local function resolvePalette(value: (string | Palette)?): Palette
	if type(value) == "table" then
		return value
	end
	return PALETTES[if type(value) == "string" then value else "sand"] or PALETTES.sand
end

local function buildRig(parent: Instance): Rig
	local folder = own(Instance.new("Folder"))
	folder.Name = "ForgeGUI_WindVfx"
	folder.Parent = parent
	local textures: Textures = options.textures or {}
	local ground, wisps = buildWisps(folder, textures.dust)
	local cloud, crown, motes, leaves = buildFloaters(folder, textures.mote, textures.leaf)
	local q = quality()
	local ribbons: { Ribbon }, crests: { Crest } = {}, {}
	for i = 1, math.floor((options.ribbons or 14) * q + 0.5) do
		ribbons[i] = buildRibbon(folder)
	end
	for i = 1, math.floor((options.crests or 4) * q + 0.5) do
		crests[i] = buildCrest(folder, textures.grain or TEX_SMOKE)
	end
	return {
		folder = folder, ground = ground, cloud = cloud, crown = crown, wisps = wisps, motes = motes,
		leaves = leaves, ribbons = ribbons, crests = crests,
	}
end

-- Public -----------------------------------------------------------------------------------

-- Where leaf fragments blow from (a tree crown), or nil when none is near.
-- FoliageSway.start({ onLeafSource = WindVfx.setLeafSource }) wires it.
function WindVfx.setLeafSource(position: Vector3?)
	leafSource = position
end

-- One frame. Public so tests and custom loops can drive it.
function WindVfx.step(dt: number)
	local r = rig
	local camera = Workspace.CurrentCamera
	if not r or not camera then
		return
	end
	local air = airNow()
	timers.look += dt
	if timers.look >= LOOK_STEP then
		timers.look = 0
		lookAround(camera.Focus.Position)
	end
	follow(r, camera, air.dir)
	timers.spawn += dt
	local spawnNow = timers.spawn >= SPAWN_STEP
	timers.spawn = if spawnNow then 0 else timers.spawn
	stepRibbons(r.ribbons, camera.CFrame, dt, air, spawnNow)
	timers.scan += dt
	if timers.scan >= CREST_STEP and #r.crests > 0 then
		timers.scan = 0
		placeCrests(r.crests, camera.CFrame, air.dir)
	end
	timers.rates += dt
	if timers.rates >= RATE_STEP then
		timers.rates = 0
		setRates(r, air)
	end
end

-- Builds the rig and starts the Heartbeat loop. A second call while running is ignored.
function WindVfx.start(opts: Options?)
	if connection then
		return
	end
	options = opts or {}
	palette = resolvePalette(options.palette)
	crestSet = {}
	local materials: { Enum.Material } = options.crestMaterials or { Enum.Material.Sand, Enum.Material.Snow }
	for _, material in materials do
		crestSet[material] = true
	end
	rayParams.FilterDescendantsInstances = options.groundFilter or { Workspace.Terrain }
	local parent = options.parent or Workspace
	sweep(parent) -- a previous run's leftovers, by ownership only
	rig = buildRig(parent)
	appliedTint, look.tint = nil, palette.dustLight
	timers.spawn, timers.look, timers.rates, timers.scan = 0, LOOK_STEP, RATE_STEP, CREST_STEP
	connection = RunService.Heartbeat:Connect(WindVfx.step)
end

-- Stops the loop and removes what start() made. Safe to call twice; returns
-- true when there was something to stop or remove.
function WindVfx.stop(): boolean
	local conn = connection
	connection = nil
	if conn then
		conn:Disconnect()
	end
	local r = rig
	rig = nil
	local parent: Instance = if r and r.folder.Parent then r.folder.Parent else options.parent or Workspace
	return sweep(parent) > 0 or conn ~= nil
end

function WindVfx.isRunning(): boolean
	return connection ~= nil
end

return WindVfx
