# Mechanical polish

The small details that make a build read as finished. Each snippet is self-contained Luau for `multi_edit` into the right script type. Apply after the scene and gameplay exist; order: UI transitions → hit feedback → camera → prompts → onboarding.

## UI tween-in (LocalScript under the ScreenGui)

```lua
local TweenService = game:GetService("TweenService")
local panel = script.Parent:WaitForChild("Panel")
local scale = panel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", panel)
local backgroundAlpha = { [panel] = panel.BackgroundTransparency }

local function show()
	panel.Visible = true
	scale.Scale = 0.9
	local objects = { panel }
	for _, d in panel:GetDescendants() do
		if d:IsA("GuiObject") then
			if backgroundAlpha[d] == nil then backgroundAlpha[d] = d.BackgroundTransparency end
			table.insert(objects, d)
		end
	end
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	for _, object in objects do
		object.BackgroundTransparency = 1
		TweenService:Create(object, TweenInfo.new(0.18), { BackgroundTransparency = backgroundAlpha[object] }):Play()
	end
end
```

Rules: 150–250 ms, `Back`/`Quad` out for entrances, `Quad` in for exits, never bounce the whole HUD. Respect the art's transparency (do not tween an `ImageLabel` background that should stay transparent).

## Hit feedback (Script on the server, effect on the victim; knockback for server-owned models only)

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

Pair with `ParticleRecipes.burstAt("hit_impact", contactPosition)` fired on the client (send the contact position through the same RemoteEvent used for camera shake; `Emit()` does not replicate from the server) and a `Sound` with `PlayOnRemove`. `ApplyImpulse` only acts on the machine that owns the part: it works for server-owned NPCs; for a player victim send the impulse through that same RemoteEvent and apply it in the client handler. Keep the flash under 200 ms; longer reads as a bug.

## Camera shake (LocalScript in StarterPlayerScripts)

```lua
local RunService = game:GetService("RunService")
local shake = 0 -- current amplitude in studs
local lastWritten: CFrame? = nil -- the CFrame this script wrote last frame
local lastBase = CFrame.identity -- the controller's transform that write was based on

-- Runs after the camera controller (RenderPriority.Camera) has written this frame's CFrame.
-- If the camera still holds what we wrote last frame, nothing else moved it (Scriptable), so
-- reuse the base we shook from. Otherwise the controller rewrote it (Custom) and that is the
-- base. Either way the offset is applied to a clean transform and never compounds.
RunService:BindToRenderStep("ForgeGUICameraShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local camera = workspace.CurrentCamera
	if not camera then return end
	local current = camera.CFrame
	local base = if current == lastWritten then lastBase else current
	local offset = CFrame.identity
	if shake > 0.01 then
		offset = CFrame.new((math.random() - 0.5) * shake, (math.random() - 0.5) * shake, 0)
		shake = math.max(0, shake - dt * 4) -- decay in ~0.25 s per stud
	else
		shake = 0
	end
	lastBase = base
	lastWritten = base * offset
	camera.CFrame = lastWritten
end)

-- call from a RemoteEvent handler: shake = math.min(shake + 0.35, 1)
-- on teardown: RunService:UnbindFromRenderStep("ForgeGUICameraShake")
```

Cap amplitude at 1 stud and decay fast. The offset is applied to the controller's transform for that frame, not to last frame's shaken result, so displacement stays within ±half the amplitude and the camera lands exactly where the controller put it when the shake ends. Never shake on every hit for ranged spam; gate to hits on the local player or large explosions.

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
