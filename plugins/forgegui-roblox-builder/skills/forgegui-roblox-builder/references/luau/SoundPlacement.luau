--!strict
-- Idempotent placement, one voice per parent/key, explicit playback and owned cleanup.
-- Library IDs still need client preload + an audible Play check in the target place.
local SoundService = game:GetService("SoundService")
local OWNED = "ForgeGUISoundOwned"
local M = {}

export type Options = {
	volume: number?,
	looped: boolean?,
	minDistance: number?,
	maxDistance: number?,
	playbackSpeed: number?,
	group: SoundGroup?,
}

local function bounded(value: number?, default: number, lo: number, hi: number): number
	local n = if value == nil then default else value
	assert(n == n and n >= lo and n <= hi, "SoundPlacement: invalid numeric option")
	return n
end

function M.ensure(parent: Instance, key: string, assetId: string, options: Options?): Sound
	assert(parent:IsA("BasePart") or parent:IsA("Attachment") or parent == SoundService,
		"SoundPlacement: use a BasePart/Attachment for spatial audio or SoundService for a global bed")
	assert(#key > 0 and #key <= 80, "SoundPlacement: supply a short stable placement key")
	assert(assetId:match("^[1-9]%d*$"), "SoundPlacement: expected a decimal Roblox audio asset ID")
	local opts = options or {}
	local volume = bounded(opts.volume, 0.25, 0, 10)
	local minimum = bounded(opts.minDistance, 6, 0, 100000)
	local maximum = bounded(opts.maxDistance, 40, 0.01, 100000)
	local speed = bounded(opts.playbackSpeed, 1, 0.05, 4)
	assert(maximum > minimum, "SoundPlacement: maxDistance must exceed minDistance")
	assert(opts.group == nil or opts.group:IsA("SoundGroup"), "SoundPlacement: invalid SoundGroup")
	local name = "FGSound_" .. key
	local existing = parent:FindFirstChild(name)
	assert(existing == nil or (existing:IsA("Sound") and existing:GetAttribute(OWNED) == true),
		"SoundPlacement: name belongs to an unrelated instance; choose a different key")
	local sound: Sound
	if existing then
		sound = existing :: Sound
	else
		sound = Instance.new("Sound")
		sound.Name = name
		sound:SetAttribute(OWNED, true)
		sound:SetAttribute("ForgeGUISoundKey", key)
	end
	local uri = "rbxassetid://" .. assetId
	if sound.SoundId ~= uri then
		sound:Stop()
		sound.SoundId = uri
	end
	sound.Volume = volume
	sound.Looped = opts.looped == true
	sound.PlayOnRemove = false
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = minimum
	sound.RollOffMaxDistance = maximum
	sound.PlaybackSpeed = speed
	sound.SoundGroup = opts.group
	sound.Parent = parent
	return sound
end

function M.play(sound: Sound)
	assert(sound:GetAttribute(OWNED) == true, "SoundPlacement: sound is not owned by this helper")
	if sound.Looped then
		if not sound.IsPlaying then sound:Play() end
	else
		-- Retrigger a single voice; do not clone an unbounded stack of hit/UI sounds.
		sound:Stop()
		sound:Play()
	end
end

function M.remove(sound: Sound)
	assert(sound:GetAttribute(OWNED) == true, "SoundPlacement: refusing unrelated sound cleanup")
	sound:Stop()
	sound:Destroy()
end

return M
