-- Appended to the reviewed ParticleRecipes source in place of its final `return M`.
-- Run the generated standalone regression through Studio MCP in an owned test place.
local FX = M
local HttpService = game:GetService("HttpService")
local checks = {}
local scratch = Instance.new("Folder")
scratch.Name = "ForgeGUIParticleOwnershipRegression_" .. HttpService:GenerateGUID(false)
scratch.Parent = workspace
local transient: Attachment? = nil

local function check(condition: boolean, label: string)
	assert(condition, label)
	table.insert(checks, label)
end

local function ownedEmitterCount(target: Instance): number
	local count = 0
	for _, child in target:GetDescendants() do
		if child:IsA("ParticleEmitter") and child:GetAttribute("ForgeGUIRecipeOwned") == true then
			count += 1
		end
	end
	return count
end

local ok, failure = xpcall(function()
	local part = Instance.new("Part")
	part.Anchored = true
	part.Transparency = 1
	part.CanCollide = false
	part.Position = Vector3.new(0, -10000, 0)
	part.Parent = scratch
	local borrowed = Instance.new("Attachment")
	borrowed.Name = "CallerOwnedMuzzle"
	borrowed:SetAttribute("ForgeGUIRecipe", "caller-sentinel")
	borrowed:SetAttribute("CallerMetadata", 42)
	borrowed.Parent = part
	local unrelated = Instance.new("ParticleEmitter")
	unrelated.Name = "CallerOwnedEmitter"
	unrelated.Enabled = false
	unrelated.Rate = 0
	unrelated:SetAttribute("ForgeGUIRecipe", "unrelated-sentinel")
	unrelated.Parent = borrowed
	local unrelatedChild = Instance.new("Folder")
	unrelatedChild.Name = "CallerOwnedChild"
	unrelatedChild.Parent = borrowed
	local beam = Instance.new("Beam")
	beam.Attachment0 = borrowed
	beam.Parent = part

	local handle = FX.attach("muzzle_flash", borrowed)
	check(handle == borrowed, "attach returns the supplied attachment")
	check(borrowed:GetAttribute("ForgeGUIRecipe") == "caller-sentinel", "borrowed recipe attribute preserved")
	check(borrowed:GetAttribute("CallerMetadata") == 42, "borrowed custom metadata preserved")
	check(borrowed:GetAttribute("ForgeGUIRecipeOwned") == nil, "borrowed attachment is not marked owned")
	check(ownedEmitterCount(borrowed) == 2, "muzzle recipe creates two owned emitters")
	FX.burst(handle, 0)
	FX.detach(borrowed)
	check(ownedEmitterCount(borrowed) == 0, "detach on borrowed target removes owned emitters")
	check(borrowed.Parent == part, "detach preserves borrowed target")
	check(unrelated.Parent == borrowed, "detach preserves unrelated emitter")
	check(unrelatedChild.Parent == borrowed, "detach preserves unrelated child")
	check(beam.Attachment0 == borrowed, "detach preserves external attachment reference")
	check(borrowed:GetAttribute("ForgeGUIRecipe") == "caller-sentinel", "detach preserves caller recipe metadata")

	for cycle = 1, 3 do
		FX.attach("pickup_sparkle", borrowed, { rate = 0 })
		FX.attach("pickup_sparkle", borrowed, { rate = 0 })
		check(ownedEmitterCount(borrowed) == 2, "repeated attach adds exactly two emitters, cycle " .. cycle)
		FX.detach(part)
		check(ownedEmitterCount(part) == 0, "parent detach clears all owned emitters, cycle " .. cycle)
		check(borrowed.Parent == part and unrelated.Parent == borrowed, "repeated detach preserves borrowed objects, cycle " .. cycle)
	end

	local owned = FX.attach("pickup_sparkle", part, { rate = 0 })
	check(owned:GetAttribute("ForgeGUIRecipeOwned") == true, "created holder is marked owned")
	FX.detach(owned)
	check(owned.Parent == nil, "detach includes an empty owned target")
	check(ownedEmitterCount(part) == 0, "owned-target detach leaves no recipe emitters")

	local retained = FX.attach("pickup_sparkle", part, { rate = 0 })
	local foreignChild = Instance.new("Folder")
	foreignChild.Name = "CallerAddedChild"
	foreignChild.Parent = retained
	FX.detach(part)
	check(retained.Parent == part and foreignChild.Parent == retained, "owned holder with unrelated child is retained")
	check(ownedEmitterCount(retained) == 0, "retained holder has no recipe emitters")
	foreignChild:Destroy()
	FX.detach(part)
	check(retained.Parent == nil, "retained owned holder is removed once empty")

	local legacy = Instance.new("Attachment")
	legacy:SetAttribute("ForgeGUIRecipe", "pickup_sparkle")
	legacy.Parent = part
	FX.detach(part)
	check(legacy.Parent == part, "legacy unowned attachment is not claimed")

	transient = FX.burstAt("footstep_puff", part.Position, 1)
	check(transient:GetAttribute("ForgeGUIRecipeOwned") == true, "transient holder is marked owned")
	FX.detach(transient)
	check(transient.Parent == nil, "explicit detach cleans transient holder")
	check(borrowed.Parent == part and unrelatedChild.Parent == borrowed, "final borrowed objects remain intact")
end, debug.traceback)

if transient then transient:Destroy() end
scratch:Destroy()
assert(ok, tostring(failure))
return HttpService:JSONEncode({ passed = #checks, failed = 0, checks = checks, temporaryInstancesRemoved = scratch.Parent == nil })
