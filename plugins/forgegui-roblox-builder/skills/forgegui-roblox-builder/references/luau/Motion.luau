--!strict
-- UI motion. The difference between a Roblox menu and a shipped
-- one is rarely the layout -- it is that everything arrives, responds and
-- leaves, and that nothing ever snaps.
--
-- Three rules hold it together:
--   1. One tween per object per channel. A second tween on the same property
--      is cancelled first, so a fast clicker gets responsiveness, not jitter.
--   2. Motion has a budget. Durations are clamped; a panel that takes a second
--      to open reads as lag, not polish.
--   3. Nothing animates a layout property. Position and Size are driven through
--      UIScale and AnchorPoint offsets where possible.

local TweenService = game:GetService("TweenService")

local Motion = {}

local MAX_SECONDS = 1.2
local ACTIVE: { [Instance]: { [string]: Tween } } = {}
-- Where each element rests when it is not moving. An interrupted reveal or
-- dismiss must aim for this, not for wherever the element happened to be.
local HOME: { [GuiObject]: UDim2 } = setmetatable({}, { __mode = "k" }) :: any

-- Curves chosen for what they communicate, not for variety: Back for arrival
-- (a slight overshoot reads as physical), Quart for exits (fast start, out of
-- the way), Quad for state changes that should not draw attention.
Motion.EASING = {
	arrive = { style = Enum.EasingStyle.Back, direction = Enum.EasingDirection.Out, seconds = 0.28 },
	exit = { style = Enum.EasingStyle.Quart, direction = Enum.EasingDirection.In, seconds = 0.16 },
	state = { style = Enum.EasingStyle.Quad, direction = Enum.EasingDirection.Out, seconds = 0.12 },
	emphasis = { style = Enum.EasingStyle.Elastic, direction = Enum.EasingDirection.Out, seconds = 0.45 },
}

local function clampSeconds(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value <= 0 then
		return fallback
	end
	return math.min(value, MAX_SECONDS)
end

-- `channel` groups tweens that fight over the same properties, so starting a
-- new one cancels only its own kind.
local function play(object: Instance, channel: string, info: TweenInfo, goal: { [string]: any }): Tween
	local channels = ACTIVE[object]
	if not channels then
		channels = {}
		ACTIVE[object] = channels
	end
	local existing = channels[channel]
	if existing then
		existing:Cancel()
	end
	local tween = TweenService:Create(object, info, goal)
	channels[channel] = tween
	tween.Completed:Once(function()
		if channels[channel] == tween then
			channels[channel] = nil
		end
		if next(channels) == nil then
			ACTIVE[object] = nil
		end
	end)
	tween:Play()
	return tween
end

-- Roblox fires Tween.Completed for Cancel as well as for a finished tween.
-- Anything that hides, destroys or chains on completion checks this first.
local function finished(state: Enum.PlaybackState): boolean
	return state == Enum.PlaybackState.Completed
end

local function homeOf(object: GuiObject): UDim2
	local channels = ACTIVE[object]
	local moving = channels ~= nil and channels.position ~= nil
	local home = HOME[object]
	if moving and home then
		return home
	end
	HOME[object] = object.Position
	return object.Position
end

local function easingInfo(name: string, seconds: number?): TweenInfo
	local preset = Motion.EASING[name] or Motion.EASING.state
	return TweenInfo.new(clampSeconds(seconds, preset.seconds), preset.style, preset.direction)
end

local function uiScale(object: GuiObject): UIScale
	local scale = object:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = object
	end
	return scale :: UIScale
end

-- Arrival and exit -------------------------------------------------------------

export type RevealOptions = { seconds: number?, from: number?, rise: number? }

-- Scales and lifts an element into place. Scale is animated on a UIScale rather
-- than on Size, so layout never reflows mid-animation.
function Motion.reveal(object: GuiObject, options: RevealOptions?)
	local settings = options or {}
	local scale = uiScale(object)
	local target = homeOf(object)
	local rise = settings.rise or 18

	scale.Scale = math.clamp(settings.from or 0.92, 0.5, 1)
	object.Position = target + UDim2.fromOffset(0, rise)
	object.Visible = true

	play(scale, "scale", easingInfo("arrive", settings.seconds), { Scale = 1 })
	play(object, "position", easingInfo("arrive", settings.seconds), { Position = target })
end

function Motion.dismiss(object: GuiObject, options: RevealOptions?)
	local settings = options or {}
	local scale = uiScale(object)
	local start = homeOf(object)
	local drop = settings.rise or 12

	play(scale, "scale", easingInfo("exit", settings.seconds), { Scale = 0.96 })
	local tween = play(object, "position", easingInfo("exit", settings.seconds), { Position = start + UDim2.fromOffset(0, drop) })
	tween.Completed:Once(function(state)
		if not finished(state) then
			return
		end
		object.Visible = false
		object.Position = start
		scale.Scale = 1
	end)
end

-- Reveals children one after another. The delay is small on purpose: a stagger
-- you notice is a stagger that is too slow.
function Motion.stagger(container: Instance, options: { delay: number?, seconds: number? }?)
	local settings = options or {}
	local step = math.clamp(settings.delay or 0.045, 0.01, 0.2)
	local index = 0
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") then
			local delay = index * step
			index += 1
			task.delay(delay, function()
				-- Still ours: a child moved to another container, or recycled into
				-- another list, belongs to whatever owns it now.
				if child.Parent == container then
					Motion.reveal(child, { seconds = settings.seconds })
				end
			end)
		end
	end
	return index
end

-- Interaction ------------------------------------------------------------------

-- Hover and press states. Art-backed buttons have no background to tint, so the
-- feedback is scale: small enough to feel physical, large enough to register.
function Motion.pressable(button: GuiButton, options: { hover: number?, press: number? }?)
	local settings = options or {}
	local hover = math.clamp(settings.hover or 1.04, 1, 1.15)
	local press = math.clamp(settings.press or 0.95, 0.85, 1)
	local scale = uiScale(button)
	local function to(value: number, easing: string)
		play(scale, "scale", easingInfo(easing), { Scale = value })
	end
	button.MouseEnter:Connect(function()
		to(hover, "state")
	end)
	button.MouseLeave:Connect(function()
		to(1, "state")
	end)
	button.MouseButton1Down:Connect(function()
		to(press, "state")
	end)
	button.MouseButton1Up:Connect(function()
		to(hover, "emphasis")
	end)
end

-- A short attention beat for something that just changed underneath the player.
function Motion.pulse(object: GuiObject, strength: number?)
	local scale = uiScale(object)
	local peak = math.clamp(strength or 1.08, 1, 1.3)
	local tween = play(scale, "scale", easingInfo("state", 0.08), { Scale = peak })
	tween.Completed:Once(function(state)
		if finished(state) then
			play(scale, "scale", easingInfo("emphasis"), { Scale = 1 })
		end
	end)
end

-- Numbers ----------------------------------------------------------------------

export type CountOptions = { seconds: number?, format: ((number) -> string)? }

type Counter = { holder: NumberValue, format: (number) -> string, connection: RBXScriptConnection? }
local COUNTERS: { [TextLabel]: Counter } = setmetatable({}, { __mode = "k" }) :: any

-- Counts a label from its current value to a new one. A coin total that ticks
-- up reads as a reward; the same total snapping into place reads as a variable
-- being assigned.
function Motion.countTo(label: TextLabel, from: number, to: number, options: CountOptions?): ()
	local settings = options or {}
	local seconds = clampSeconds(settings.seconds, 0.4)
	local format = settings.format or function(value: number): string
		return tostring(math.floor(value + 0.5))
	end
	-- One counter per label. A second count while the first is running retargets
	-- the same value instead of starting a rival that fights over the text.
	local counter = COUNTERS[label]
	if not counter then
		local holder = Instance.new("NumberValue")
		holder.Value = from
		holder.Parent = label
		counter = { holder = holder, format = format }
		local state = counter
		counter.connection = holder.Changed:Connect(function(value)
			label.Text = state.format(value)
		end)
		COUNTERS[label] = counter
	end
	counter.format = format
	local active = counter
	local tween = play(active.holder, "value", TweenInfo.new(seconds, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Value = to })
	tween.Completed:Once(function(state)
		if not finished(state) or COUNTERS[label] ~= active then
			return
		end
		label.Text = format(to)
		active.connection:Disconnect()
		active.holder:Destroy()
		COUNTERS[label] = nil
	end)
end

-- Modals -----------------------------------------------------------------------

export type ModalHandle = { open: () -> (), close: () -> () }

-- A modal that dims and blurs the world behind it. The blur is what separates a
-- panel floating over a scene from a panel that owns the screen; it is removed
-- on close, and it is the caller's own BlurEffect, never an adopted one.
--
-- A modal never closes on a stray click. Wiring the backdrop to close meant any
-- click that missed a button closed the screen the player was reading, because
-- a panel's empty space lets clicks fall through to the backdrop behind it. So
-- the backdrop here only dims and sinks input, and the panel sinks input over
-- its own area. Close from a close button, a key or gamepad B, or the action
-- that opened the modal; never connect an input signal on the backdrop.
function Motion.modal(panel: GuiObject, options: { backdrop: GuiObject?, blur: number?, seconds: number? }?): ModalHandle
	local settings = options or {}
	local blurSize = math.clamp(settings.blur or 14, 0, 24)
	local backdrop = settings.backdrop
	local blurName = "ForgeGUI_ModalBlur"

	panel.Active = true
	if backdrop then
		backdrop.Active = true
		-- A button backdrop is what reliably stops clicks reaching the HUD and the
		-- world under it; Modal frees a locked mouse (shift lock, first person).
		if backdrop.ClassName == "TextButton" or backdrop.ClassName == "ImageButton" then
			local button = backdrop :: any
			button.AutoButtonColor = false
			button.Modal = true
			button.Selectable = false
		end
	end

	local function open()
		if backdrop then
			backdrop.BackgroundTransparency = 1
			backdrop.Visible = true
			play(backdrop, "backdrop", easingInfo("state", settings.seconds), { BackgroundTransparency = 0.45 })
		end
		local lighting = game:GetService("Lighting")
		local blur = lighting:FindFirstChild(blurName)
		if not blur then
			blur = Instance.new("BlurEffect")
			blur.Name = blurName
			blur.Size = 0
			blur.Parent = lighting
		end
		play(blur, "blur", easingInfo("state", settings.seconds), { Size = blurSize })
		Motion.reveal(panel, { seconds = settings.seconds })
	end

	local function close()
		local lighting = game:GetService("Lighting")
		local blur = lighting:FindFirstChild(blurName)
		if blur then
			local tween = play(blur, "blur", easingInfo("exit", settings.seconds), { Size = 0 })
			tween.Completed:Once(function(state)
				if finished(state) and blur.Parent then
					blur:Destroy()
				end
			end)
		end
		if backdrop then
			local tween = play(backdrop, "backdrop", easingInfo("exit", settings.seconds), { BackgroundTransparency = 1 })
			tween.Completed:Once(function(state)
				if finished(state) then
					backdrop.Visible = false
				end
			end)
		end
		Motion.dismiss(panel, { seconds = settings.seconds })
	end

	return { open = open, close = close }
end

-- Cancels every tween this module is running on an object. Call before
-- destroying something mid-animation.
function Motion.stop(object: Instance)
	local channels = ACTIVE[object]
	if not channels then
		return
	end
	for _, tween in pairs(channels) do
		tween:Cancel()
	end
	ACTIVE[object] = nil
end

Motion.MAX_SECONDS = MAX_SECONDS

return Motion
