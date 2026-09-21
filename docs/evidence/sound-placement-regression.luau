-- Append this file to references/luau/SoundPlacement.luau in place of its final `return M`.
-- Run the combined source through Studio MCP execute_luau in Edit in an owned test place.
-- Uses real Instances for placement; playback spies test call sequencing without loading audio.
-- Asset IDs below are syntax-only fixtures. This does not test audibility or asset access.
local S = M
local HttpService = game:GetService("HttpService")
local checks = {}
local scratch = Instance.new("Folder")
scratch.Name = "ForgeGUISoundRegression_" .. HttpService:GenerateGUID(false)
scratch.Parent = workspace
local globalSound: Sound? = nil

local function check(condition: boolean, label: string)
	assert(condition, label)
	table.insert(checks, label)
end

local function rejects(callback: () -> (), label: string)
	local succeeded = pcall(callback)
	check(not succeeded, label)
end

local ok, failure = xpcall(function()
	local part = Instance.new("Part")
	part.Anchored = true
	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Position = Vector3.new(0, -10000, 0)
	part.Parent = scratch
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	local group = Instance.new("SoundGroup")
	group.Parent = scratch
	local options = { volume = 0, looped = true, minDistance = 8, maxDistance = 65, group = group }
	local sound = S.ensure(attachment, "loop", "1", options)
	check(sound.Parent == attachment and sound.SoundId == "rbxassetid://1", "spatial source and audio ID configured")
	check(sound:GetAttribute("ForgeGUISoundOwned") == true and sound:GetAttribute("ForgeGUISoundKey") == "loop", "new sound tagged for ownership")
	check(sound.RollOffMode == Enum.RollOffMode.InverseTapered and sound.RollOffMinDistance == 8 and sound.RollOffMaxDistance == 65, "explicit spatial rolloff applied")
	check(sound.SoundGroup == group and sound.Looped and sound.Volume == 0, "mix and looping options applied")
	check(not sound.IsPlaying and not sound.PlayOnRemove, "placement does not start playback")
	for _ = 1, 3 do
		check(S.ensure(attachment, "loop", "1", options) == sound, "repeated setup reuses the same sound")
	end
	check(#attachment:GetChildren() == 1, "repeated setup leaves one voice")
	rejects(function() S.ensure(attachment, "loop", "2", { minDistance = 50, maxDistance = 40 }) end, "invalid rolloff rejected")
	rejects(function() S.ensure(attachment, "loop", "2", { volume = 0 / 0 }) end, "NaN volume rejected")
	rejects(function() S.ensure(attachment, "loop", "2", { playbackSpeed = math.huge }) end, "infinite speed rejected")
	rejects(function() S.ensure(attachment, "loop", "2", { group = part :: any }) end, "non-SoundGroup rejected")
	check(sound.SoundId == "rbxassetid://1" and sound.Looped and sound.Volume == 0 and sound.SoundGroup == group and sound.RollOffMaxDistance == 65, "invalid updates preserve existing configuration")
	rejects(function() S.ensure(attachment, "bad", "https://example.com/audio") end, "external URL rejected")
	rejects(function() S.ensure(attachment, "bad", "0") end, "zero asset ID rejected")
	rejects(function() S.ensure(attachment, "", "1") end, "empty placement key rejected")
	rejects(function() S.ensure(scratch, "bad", "1") end, "non-spatial folder parent rejected")
	check(#attachment:GetChildren() == 1, "invalid new placements leave no instances")

	local unrelated = Instance.new("Sound")
	unrelated.Name = "FGSound_collision"
	unrelated.Volume = 0
	unrelated.Parent = attachment
	rejects(function() S.ensure(attachment, "collision", "1") end, "unowned sound name collision rejected")
	rejects(function() S.play(unrelated) end, "unowned playback rejected")
	rejects(function() S.remove(unrelated) end, "unowned cleanup rejected")
	check(unrelated.Parent == attachment and unrelated.SoundId == "" and not unrelated.IsPlaying, "unowned sound preserved")
	local foreign = Instance.new("Folder")
	foreign.Name = "FGSound_foreign"
	foreign:SetAttribute("ForgeGUISoundOwned", true)
	foreign.Parent = attachment
	rejects(function() S.ensure(attachment, "foreign", "1") end, "non-Sound collision rejected even with ownership tag")

	S.ensure(attachment, "loop", "2")
	check(sound.SoundId == "rbxassetid://2" and sound.Volume == 0.25 and not sound.Looped and sound.SoundGroup == nil and sound.RollOffMinDistance == 6 and sound.RollOffMaxDistance == 40, "full configuration replaces ID and resets omitted options")
	local second = S.ensure(part, "loop", "1", { volume = 0 })
	check(second ~= sound and second.Parent == part, "same key on another parent has an independent voice")
	globalSound = S.ensure(game:GetService("SoundService"), scratch.Name, "1", { volume = 0, looped = true })
	check(globalSound.Parent == game:GetService("SoundService"), "global ambience uses SoundService")

	-- Exercise only the playback policy here; native asset loading needs a separate Play check.
	local spy: any = { Looped = true, IsPlaying = false, plays = 0, stops = 0 }
	function spy:GetAttribute(name: string) return name == "ForgeGUISoundOwned" end
	function spy:Play() self.plays += 1; self.IsPlaying = true end
	function spy:Stop() self.stops += 1; self.IsPlaying = false end
	S.play(spy)
	S.play(spy)
	check(spy.plays == 1 and spy.stops == 0, "playing loop is not restarted")
	spy.IsPlaying = false
	S.play(spy)
	check(spy.plays == 2, "stopped loop resumes on request")
	spy.Looped = false
	S.play(spy)
	S.play(spy)
	check(spy.plays == 4 and spy.stops == 2, "one-shots stop and retrigger one voice")

	S.remove(sound)
	check(sound.Parent == nil and not sound.PlayOnRemove, "owned cleanup destroys without playback-on-remove")
	check(unrelated.Parent == attachment and foreign.Parent == attachment and second.Parent == part, "cleanup preserves unrelated sounds and objects")
	S.remove(globalSound)
	check(globalSound.Parent == nil, "global sound cleanup succeeds")
end, debug.traceback)

if globalSound then globalSound:Destroy() end
scratch:Destroy()
assert(ok, tostring(failure))
return HttpService:JSONEncode({ passed = #checks, failed = 0, checks = checks, temporaryInstancesRemoved = scratch.Parent == nil and (globalSound == nil or globalSound.Parent == nil) })
