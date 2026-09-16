# Mechanical polish

The small details that make a build read as finished. Each snippet is self-contained Luau for `multi_edit` into the right script type. Apply after the scene and gameplay exist; order: UI transitions → hit feedback → camera → prompts → onboarding.

## UI tween-in (LocalScript under the ScreenGui)

```lua
local TweenService = game:GetService("TweenService")
local panel = script.Parent:WaitForChild("Panel")
local scale = panel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", panel)

local function show()
	panel.Visible = true
	scale.Scale = 0.9
	panel.BackgroundTransparency = 1
	for _, d in panel:GetDescendants() do
		if d:IsA("GuiObject") then d:SetAttribute("t0", d.BackgroundTransparency) d.BackgroundTransparency = 1 end
	end
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(panel, TweenInfo.new(0.18), { BackgroundTransparency = 0 }):Play()
	for _, d in panel:GetDescendants() do
		if d:IsA("GuiObject") then
			TweenService:Create(d, TweenInfo.new(0.18), { BackgroundTransparency = d:GetAttribute("t0") or 0 }):Play()
		end
	end
end
```

Rules: 150–250 ms, `Back`/`Quad` out for entrances, `Quad` in for exits, never bounce the whole HUD. Respect the art's transparency (do not tween an `ImageLabel` background that should stay transparent).

## Hit feedback (Script on the server, effect on the victim)

```lua
local TweenService = game:GetService("TweenService")

local function hitFeedback(model: Model, fromPosition: Vector3, force: number)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	-- flash
	local hl = Instance.new("Highlight")
	hl.FillColor = Color3.fromRGB(255, 80, 80); hl.FillTransparency = 0.2; hl.OutlineTransparency = 1
	hl.Parent = model
	TweenService:Create(hl, TweenInfo.new(0.18), { FillTransparency = 1 }):Play()
	game:GetService("Debris"):AddItem(hl, 0.2)
	-- knockback
	local dir = (root.Position - fromPosition) * Vector3.new(1, 0, 1)
	if dir.Magnitude > 0 then
		root:ApplyImpulse((dir.Unit * force + Vector3.new(0, force * 0.4, 0)) * root.AssemblyMass)
	end
end
```

Pair with `ParticleRecipes.burstAt("hit_impact", contactPosition)` and a `Sound` with `PlayOnRemove`. Keep the flash under 200 ms; longer reads as a bug.

## Camera shake (LocalScript in StarterPlayerScripts)

```lua
local RunService = game:GetService("RunService")
local camera = workspace.CurrentCamera
local shake = 0 -- current amplitude in studs

RunService.RenderStepped:Connect(function(dt)
	if shake > 0.01 then
		local offset = Vector3.new((math.random() - 0.5), (math.random() - 0.5), 0) * shake
		camera.CFrame = camera.CFrame * CFrame.new(offset)
		shake = math.max(0, shake - dt * 4) -- decay in ~0.25 s per stud
	end
end)

-- call from a RemoteEvent handler: shake = math.min(shake + 0.35, 1)
```

Cap amplitude at 1 stud and decay fast. Never shake on every hit for ranged spam; gate to hits on the local player or large explosions.

## Smooth camera follow (for third-person or vehicle cameras)

```lua
-- in RenderStepped, after computing the desired CFrame `target`
camera.CFrame = camera.CFrame:Lerp(target, 1 - math.exp(-dt * 10))
```

The `exp` form is frame-rate independent; 8–12 is a good stiffness. Leave `CameraType` alone unless the game owns the camera.

## Interaction prompts

```lua
local prompt = Instance.new("ProximityPrompt")
prompt.ActionText = "Open"
prompt.ObjectText = "Treasure chest"
prompt.KeyboardKeyCode = Enum.KeyCode.E
prompt.HoldDuration = 0.35
prompt.MaxActivationDistance = 8
prompt.RequiresLineOfSight = true
prompt.Parent = chest.Lid
```

Verb first, object second, one key game-wide. Use `HoldDuration` only for destructive or expensive actions. Add a `pickup_sparkle` or `Highlight` on approach so the affordance is visible before the prompt appears.

## Humanoid state transitions

Play a landing `footstep_puff` and a short sound on `Humanoid.StateChanged` → `Landed`; scale the puff by fall distance. Blend animations with `Animator:LoadAnimation(...):Play(0.15)` fade time instead of 0.

## First 30 seconds

On spawn: one tweened title card (2 s, then dismiss), a single prompt pointing at the first interaction, and no menu. Verify by starting a playtest, taking a capture at 0 s, 10 s and 30 s, and confirming the player can reach the first interaction without a hint.

## Verify

For every item: a playtest, a `screen_capture` during the effect, `get_console_output` clean of errors, and confirmation that transient instances (Highlight, FX attachments, title card) are gone afterwards.
