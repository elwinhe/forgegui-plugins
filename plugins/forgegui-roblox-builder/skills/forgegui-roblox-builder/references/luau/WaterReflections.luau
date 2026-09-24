--!strict
-- WaterReflections: water reflections through Roblox's own terrain water.
--   local Water = require(ReplicatedStorage.WaterReflections)
--   Water.setLevel(1)   -- 0 off (a faint sky sheen), 0.5 low, 1 high
--   Water.clear()       -- puts the place's own WaterReflectance back
--
-- Terrain water already reflects the scene on screen and ripples it with the
-- waves; the only setting worth exposing is how strongly. Levels map to
-- Terrain.WaterReflectance 0.08 / 0.3 / 0.5. High stays at 0.5: stronger turns
-- nearby trunks and pillars into mirror images across half a pond at grazing
-- angles.
--
-- Tried and retired: a planar mirror (a ViewportFrame of copied scenery laid on
-- the water). Side by side, the native reflection put every pillar in the right
-- place with natural ripples, while the mirror added a hard edge along the far
-- bank, dropped some reflections and cost frame time. Worse, moving any part
-- inside a ViewportFrame re-prepares every mesh in it: one part moved per frame
-- beside ~150 heavy meshes cost 250 ms a frame. Do not rebuild it.
--
-- Ownership: nothing is created. Terrain.WaterReflectance is borrowed; its value
-- is recorded once as ForgeGUIPrior_WaterReflectance and clear() restores it.
-- Terrain carries ForgeGUIWaterReflections = <level> while a level is applied.
-- Safe to call from a LocalScript (per-player setting) or in Edit (baked).

local Workspace = game:GetService("Workspace")

local WaterReflections = {}

local OWNED_ATTR = "ForgeGUIWaterReflections"
local PRIOR_KEY = "ForgeGUIPrior_WaterReflectance"
local REFLECTANCE = { off = 0.08, low = 0.3, high = 0.5 }
WaterReflections.REFLECTANCE = REFLECTANCE

function WaterReflections.reflectanceFor(level: number): number
	if level ~= level or level <= 0.01 then
		return REFLECTANCE.off
	end
	return if level < 0.75 then REFLECTANCE.low else REFLECTANCE.high
end

-- Returns the reflectance applied. Idempotent; the first call records the prior.
function WaterReflections.setLevel(level: number): number
	local terrain = Workspace.Terrain
	if terrain:GetAttribute(PRIOR_KEY) == nil then
		terrain:SetAttribute(PRIOR_KEY, terrain.WaterReflectance)
	end
	local wanted = WaterReflections.reflectanceFor(level)
	if math.abs(terrain.WaterReflectance - wanted) > 1e-3 then
		terrain.WaterReflectance = wanted
	end
	terrain:SetAttribute(OWNED_ATTR, math.clamp(if level == level then level else 0, 0, 1))
	return wanted
end

-- Returns false when no level was applied.
function WaterReflections.clear(): boolean
	local terrain = Workspace.Terrain
	local prior = terrain:GetAttribute(PRIOR_KEY)
	if terrain:GetAttribute(OWNED_ATTR) == nil and prior == nil then
		return false
	end
	if type(prior) == "number" then
		terrain.WaterReflectance = prior
	end
	terrain:SetAttribute(PRIOR_KEY, nil)
	terrain:SetAttribute(OWNED_ATTR, nil)
	return true
end

return WaterReflections
