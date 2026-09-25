--!strict
-- One shared ModuleScript per client, beside ColourGrade and GlobalIllumination.
-- Owns only the four colour properties while a layer is registered.
-- External writes are base inputs; composition is always base -> GI -> grade.
local Lighting = game:GetService("Lighting")
local M = {}
export type Colours = { [string]: Color3 }
local PROPERTIES = { "Ambient", "OutdoorAmbient", "ColorShift_Top", "ColorShift_Bottom" }
local BASE = "ForgeGUILightingBase_"
local OUTPUT = "ForgeGUILightingOutput_"
local INPUT = "ForgeGUILightingInput_"
local base: Colours? = nil
local written: Colours = {}
local gi: ((Colours) -> Colours)? = nil
local shadow: Color3? = nil
local highlight: Color3? = nil

local function read(): Colours
	local result: Colours = {}
	for _, property in PROPERTIES do
		result[property] = (Lighting :: any)[property]
	end
	return result
end

local function sync(): Colours
	local current = read()
	local b = base
	if not b then
		b = current
		base = b
	else
		for _, property in PROPERTIES do
			-- Compare with actual engine readback, not the requested colour.
			-- Even a tiny external change is legitimate; no epsilon hides it.
			local input = Lighting:GetAttribute(INPUT .. property)
			if current[property] ~= written[property] or (input ~= nil and current[property] == input) then
				b[property] = current[property]
			end
			Lighting:SetAttribute(INPUT .. property, nil)
		end
	end
	return b
end

local function multiply(a: Color3, b: Color3): Color3
	return Color3.new(math.clamp(a.R * b.R, 0, 1), math.clamp(a.G * b.G, 0, 1), math.clamp(a.B * b.B, 0, 1))
end

local function compose(b: Colours)
	local output = table.clone(b)
	if gi then
		output = gi(output)
	end
	if shadow then
		output.Ambient = multiply(output.Ambient, shadow)
		output.OutdoorAmbient = multiply(output.OutdoorAmbient, shadow)
	end
	if highlight then
		output.ColorShift_Top = multiply(output.ColorShift_Top, highlight)
	end
	local active = gi ~= nil or shadow ~= nil or highlight ~= nil
	for _, property in PROPERTIES do
		(Lighting :: any)[property] = output[property]
		written[property] = (Lighting :: any)[property]
		-- Preset prior capture consults these only if its live value matches
		-- this output. An intervening external edit remains its own baseline.
		Lighting:SetAttribute(BASE .. property, if active then b[property] else nil)
		Lighting:SetAttribute(OUTPUT .. property, if active then written[property] else nil)
	end
	if not active then
		base = nil
		table.clear(written)
	end
end

function M.getBase(): Colours
	return table.clone(sync())
end

-- Explicit base input for continuous day/night scripts (including GI.getBase).
-- This also expresses a write equal to the visible output, which polling cannot detect.
function M.setBase(values: Colours)
	local b = sync()
	for property, value in values do
		assert(table.find(PROPERTIES, property) ~= nil, "unsupported Lighting base property: " .. property)
		assert(typeof(value) == "Color3", "Lighting base must be Color3")
	end
	for property, value in values do
		b[property] = value
	end
	compose(b)
end

function M.setGI(transform: ((Colours) -> Colours)?)
	local b = sync()
	gi = transform
	compose(b)
end

function M.setGrade(shadowTone: Color3?, highlightTone: Color3?)
	local b = sync()
	shadow, highlight = shadowTone, highlightTone
	compose(b)
end

return M
