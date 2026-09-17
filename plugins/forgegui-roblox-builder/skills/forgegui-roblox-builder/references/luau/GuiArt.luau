--!strict
-- Places generated GUI art so it never fights the frame it sits in.
--
-- Every layering fault seen in generated UI came from one of three mistakes, and
-- each rule below closes one of them structurally rather than by care:
--   1. A Roblox background, corner or stroke drawn under art that already has its
--      own shape. Art elements get none, and `conflicts` reports any found.
--   2. Art stretched to an aspect it was not drawn at. Plain art is fitted at its
--      recorded native aspect; panels that must resize are sliced.
--   3. A slice centre guessed by eye, which stretches a crest or a gem. Slice
--      metadata comes from `references/tools/slice_metadata.py`, measured on the
--      art itself.

local GuiArt = {}

export type Art = {
	id: string,
	aspect: number,
	-- Native pixel size and slice centre {x0, y0, x1, y1}, both from slice_metadata.py.
	size: { number }?,
	sliceCenter: { number }?,
}

export type Registry = { [string]: Art }

local ASSET_PATTERN = "^rbxassetid://%d+$"
local DECORATION_CLASSES = { "UICorner", "UIStroke", "UIGradient" }

local function isPositiveNumber(value: any): boolean
	return type(value) == "number" and value == value and value > 0 and value < math.huge
end

-- Returns a list of problems; an empty list means the registry is usable. A
-- mistyped id renders as a blank element, and a bad slice centre renders as a
-- smear, both silently -- so they are caught here instead.
function GuiArt.validate(registry: Registry): { string }
	local problems = {}
	for name, art in pairs(registry) do
		if type(art) ~= "table" then
			table.insert(problems, `{name}: not a table`)
			continue
		end
		if type(art.id) ~= "string" or not string.match(art.id, ASSET_PATTERN) then
			table.insert(problems, `{name}: id must look like rbxassetid://123`)
		end
		if not isPositiveNumber(art.aspect) then
			table.insert(problems, `{name}: aspect must be a positive number`)
		end
		if art.sliceCenter ~= nil then
			local size, center = art.size, art.sliceCenter
			if type(size) ~= "table" or not isPositiveNumber(size[1]) or not isPositiveNumber(size[2]) then
				table.insert(problems, `{name}: sliceCenter needs size = \{width, height\}`)
			elseif type(center) ~= "table" or #center ~= 4 then
				table.insert(problems, `{name}: sliceCenter must be \{x0, y0, x1, y1\}`)
			else
				local x0, y0, x1, y1 = center[1], center[2], center[3], center[4]
				if not (0 <= x0 and x0 < x1 and x1 <= size[1] and 0 <= y0 and y0 < y1 and y1 <= size[2]) then
					table.insert(problems, `{name}: sliceCenter lies outside the art or is inverted`)
				end
			end
		end
	end
	table.sort(problems)
	return problems
end

-- What already draws on `object`: a visible background or decoration that
-- generated art placed on or inside it would stack on top of. Read this before
-- decorating existing UI rather than after the screenshot shows two shapes.
function GuiArt.conflicts(object: GuiObject): { string }
	local found = {}
	if object.BackgroundTransparency < 1 then
		table.insert(found, "visible background")
	end
	for _, className in ipairs(DECORATION_CLASSES) do
		if object:FindFirstChildOfClass(className) then
			table.insert(found, className)
		end
	end
	for _, child in ipairs(object:GetChildren()) do
		if (child:IsA("ImageLabel") or child:IsA("ImageButton")) and (child :: ImageLabel).Image ~= "" then
			table.insert(found, "existing image " .. child.Name)
		end
	end
	return found
end

local function strip(object: GuiObject)
	object.BackgroundTransparency = 1
	object.BorderSizePixel = 0
	for _, className in ipairs(DECORATION_CLASSES) do
		local decoration = object:FindFirstChildOfClass(className)
		while decoration do
			decoration:Destroy()
			decoration = object:FindFirstChildOfClass(className)
		end
	end
end

local function apply(object: any, props: { [string]: any }?)
	local parent = nil
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			object[key] = value
		end
	end
	return parent
end

-- The SliceScale that keeps a sliced panel's corners in proportion: art pixels
-- scale by the tighter of the two axes. That alone guarantees the fixed corners
-- and edges fit, because they are a part of the art's size on each axis.
function GuiArt.sliceScale(art: Art, absoluteSize: Vector2): number
	local size = art.size
	if not size then
		return 1
	end
	return math.max(0.01, math.min(absoluteSize.X / size[1], absoluteSize.Y / size[2]))
end

export type Placer = {
	image: (name: string, props: { [string]: any }?) -> ImageLabel,
	button: (name: string, props: { [string]: any }?) -> ImageButton,
	panel: (name: string, props: { [string]: any }?) -> ImageLabel,
}

function GuiArt.new(registry: Registry): Placer
	local problems = GuiArt.validate(registry)
	assert(#problems == 0, "GuiArt registry: " .. table.concat(problems, "; "))

	local function lookup(name: string): Art
		local art = registry[name]
		assert(art, "GuiArt: no art named " .. tostring(name))
		return art
	end

	-- Plain art: fitted at its native aspect, so it can never be stretched.
	local function place(object: any, name: string, props: { [string]: any }?)
		local art = lookup(name)
		object.Image = art.id
		object.ScaleType = Enum.ScaleType.Fit
		strip(object)
		local parent = apply(object, props)
		strip(object)
		local constraint = Instance.new("UIAspectRatioConstraint")
		constraint.AspectRatio = art.aspect
		constraint.Parent = object
		object.Parent = parent
		return object
	end

	local placer = {}

	function placer.image(name: string, props: { [string]: any }?): ImageLabel
		return place(Instance.new("ImageLabel"), name, props)
	end

	-- AutoButtonColor stays off: art has no background to tint, so press feedback
	-- belongs to motion (scale), not to a colour change on an invisible frame.
	function placer.button(name: string, props: { [string]: any }?): ImageButton
		local button = Instance.new("ImageButton")
		button.AutoButtonColor = false
		return place(button, name, props)
	end

	-- A window background that takes any size. Uses the measured slice centre when
	-- there is one, and falls back to fitted art (never stretched) when there is not.
	function placer.panel(name: string, props: { [string]: any }?): ImageLabel
		local art = lookup(name)
		if not art.sliceCenter then
			return placer.image(name, props)
		end
		local label = Instance.new("ImageLabel")
		label.Image = art.id
		label.ScaleType = Enum.ScaleType.Slice
		local center = art.sliceCenter :: { number }
		label.SliceCenter = Rect.new(center[1], center[2], center[3], center[4])
		strip(label)
		local parent = apply(label, props)
		strip(label)
		local function rescale()
			label.SliceScale = GuiArt.sliceScale(art, label.AbsoluteSize)
		end
		label:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
		rescale()
		label.Parent = parent
		return label
	end

	return placer :: any
end

return GuiArt
