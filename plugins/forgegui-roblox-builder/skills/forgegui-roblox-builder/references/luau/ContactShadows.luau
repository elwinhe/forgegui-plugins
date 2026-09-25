--!strict
-- ContactShadows: soft darkening where props, buildings and characters meet the
-- ground, client side. Roblox has no ambient occlusion, so without it everything
-- looks set down on the ground rather than standing in it.
--   local CS = require(ReplicatedStorage.ContactShadows)
--   CS.start({ roots = { workspace.World }, kinds = { crate = { shape = "round" } },
--              textures = { round = "rbxassetid://<id>", rect = "rbxassetid://<id>" } })
--   CS.setEnabled(false) / CS.stop()
--
-- - Static grounders get a soft blob on the ground under their footprint: a
--   rounded rectangle for buildings and walls, a round pool for the rest. Trees
--   get one sized to the trunk, not the crown (spread 0.3). What counts:
--   * anything tagged `ForgeGUIContactShadow` (CollectionService), with optional
--     attributes ContactShadowShape ("rect" | "round"), ContactShadowSpread and
--     ContactShadowStrength;
--   * Models under `roots` whose name, minus a trailing _<n> copy suffix, is a key
--     of `kinds` ("house_small_3" -> "house_small").
--   Only the nearest `maxStatic` within `range` get one, re-chosen every 0.5 s,
--   from a pool of decal parts.
-- - Characters (every player, plus Models with a Humanoid under
--   `characterFolders`) get a small round blob that follows them each frame and
--   fades as they jump.
-- Textures: soft radial / rounded-rectangle black-alpha PNGs. Make them with
-- `python references/tools/make_gradient.py --shape round|rect out.png` and
-- upload them. With no texture ids it falls back to a SurfaceGui of five nested
-- rounded frames (a stepped radial gradient that needs no asset); the texture
-- route looks smoother and costs less, so prefer it for shipping.
--
-- Ownership: everything lives in one Folder under Workspace carrying
-- ForgeGUIContactShadows = true; stop() destroys that folder only. Nothing it
-- does not own is modified. Blob parts have CanQuery = false, so raycasts
-- (GlobalIllumination, weapons) pass through them.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ContactShadows = {}

export type Shape = "rect" | "round"
export type Kind = { shape: Shape?, spread: number?, strength: number? }
export type Options = {
	tag: string?, -- CollectionService tag for grounders (default "ForgeGUIContactShadow")
	roots: { Instance }?, -- containers watched for Models named in `kinds`
	kinds: { [string]: Kind }?, -- by name, minus a trailing _<n>
	characterFolders: { Instance }?, -- NPC / creature containers; players are always included
	textures: { round: string?, rect: string? }?, -- rbxassetid:// ids; nil = SurfaceGui fallback
	ground: { Instance }?, -- what the blob lies on (default { Workspace.Terrain })
	range: number?, -- default 170 studs from the camera focus
	maxStatic: number?, -- default 140
	maxCharacters: number?, -- default 24
	characterRange: number?, -- default 90
	characterSize: number?, -- default 3.6 studs across
	characterStrength: number?, -- default 0.55 opacity
	getFocus: (() -> Vector3)?,
	manual: boolean?, -- true: no Heartbeat connection; call CS.step(dt) yourself
}

type Blob = { part: Part, decal: Decal?, rings: { Frame }?, shape: Shape? }
type Grounded = { instance: Instance, kind: Kind, blob: Blob? }
type Pick = { entry: Grounded, distance: number }

local OWNED_ATTR = "ForgeGUIContactShadows"
local DEFAULT_TAG = "ForgeGUIContactShadow"
local PICK_STEP = 0.5
local LEAVE_MARGIN = 20 -- hysteresis: an active blob stays until this much further out
local LIFT = 0.06 -- above the ground, clear of z-fighting
local RINGS = 5
local DEFAULT_SPREAD, DEFAULT_STRENGTH = 1.3, 0.5

local opts: Options = {}
local grounded: { [Instance]: Grounded } = {}
local active: { Grounded } = {}
local pool: { Blob } = {}
local characterBlobs: { [Model]: Blob } = {}
local connections: { RBXScriptConnection } = {}
local folder: Folder? = nil
local enabled = true
local sincePick = PICK_STEP
local running = false

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.IgnoreWater = false

local NONE: { Instance } = {}

local function num(value: any, default: number): number
	return if type(value) == "number" then value else default
end

local function kitName(name: string): string
	return (string.gsub(name, "_%d+$", ""))
end

-- Blobs -------------------------------------------------------------------------------------

-- Five nested rounded frames: each adds `a` opacity, so the centre reaches the
-- strength and the edge fades out in steps. No asset needed.
local function makeRings(part: Part): { Frame }
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.CanvasSize = Vector2.new(64, 64)
	gui.LightInfluence = 1
	gui.Parent = part
	local rings: { Frame } = {}
	local parent: Instance = gui
	for i = 1, RINGS do
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Size = if i == 1 then UDim2.fromScale(1, 1) else UDim2.fromScale(0.78, 0.78)
		frame.BackgroundColor3 = Color3.new(0, 0, 0)
		frame.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = frame
		frame.Parent = parent
		parent = frame
		table.insert(rings, frame)
	end
	return rings
end

local function newBlob(): Blob
	local part = Instance.new("Part")
	part.Name = "ForgeGUI_ContactShadow"
	part.Anchored = true
	part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = false, false, false, false
	part.Transparency = 1
	part.Size = Vector3.new(4, 0.05, 4)
	local textures = opts.textures
	if textures and (textures.round or textures.rect) then
		local decal = Instance.new("Decal")
		decal.Face = Enum.NormalId.Top
		decal.Color3 = Color3.new(0, 0, 0)
		decal.Parent = part
		return { part = part, decal = decal }
	end
	return { part = part, rings = makeRings(part) }
end

local function takeBlob(): Blob
	local blob = table.remove(pool) or newBlob()
	blob.part.Parent = folder
	return blob
end

local function giveBack(blob: Blob)
	blob.part.Parent = nil
	table.insert(pool, blob)
end

local function style(blob: Blob, shape: Shape, strength: number)
	local decal, rings = blob.decal, blob.rings
	if decal then
		local textures: { round: string?, rect: string? } = opts.textures or {}
		local texture = if shape == "rect" then textures.rect or textures.round else textures.round or textures.rect
		decal.Texture = texture or ""
		decal.Transparency = 1 - strength
	elseif rings then
		local step = 1 - (1 - math.clamp(strength, 0, 0.99)) ^ (1 / RINGS)
		for _, frame in rings do
			frame.BackgroundTransparency = 1 - step
			local corner = frame:FindFirstChildOfClass("UICorner")
			if corner and blob.shape ~= shape then
				corner.CornerRadius = UDim.new(if shape == "rect" then 0.22 else 0.5, 0)
			end
		end
	end
	blob.shape = shape
end

-- Static grounders ------------------------------------------------------------------------

local function groundAt(position: Vector3, height: number): RaycastResult?
	return Workspace:Raycast(position + Vector3.new(0, height, 0), Vector3.new(0, -(height + 12), 0), groundParams)
end

local function bounds(instance: Instance): (CFrame, Vector3)
	if instance:IsA("Model") then
		return instance:GetBoundingBox()
	end
	local part = instance :: BasePart
	return part.CFrame, part.Size
end

local function layStatic(entry: Grounded)
	local cf, size = bounds(entry.instance)
	local baseY = cf.Y - size.Y / 2
	local hit = groundAt(Vector3.new(cf.X, baseY, cf.Z), size.Y * 0.5 + 4)
	local blob = entry.blob or takeBlob()
	entry.blob = blob
	local kind = entry.kind
	local shape: Shape = kind.shape or "round"
	local spread = num(kind.spread, DEFAULT_SPREAD)
	local _, yaw, _ = cf:ToEulerAnglesYXZ()
	local width, depth = size.X * spread, size.Z * spread
	if shape == "round" then
		local r = math.max(width, depth)
		width, depth = r, r
	end
	local y = if hit then hit.Position.Y else baseY
	blob.part.Size = Vector3.new(math.max(width, 1), 0.05, math.max(depth, 1))
	blob.part.CFrame = CFrame.new(cf.X, y + LIFT, cf.Z) * CFrame.Angles(0, yaw, 0)
	style(blob, shape, num(kind.strength, DEFAULT_STRENGTH))
end

local function release(entry: Grounded)
	local blob = entry.blob
	if blob then
		giveBack(blob)
		entry.blob = nil
	end
end

local function pickStatic(eye: Vector3)
	local range = num(opts.range, 170)
	local picks: { Pick } = {}
	for instance, entry in grounded do
		if not instance:IsDescendantOf(Workspace) then
			continue
		end
		-- The pivot is cheap; the bounding box is only measured when a blob is laid.
		local at = if instance:IsA("Model") then instance:GetPivot().Position else (instance :: BasePart).Position
		local d = (at - eye).Magnitude
		if d <= range + (if entry.blob then LEAVE_MARGIN else 0) then
			table.insert(picks, { entry = entry, distance = d })
		end
	end
	table.sort(picks, function(a: Pick, b: Pick)
		return a.distance < b.distance
	end)
	local keep: { [Grounded]: boolean } = {}
	for i = 1, math.min(#picks, num(opts.maxStatic, 140)) do
		keep[picks[i].entry] = true
	end
	for _, entry in active do
		if not keep[entry] then
			release(entry)
		end
	end
	table.clear(active)
	for entry in keep do
		if not entry.blob then
			layStatic(entry)
		end
		table.insert(active, entry)
	end
end

local function clearStatic()
	for _, entry in active do
		release(entry)
	end
	table.clear(active)
end

-- Characters ---------------------------------------------------------------------------------

local function characters(eye: Vector3): { Model }
	local list: { Model } = {}
	local limit, reach = num(opts.maxCharacters, 24), num(opts.characterRange, 90)
	local function consider(model: Instance)
		if #list >= limit or not (model:IsA("Model") and model:FindFirstChildOfClass("Humanoid")) then
			return
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - eye).Magnitude < reach then
			table.insert(list, model)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			consider(player.Character)
		end
	end
	local folders: { Instance } = opts.characterFolders or NONE
	for _, group in folders do
		for _, child in group:GetChildren() do
			consider(child)
		end
	end
	return list
end

local function layCharacter(model: Model): boolean
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local hit = groundAt(root.Position, 1)
	if not hit then
		return false
	end
	local blob = characterBlobs[model]
	if not blob then -- size once, not every frame
		local made = takeBlob()
		local size = num(opts.characterSize, 3.6)
		made.part.Size = Vector3.new(size, 0.05, size)
		characterBlobs[model] = made
		blob = made
	end
	local height = root.Position.Y - hit.Position.Y
	local fade = math.clamp(1 - (height - 3) / 10, 0, 1) -- a jump lifts it away
	blob.part.CFrame = CFrame.new(hit.Position + Vector3.new(0, LIFT, 0))
	style(blob, "round", num(opts.characterStrength, 0.55) * fade)
	return true
end

local function stepCharacters(eye: Vector3)
	local seen: { [Model]: boolean } = {}
	if enabled then
		for _, model in characters(eye) do
			if layCharacter(model) then
				seen[model] = true
			end
		end
	end
	for model, blob in characterBlobs do
		if not seen[model] then
			characterBlobs[model] = nil
			giveBack(blob)
		end
	end
end

-- Watching -----------------------------------------------------------------------------------

local function kindFromAttributes(instance: Instance): Kind
	local shape: Shape = if instance:GetAttribute("ContactShadowShape") == "rect" then "rect" else "round"
	return {
		shape = shape,
		spread = num(instance:GetAttribute("ContactShadowSpread"), DEFAULT_SPREAD),
		strength = num(instance:GetAttribute("ContactShadowStrength"), DEFAULT_STRENGTH),
	}
end

local function add(instance: Instance, kind: Kind)
	if not grounded[instance] and (instance:IsA("Model") or instance:IsA("BasePart")) then
		grounded[instance] = { instance = instance, kind = kind, blob = nil }
	end
end

local function remove(instance: Instance)
	local entry = grounded[instance]
	grounded[instance] = nil
	if entry then
		release(entry)
		local at = table.find(active, entry)
		if at then
			table.remove(active, at)
		end
	end
end

local function byName(instance: Instance)
	local kinds = opts.kinds
	if kinds and instance:IsA("Model") then
		local kind = kinds[kitName(instance.Name)]
		if kind then
			add(instance, kind)
		end
	end
end

local function watch()
	local tag = opts.tag or DEFAULT_TAG
	for _, instance in CollectionService:GetTagged(tag) do
		add(instance, kindFromAttributes(instance))
	end
	table.insert(connections, CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance: Instance)
		add(instance, kindFromAttributes(instance))
	end))
	table.insert(connections, CollectionService:GetInstanceRemovedSignal(tag):Connect(remove))
	local roots: { Instance } = opts.roots or NONE
	for _, root in roots do
		for _, d in root:GetDescendants() do
			byName(d)
		end
		table.insert(connections, root.DescendantAdded:Connect(byName))
		table.insert(connections, root.DescendantRemoving:Connect(remove))
	end
end

-- Lifecycle ----------------------------------------------------------------------------------

function ContactShadows.step(dt: number)
	if not running then
		return
	end
	local getter = opts.getFocus
	local camera = Workspace.CurrentCamera
	local eye = if getter then getter() elseif camera then camera.Focus.Position else nil
	if not eye then
		return
	end
	sincePick += dt
	if sincePick >= PICK_STEP then
		sincePick = 0
		if enabled then
			pickStatic(eye)
		else
			clearStatic()
		end
	end
	stepCharacters(eye)
end

function ContactShadows.setEnabled(on: boolean)
	enabled = on
	sincePick = PICK_STEP -- apply on the next step, not half a second later
end

-- Idempotent: a second start while running does nothing (stop first to change options).
function ContactShadows.start(options: Options?): boolean
	if running then
		return false
	end
	running = true
	opts = options or {}
	groundParams.FilterDescendantsInstances = opts.ground or { Workspace.Terrain }
	local made = Instance.new("Folder")
	made.Name = "ForgeGUI_ContactShadows"
	made:SetAttribute(OWNED_ATTR, true)
	made.Parent = Workspace
	folder = made
	sincePick = PICK_STEP
	watch()
	if not opts.manual then
		table.insert(connections, RunService.Heartbeat:Connect(ContactShadows.step))
	end
	return true
end

function ContactShadows.stop(): boolean
	if not running then
		return false
	end
	running = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	local owned = folder
	if owned and owned:GetAttribute(OWNED_ATTR) == true then
		owned:Destroy()
	end
	for _, blob in pool do
		blob.part:Destroy() -- pooled blobs sit outside the folder
	end
	folder = nil
	table.clear(grounded)
	table.clear(active)
	table.clear(pool)
	table.clear(characterBlobs)
	return true
end

function ContactShadows.stats(): { [string]: number }
	local watched, characterCount = 0, 0
	for _ in grounded do
		watched += 1
	end
	for _ in characterBlobs do
		characterCount += 1
	end
	return { watched = watched, active = #active, characters = characterCount, pooled = #pool }
end

return ContactShadows
