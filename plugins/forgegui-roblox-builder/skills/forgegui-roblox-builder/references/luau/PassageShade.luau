--!strict
-- PassageShade: baked shade for walk-through landmarks (gatehouses, arches,
-- tunnels, covered markets). Edit-time helper: run it once per model from the
-- command bar or execute_luau and save the place; the panels it lays replicate
-- like any other part.
--   local Shade = require(ServerStorage.PassageShade)   -- or paste the body
--   print(Shade.apply(workspace.World.Gatehouse))       -- measure, lay panels
--   Shade.clear(workspace.World.Gatehouse)              -- remove only its panels
--
-- Why: Roblox's sky light hardly dims inside a narrow roofed passage (measured:
-- adding hidden occluding geometry changed nothing), and a low sun rakes straight
-- down it, so the inside reads as bright as the street. Soft dark gradient panels
-- on the floor, both inner walls and the ceiling fix it: darkest mid-passage,
-- fading toward the lit ends. Target: the covered floor reads 40-55 % darker
-- than open ground. Recorded with these defaults on a 30-stud gatehouse at noon:
-- the roofed floor went from 51 % to 58 % darker than the open ground beside it;
-- lower `strength` if a passage already in sun shadow goes past the target.
-- GlobalIllumination's sky-openness probe darkens the ambient while the camera
-- is inside; this helper is what makes the passage read darker from outside.
--
-- Geometry: by default the passage runs along the model's bounding-box X, centred
-- on the box, floor at the box base. `measure` raycasts against the model (and
-- Terrain for the floor) to find the floor, the ceiling and the inner walls;
-- anything it cannot find falls back to box fractions and is listed in the
-- report's `guessed`. Pass `frame` (floor centre, X along the passage) and any of
-- `length`, `halfWidth`, `ceiling` to override.
--
-- Texture: a soft black-alpha gradient. With `texture = "rbxassetid://<id>"`
-- each panel is a Decal (smooth fade on both axes; make the PNG with
-- `python references/tools/make_gradient.py --shape rect shade.png` and upload
-- it). Without one each panel is a SurfaceGui Frame with a UIGradient fading
-- along the passage: no asset needed, fades on one axis only.
--
-- Ownership: every panel is a Part carrying ForgeGUIPassageShade = true, parented
-- to the model; clear() destroys only those. apply() clears first, so it is
-- idempotent. Panels are anchored, CanCollide/CanQuery/CanTouch/CastShadow off.

local Workspace = game:GetService("Workspace")

local PassageShade = {}

export type Options = {
	frame: CFrame?, -- passage floor centre, X along the passage (default: box base centre)
	length: number?, -- default 0.9 x the box's X size
	halfWidth: number?, -- default measured, else 0.25 x the box's Z size
	ceiling: number?, -- height above the floor; default measured, else 0.56 x box height
	texture: string?, -- rbxassetid:// of a soft black-alpha PNG; nil = SurfaceGui gradient
	strength: number?, -- opacity multiplier, default 1
}
export type Measure = { frame: CFrame, length: number, halfWidth: number, ceiling: number, guessed: { string } }
export type Report = { frame: CFrame, length: number, halfWidth: number, ceiling: number, guessed: { string }, panels: number }

local OWNED_ATTR = "ForgeGUIPassageShade"
-- Opacity per surface (1 - Decal.Transparency): floor 0.7, walls 0.6, ceiling 0.65.
local OPACITY = { floor = 0.7, wall = 0.6, ceiling = 0.65 }
local PROBE_HEIGHT = 1.5 -- rays start this far above the floor, inside the passage
local FLOOR_LIFT = 0.08 -- above the floor, clear of z-fighting
local THIN = 0.05

local function castWithin(model: Model, from: Vector3, direction: Vector3, withTerrain: boolean): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = if withTerrain then { model, Workspace.Terrain } else { model }
	params.IgnoreWater = true
	return Workspace:Raycast(from, direction, params)
end

local function sideDistance(model: Model, frame: CFrame, height: number, sign: number, reach: number): number?
	local from = frame:PointToWorldSpace(Vector3.new(0, height, 0))
	local hit = castWithin(model, from, frame:VectorToWorldSpace(Vector3.new(0, 0, sign * reach)), false)
	return if hit then (hit.Position - from).Magnitude else nil
end

local function measureWidth(model: Model, frame: CFrame, ceiling: number, reach: number): number?
	local nearest: number? = nil
	for _, height in { 2, ceiling * 0.5 } do
		for _, sign in { 1, -1 } do
			local d = sideDistance(model, frame, height, sign, reach)
			if d and (nearest == nil or d < nearest) then
				nearest = d
			end
		end
	end
	return nearest
end

-- Floor, ceiling and inner walls by raycast; box fractions where nothing is hit.
function PassageShade.measure(model: Model, options: Options?): Measure
	local given: Options = options or {}
	local cf, size = model:GetBoundingBox()
	local frame = given.frame or cf * CFrame.new(0, -size.Y / 2, 0)
	local guessed: { string } = {}
	local start = frame:PointToWorldSpace(Vector3.new(0, PROBE_HEIGHT, 0))
	local floorHit = castWithin(model, start, frame:VectorToWorldSpace(Vector3.new(0, -PROBE_HEIGHT - 2, 0)), true)
	if floorHit then
		frame += frame.UpVector * (floorHit.Position - frame.Position):Dot(frame.UpVector)
	end
	local ceiling = given.ceiling
	if not ceiling then
		local up = castWithin(model, start, frame.UpVector * size.Y, false)
		if up then
			ceiling = (up.Position - frame.Position):Dot(frame.UpVector)
		else
			ceiling = size.Y * 0.56
			table.insert(guessed, "ceiling")
		end
	end
	local ceilingHeight: number = ceiling :: number
	local halfWidth = given.halfWidth or measureWidth(model, frame, ceilingHeight, size.Z)
	if not halfWidth then
		halfWidth = size.Z * 0.25
		table.insert(guessed, "halfWidth")
	end
	return {
		frame = frame,
		length = given.length or size.X * 0.9,
		halfWidth = halfWidth :: number,
		ceiling = ceilingHeight,
		guessed = guessed,
	}
end

-- Panels ---------------------------------------------------------------------------------------

local function gradientGui(part: Part, face: Enum.NormalId, opacity: number)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.CanvasSize = Vector2.new(256, 64)
	gui.LightInfluence = 1
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.new(0, 0, 0)
	fill.BorderSizePixel = 0
	local gradient = Instance.new("UIGradient")
	local darkest = 1 - opacity
	local shoulder = darkest + (1 - darkest) * 0.35
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, shoulder),
		NumberSequenceKeypoint.new(0.5, darkest),
		NumberSequenceKeypoint.new(0.7, shoulder),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = fill
	fill.Parent = gui
	gui.Parent = part
end

type Panel = { size: Vector3, offset: Vector3, face: Enum.NormalId, opacity: number }

local function lay(model: Model, frame: CFrame, spec: Panel, texture: string?)
	local part = Instance.new("Part")
	part.Name = "ForgeGUI_PassageShade"
	part:SetAttribute(OWNED_ATTR, true)
	part.Size = spec.size
	part.CFrame = frame * CFrame.new(spec.offset)
	part.Transparency = 1
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.CastShadow = false
	if texture then
		local decal = Instance.new("Decal")
		decal.Texture = texture
		decal.Face = spec.face
		decal.Color3 = Color3.new(0, 0, 0)
		decal.Transparency = 1 - spec.opacity
		decal.Parent = part
	else
		gradientGui(part, spec.face, spec.opacity)
	end
	part.Parent = model
end

-- Floor wider than the passage (it runs under the wall bases), walls just inside
-- the inner faces, ceiling just under the roof.
local function panels(m: Measure, k: number): { Panel }
	local length, w, h = m.length, m.halfWidth, m.ceiling
	local function o(value: number): number
		return math.min(value * k, 0.95)
	end
	return {
		{ size = Vector3.new(length, THIN, w * 2.5), offset = Vector3.new(0, FLOOR_LIFT, 0), face = Enum.NormalId.Top, opacity = o(OPACITY.floor) },
		{ size = Vector3.new(length * 0.9, h, THIN), offset = Vector3.new(0, h / 2, w - THIN), face = Enum.NormalId.Front, opacity = o(OPACITY.wall) },
		{ size = Vector3.new(length * 0.9, h, THIN), offset = Vector3.new(0, h / 2, -w + THIN), face = Enum.NormalId.Back, opacity = o(OPACITY.wall) },
		{ size = Vector3.new(length * 0.85, THIN, w * 2.3), offset = Vector3.new(0, h - THIN, 0), face = Enum.NormalId.Bottom, opacity = o(OPACITY.ceiling) },
	}
end

-- Lays floor, wall and ceiling panels. Returns what it measured and laid.
function PassageShade.apply(model: Model, options: Options?): Report
	assert(typeof(model) == "Instance" and model:IsA("Model"), "PassageShade.apply: pass a Model")
	PassageShade.clear(model)
	local given: Options = options or {}
	local m = PassageShade.measure(model, given)
	local list = panels(m, math.clamp(given.strength or 1, 0, 1.4))
	for _, spec in list do
		lay(model, m.frame, spec, given.texture)
	end
	return { frame = m.frame, length = m.length, halfWidth = m.halfWidth, ceiling = m.ceiling, guessed = m.guessed, panels = #list }
end

-- Destroys only the panels this module laid. Returns how many.
function PassageShade.clear(model: Instance): number
	local removed = 0
	for _, d in model:GetDescendants() do
		if d:GetAttribute(OWNED_ATTR) == true then
			d:Destroy()
			removed += 1
		end
	end
	return removed
end

return PassageShade
