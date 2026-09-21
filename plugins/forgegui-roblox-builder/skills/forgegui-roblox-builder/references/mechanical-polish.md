# Mechanical polish

The small details that make a build read as finished. Each snippet is self-contained Luau for `multi_edit` into the right script type; resolve placeholder names such as `chest` to inspected instances in your place before pasting. Apply after the scene and gameplay exist; order: UI transitions → hit feedback → camera → prompts → onboarding.

## UI transitions (LocalScript under the ScreenGui)

Use `luau/Motion.luau`, documented in `ui-motion.md`, rather than a hand-written tween per panel:

```lua
local Motion = require(ReplicatedStorage.Visuals.Motion)
local shop = Motion.modal(panel, { backdrop = backdrop })
Motion.pressable(buyButton)
Motion.countTo(coinLabel, oldTotal, newTotal)
shop.open()
```

Rules it already keeps: 150–250 ms, `Back`/`Quad` out for entrances, `Quad` in for exits, never bounce the whole HUD, and never tween a background that the art is meant to supply. Two failures a hand-written version usually has instead: `Tween.Completed` fires for `Cancel` as well, so reopening a menu mid-close hides it again; and animating the same `UIScale` that carries responsive scale snaps the HUD to design size. A modal's backdrop dims and sinks input — it never closes the modal.

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
local shake = 0
local lastCamera: Camera? = nil
local lastWritten: CFrame? = nil
local lastBase = CFrame.identity

local function restoreOwnedOffset()
	-- Restore only our most recent write to the SAME camera. Preserve newer controller writes.
	if lastCamera and lastWritten and lastCamera.CFrame == lastWritten then
		lastCamera.CFrame = lastBase
	end
	lastCamera = nil
	lastWritten = nil
	lastBase = CFrame.identity
end

RunService:BindToRenderStep("ForgeGUICameraShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local camera = workspace.CurrentCamera
	if camera ~= lastCamera then restoreOwnedOffset() end
	if not camera then return end
	local current = camera.CFrame
	local base = if current == lastWritten then lastBase else current
	local offset = CFrame.identity
	if shake > 0.01 then
		offset = CFrame.new((math.random() - 0.5) * shake, (math.random() - 0.5) * shake, 0)
		shake = math.max(0, shake - dt * 4)
	else
		shake = 0
	end
	lastCamera = camera
	lastBase = base
	lastWritten = base * offset
	camera.CFrame = lastWritten
end)

local function stopShake()
	RunService:UnbindFromRenderStep("ForgeGUICameraShake")
	restoreOwnedOffset()
	shake = 0
end

-- RemoteEvent handler: shake = math.min(shake + 0.35, 1)
-- On teardown call stopShake(). Call explicitly before removing/replacing this script.
-- Ownership assumption: no other script uses the same render binding name.
```

Cap amplitude at 1 stud and decay fast. The offset is bounded to ±half the amplitude per local X/Y axis when the controller supplies a clean transform each frame, or when a stationary Scriptable camera retains this callback's previous write. A controller that builds its next transform from the already shaken camera needs its own separate base transform; this snippet cannot infer that base. Call `stopShake()` before removing or replacing the script: it unbinds and restores only its own remaining offset, preserving any newer controller write. Never shake on every hit for ranged spam; gate to hits on the local player or large explosions.

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
