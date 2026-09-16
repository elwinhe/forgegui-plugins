--!strict
-- ParticleRecipes: declarative VFX descriptors built by one reviewed constructor.
-- Ship as ReplicatedStorage.ParticleRecipes or paste into execute_luau.
--
-- attach(name, target, overrides?)  -> Attachment holding the emitters, parented to target
-- burst(handle, count?)             -> one-shot Emit on recipe-owned emitters in the handle
-- burstAt(name, position, lifetime?) -> transient burst at a world position, auto-cleaned
-- detach(target)                    -> removes recipe emitters and empty owned attachments
--
-- Cleanup contract: emitters live under an Attachment on the target, so destroying the
-- target destroys them. Transient bursts are parented to workspace.Terrain and removed
-- by Debris after `lifetime` seconds. Rates are clamped by each recipe's maxRate.
-- Textures default to engine-bundled rbxasset particle textures; override `texture`
-- with an rbxassetid once a generated sprite has been published as a Roblox image.

local Debris = game:GetService("Debris")

export type EmitterSpec = {
	texture: string?,
	color: ColorSequence,
	size: NumberSequence,
	transparency: NumberSequence,
	lifetime: NumberRange,
	rate: number,
	speed: NumberRange,
	spreadAngle: Vector2?,
	rotation: NumberRange?,
	rotSpeed: NumberRange?,
	acceleration: Vector3?,
	drag: number?,
	lightEmission: number?,
	lightInfluence: number?,
	orientation: Enum.ParticleOrientation?,
	zOffset: number?,
	squash: NumberSequence?,
	shape: Enum.ParticleEmitterShape?,
	shapeInOut: Enum.ParticleEmitterShapeInOut?,
	enabled: boolean?, -- false = burst-only emitter
}

export type Recipe = {
	description: string,
	burst: boolean, -- true: emitters start disabled and are fired with burst()
	burstCount: number,
	maxRate: number,
	emitters: { [string]: EmitterSpec },
}

local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"

local function c3(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local function seq2(a: number, b: number): NumberSequence
	return NumberSequence.new(a, b)
end
local function seq3(a: number, mid: number, b: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, a),
		NumberSequenceKeypoint.new(0.5, mid),
		NumberSequenceKeypoint.new(1, b),
	})
end
local function cseq(a: Color3, b: Color3): ColorSequence
	return ColorSequence.new(a, b)
end

local Recipes: { [string]: Recipe } = {
	hit_impact = {
		description = "Melee/projectile hit: bright spark burst plus a short dust puff. Fire with burst() on contact.",
		burst = true,
		burstCount = 18,
		maxRate = 0,
		emitters = {
			sparks = {
				texture = TEX_SPARK,
				color = cseq(c3(255, 240, 200), c3(255, 140, 60)),
				size = seq2(0.35, 0),
				transparency = seq2(0, 1),
				lifetime = NumberRange.new(0.15, 0.35),
				rate = 0,
				speed = NumberRange.new(18, 30),
				spreadAngle = Vector2.new(180, 180),
				acceleration = Vector3.new(0, -40, 0),
				drag = 4,
				lightEmission = 1,
				enabled = false,
			},
			puff = {
				texture = TEX_SMOKE,
				color = cseq(c3(210, 200, 190), c3(160, 150, 140)),
				size = seq2(0.8, 2.2),
				transparency = seq2(0.5, 1),
				lifetime = NumberRange.new(0.25, 0.45),
				rate = 0,
				speed = NumberRange.new(3, 6),
				spreadAngle = Vector2.new(180, 180),
				rotSpeed = NumberRange.new(-90, 90),
				drag = 6,
				enabled = false,
			},
		},
	},
	muzzle_flash = {
		description = "Gun or wand discharge: short flash plus sparks. Orient the barrel-tip attachment's local +Y along the barrel.",
		burst = true,
		burstCount = 6,
		maxRate = 0,
		emitters = {
			flash = {
				texture = TEX_FIRE,
				color = cseq(c3(255, 250, 220), c3(255, 170, 60)),
				size = seq2(1.6, 0.2),
				transparency = seq2(0, 1),
				lifetime = NumberRange.new(0.05, 0.08),
				rate = 0,
				speed = NumberRange.new(0, 0),
				lightEmission = 1,
				enabled = false,
			},
			sparks = {
				texture = TEX_SPARK,
				color = cseq(c3(255, 220, 140), c3(255, 120, 40)),
				size = seq2(0.25, 0),
				transparency = seq2(0, 1),
				lifetime = NumberRange.new(0.12, 0.25),
				rate = 0,
				speed = NumberRange.new(25, 45),
				spreadAngle = Vector2.new(12, 12),
				drag = 8,
				lightEmission = 1,
				enabled = false,
			},
		},
	},
	pickup_sparkle = {
		description = "Collectible idle glow: slow rising sparkles with soft additive light. Loops until the pickup is destroyed.",
		burst = false,
		burstCount = 12,
		maxRate = 12,
		emitters = {
			sparkles = {
				texture = TEX_SPARK,
				color = cseq(c3(255, 245, 180), c3(255, 200, 90)),
				size = seq3(0, 0.6, 0),
				transparency = seq3(1, 0, 1),
				lifetime = NumberRange.new(0.9, 1.4),
				rate = 12,
				speed = NumberRange.new(1, 2),
				spreadAngle = Vector2.new(180, 180),
				acceleration = Vector3.new(0, 2, 0),
				lightEmission = 0.9,
				lightInfluence = 0,
				shape = Enum.ParticleEmitterShape.Sphere,
				shapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
			},
		},
	},
	ambient_dust = {
		description = "Slow drifting motes from one attachment position for interiors, caves and shafts of light; does not fill a part's volume.",
		burst = false,
		burstCount = 0,
		maxRate = 6,
		emitters = {
			motes = {
				texture = TEX_SPARK,
				color = cseq(c3(230, 225, 210), c3(200, 195, 180)),
				size = seq3(0, 0.25, 0),
				transparency = seq3(1, 0.3, 1),
				lifetime = NumberRange.new(4, 7),
				rate = 6,
				speed = NumberRange.new(0.2, 0.6),
				spreadAngle = Vector2.new(180, 180),
				acceleration = Vector3.new(0.3, 0.1, 0),
				lightEmission = 0.3,
				shape = Enum.ParticleEmitterShape.Box,
				shapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
			},
		},
	},
	embers = {
		description = "Rising embers and heat haze smoke for fires and forges. Pair with a PointLight on the same part.",
		burst = false,
		burstCount = 0,
		maxRate = 24,
		emitters = {
			embers = {
				texture = TEX_SPARK,
				color = cseq(c3(255, 190, 90), c3(200, 60, 20)),
				size = seq3(0, 0.4, 0),
				transparency = seq3(1, 0, 1),
				lifetime = NumberRange.new(1.2, 2.2),
				rate = 18,
				speed = NumberRange.new(2, 4),
				spreadAngle = Vector2.new(25, 25),
				acceleration = Vector3.new(0, 3, 0),
				drag = 1,
				lightEmission = 1,
				lightInfluence = 0,
			},
			smoke = {
				texture = TEX_SMOKE,
				color = cseq(c3(90, 80, 75), c3(50, 45, 45)),
				size = seq2(1.2, 4),
				transparency = seq3(0.45, 0.7, 1),
				lifetime = NumberRange.new(1.5, 2.5),
				rate = 4,
				speed = NumberRange.new(1.5, 2.5),
				spreadAngle = Vector2.new(15, 15),
				rotSpeed = NumberRange.new(-20, 20),
				acceleration = Vector3.new(0, 1, 0),
			},
		},
	},
	footstep_puff = {
		description = "Small dust puff at the foot on landing or each step. Fire with burstAt(position).",
		burst = true,
		burstCount = 5,
		maxRate = 0,
		emitters = {
			puff = {
				texture = TEX_SMOKE,
				color = cseq(c3(200, 190, 175), c3(170, 160, 150)),
				size = seq2(0.5, 1.4),
				transparency = seq2(0.55, 1),
				lifetime = NumberRange.new(0.3, 0.5),
				rate = 0,
				speed = NumberRange.new(1.5, 3),
				spreadAngle = Vector2.new(60, 60),
				rotSpeed = NumberRange.new(-60, 60),
				drag = 5,
				enabled = false,
			},
		},
	},
	portal_aura = {
		description = "Swirling magical aura for portals, shrines and boss spawns. Two layers: inward pull and outward glow.",
		burst = false,
		burstCount = 0,
		maxRate = 40,
		emitters = {
			pull = {
				texture = TEX_SPARK,
				color = cseq(c3(150, 120, 255), c3(60, 200, 255)),
				size = seq3(0, 0.55, 0),
				transparency = seq3(1, 0, 1),
				lifetime = NumberRange.new(1.2, 1.8),
				rate = 28,
				speed = NumberRange.new(4, 6),
				spreadAngle = Vector2.new(180, 180),
				lightEmission = 1,
				lightInfluence = 0,
				shape = Enum.ParticleEmitterShape.Sphere,
				shapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
			},
			glow = {
				texture = TEX_FIRE,
				color = cseq(c3(120, 90, 255), c3(40, 160, 255)),
				size = seq3(2, 3.2, 2),
				transparency = seq3(0.85, 0.6, 0.9),
				lifetime = NumberRange.new(0.8, 1.2),
				rate = 6,
				speed = NumberRange.new(0, 0.5),
				rotSpeed = NumberRange.new(-40, 40),
				lightEmission = 1,
				zOffset = -0.5,
			},
		},
	},
}

local ATTR = "ForgeGUIRecipe"
local OWNED_ATTR = "ForgeGUIRecipeOwned"

local function applySpec(emitter: ParticleEmitter, spec: EmitterSpec, rateCap: number)
	emitter.Texture = spec.texture or TEX_SPARK
	emitter.Color = spec.color
	emitter.Size = spec.size
	emitter.Transparency = spec.transparency
	emitter.Lifetime = spec.lifetime
	emitter.Rate = math.min(spec.rate, rateCap)
	emitter.Speed = spec.speed
	emitter.SpreadAngle = spec.spreadAngle or Vector2.new(0, 0)
	emitter.Rotation = spec.rotation or NumberRange.new(0, 360)
	emitter.RotSpeed = spec.rotSpeed or NumberRange.new(0, 0)
	emitter.Acceleration = spec.acceleration or Vector3.zero
	emitter.Drag = spec.drag or 0
	emitter.LightEmission = spec.lightEmission or 0
	emitter.LightInfluence = spec.lightInfluence or 1
	emitter.Orientation = spec.orientation or Enum.ParticleOrientation.FacingCamera
	emitter.ZOffset = spec.zOffset or 0
	if spec.squash then
		emitter.Squash = spec.squash
	end
	emitter.Shape = spec.shape or Enum.ParticleEmitterShape.Box
	emitter.ShapeInOut = spec.shapeInOut or Enum.ParticleEmitterShapeInOut.Outward
	emitter.Enabled = if spec.enabled == nil then true else spec.enabled
end

local M = {}
M.Recipes = Recipes

function M.list(): { string }
	local names = {}
	for name in Recipes do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- Merge per-emitter overrides, e.g. { texture = "rbxassetid://123", rate = 5 } applied to every emitter,
-- or { emitters = { sparks = { rate = 2 } } } for one emitter.
local function mergedSpec(base: EmitterSpec, emitterName: string, overrides: { [string]: any }?): EmitterSpec
	local out: { [string]: any } = table.clone(base)
	if overrides then
		for k, v in overrides do
			if k ~= "emitters" then
				out[k] = v
			end
		end
		local per = overrides.emitters and overrides.emitters[emitterName]
		if per then
			for k, v in per do
				out[k] = v
			end
		end
	end
	return out :: EmitterSpec
end

function M.attach(name: string, target: BasePart | Attachment, overrides: { [string]: any }?): Attachment
	local recipe = Recipes[name]
	assert(recipe, ("ParticleRecipes: unknown recipe '%s'. Known: %s"):format(name, table.concat(M.list(), ", ")))

	local holder: Attachment
	if target:IsA("Attachment") then
		holder = target
	else
		holder = Instance.new("Attachment")
		holder.Name = "FX_" .. name
		holder:SetAttribute(ATTR, name)
		holder:SetAttribute(OWNED_ATTR, true)
		holder.Parent = target
	end

	local rateCap = recipe.burst and 0 or recipe.maxRate
	for emitterName, spec in recipe.emitters do
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = emitterName
		applySpec(emitter, mergedSpec(spec, emitterName, overrides), rateCap)
		if recipe.burst then
			emitter.Enabled = false
		end
		emitter:SetAttribute(ATTR, name)
		emitter:SetAttribute(OWNED_ATTR, true)
		emitter.Parent = holder
	end
	return holder
end

function M.burst(holder: Instance, count: number?)
	for _, child in holder:GetChildren() do
		if child:IsA("ParticleEmitter") and child:GetAttribute(OWNED_ATTR) == true then
			local recipeName = child:GetAttribute(ATTR)
			local recipe = if typeof(recipeName) == "string" then Recipes[recipeName] else nil
			local n = count or (recipe and recipe.burstCount) or 8
			child:Emit(n)
		end
	end
end

-- Transient burst at a world position; the attachment is destroyed after `lifetime` seconds.
function M.burstAt(name: string, position: Vector3, lifetime: number?): Attachment
	local holder = Instance.new("Attachment")
	holder.Name = "FX_" .. name .. "_transient"
	holder:SetAttribute(ATTR, name)
	holder:SetAttribute(OWNED_ATTR, true)
	holder.WorldPosition = position
	holder.Parent = workspace.Terrain
	local built = M.attach(name, holder)
	M.burst(built)
	Debris:AddItem(holder, lifetime or 2)
	return holder
end

-- Include the target itself, but never destroy a borrowed attachment or unrelated children.
-- A module-owned holder with unrelated children is retained until it is empty.
function M.detach(target: Instance)
	local instances = target:GetDescendants()
	table.insert(instances, 1, target)
	for _, d in instances do
		if d:IsA("ParticleEmitter") and d:GetAttribute(OWNED_ATTR) == true then
			d:Destroy()
		end
	end
	for index = #instances, 1, -1 do
		local d = instances[index]
		if d:IsA("Attachment") and d:GetAttribute(OWNED_ATTR) == true and #d:GetChildren() == 0 then
			d:Destroy()
		end
	end
end

return M
