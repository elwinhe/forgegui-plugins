--!strict
-- Structural checks for generated-art UI.
--
-- Two faults kept reaching play-testers because a screenshot hides them or makes
-- them look intended:
--   * borders nobody asked for: a Roblox stroke or fill around art that already
--     draws its own rim, an icon boxed in a chip or laid on a framed plate, a
--     stroked card inside a framed panel (a frame inside a frame);
--   * modals that close on any click that is not a button, because a full-screen
--     backdrop button was wired to close and the panel lets clicks through to it.
--
--   local report = UiCheck.audit(playerGui.Main)
--   print(UiCheck.format(report))
--   UiCheck.lintSource(script.Source, script:GetFullName())   -- dismissal wiring
--   UiCheck.strayClickPoints(panel, screenSize)               -- points to click in play
--
-- Everything reads plain properties, so the checks run headless against stubs.
-- Set the attribute UiCheckIgnore = true on an element whose chrome is deliberate.
-- To run it through execute_luau, paste it ahead of a runner with
-- references/tools/paste_module.py (see references/world-and-ui-checks.md).

local UiCheck = {}

export type Finding = { check: string, severity: string, subject: string, detail: string }
export type Report = { findings: { Finding }, errors: number, warnings: number, checked: number }
export type Options = {
	-- Icons are image elements no larger than this many pixels on either side.
	iconMaxPixels: number?,
	-- A chip no more than this many times the icon's size is "wrapping" it.
	chipRatio: number?,
}
export type StrayPoint = { position: Vector2, label: string }

local DEFAULT_ICON_MAX = 128
local DEFAULT_CHIP_RATIO = 1.8
-- An icon covering at least this share of the art behind it, on both axes, is
-- framed by that art; smaller art on a button (a coin beside a price) is not.
local PLATE_COVERAGE = 0.45
local IMAGE_CLASSES = { ImageLabel = true, ImageButton = true }
local TEXT_CLASSES = { TextLabel = true, TextButton = true, TextBox = true }
local BUTTON_CLASSES = { TextButton = true, ImageButton = true }
local CONTAINER_CLASSES = { Frame = true, ScrollingFrame = true, CanvasGroup = true }

local function add(report: Report, check: string, severity: string, subject: any, detail: string)
	local ok, name = pcall(function()
		return subject:GetFullName()
	end)
	table.insert(report.findings, { check = check, severity = severity, subject = if ok then name else tostring(subject.Name), detail = detail })
	if severity == "error" then
		report.errors += 1
	else
		report.warnings += 1
	end
end

local function isImage(object: any): boolean
	return IMAGE_CLASSES[object.ClassName] == true and object.Image ~= nil and object.Image ~= ""
end

local function isGuiObject(object: any): boolean
	if object == nil then
		return false
	end
	local class = object.ClassName
	return CONTAINER_CLASSES[class] == true or IMAGE_CLASSES[class] == true or TEXT_CLASSES[class] == true
end

local function ignored(object: any): boolean
	return object:GetAttribute("UiCheckIgnore") == true
end

local function pixels(object: any): (number, number)
	local absolute = object.AbsoluteSize
	if absolute and (absolute.X > 0 or absolute.Y > 0) then
		return absolute.X, absolute.Y
	end
	return object.Size.X.Offset, object.Size.Y.Offset
end

-- An enabled stroke drawn around the element's box. On text elements only a
-- Border-mode stroke counts; a Contextual one outlines the glyphs.
local function borderStroke(object: any): any?
	for _, child in ipairs(object:GetChildren()) do
		if child.ClassName == "UIStroke" and child.Enabled ~= false and (child.Transparency or 0) < 1 then
			local mode = child.ApplyStrokeMode
			if not TEXT_CLASSES[object.ClassName] or (mode ~= nil and mode.Name == "Border") then
				return child
			end
		end
	end
	return nil
end

local function hasFill(object: any): boolean
	return (object.BackgroundTransparency or 1) < 1
end

-- Art that fills its container is the frame everything else in it sits inside.
local function framingArt(container: any): any?
	local pw, ph = pixels(container)
	if pw <= 0 or ph <= 0 then
		return nil
	end
	for _, child in ipairs(container:GetChildren()) do
		if isImage(child) and child.Visible ~= false then
			local cw, ch = pixels(child)
			if cw >= pw * 0.95 and ch >= ph * 0.95 then
				return child
			end
		end
	end
	return nil
end

local function checkImage(report: Report, object: any, options: Options)
	if hasFill(object) then
		add(report, "art_background", "error", object, "generated art has a visible Roblox background behind it; set BackgroundTransparency = 1 and let the art's own shape show.")
	end
	if borderStroke(object) then
		add(report, "art_stroke", "error", object, "a UIStroke draws a rectangle around art that already has its own rim; remove it.")
	end
	local width, height = pixels(object)
	local parent = object.Parent
	if width <= 0 or height <= 0 or math.max(width, height) > (options.iconMaxPixels or DEFAULT_ICON_MAX) then
		return
	end
	if not isGuiObject(parent) or ignored(parent) then
		return
	end
	if isImage(parent) then
		local pw, ph = pixels(parent)
		local cx, cy = width / math.max(pw, 1), height / math.max(ph, 1)
		if cx >= PLATE_COVERAGE and cy >= PLATE_COVERAGE and (cx < 0.95 or cy < 0.95) then
			add(report, "icon_on_plate", "error", object, ("the icon is laid on %s, so it is framed twice; show the icon on its own and give the button its hover and press motion instead."):format(parent.Name))
		end
		return
	end
	local pw, ph = pixels(parent)
	local ratio = options.chipRatio or DEFAULT_CHIP_RATIO
	if (borderStroke(parent) or hasFill(parent)) and pw <= width * ratio and ph <= height * ratio then
		add(report, "bordered_icon", "error", object, ("the icon sits in a %dx%d chip with a stroke or fill; generated icons carry their own silhouette, so drop the chip or its chrome."):format(pw, ph))
	end
end

-- Only boxes that hold content count; a control's outline (a switch track, a
-- text button) is part of the control, not a second frame.
local function checkFrameInFrame(report: Report, object: any)
	if not (CONTAINER_CLASSES[object.ClassName] or object.ClassName == "TextLabel") or not borderStroke(object) then
		return
	end
	local ancestor = object.Parent
	while isGuiObject(ancestor) do
		local art = framingArt(ancestor)
		if art and art ~= object then
			add(report, "stroke_in_framed_art", "error", object, ("a stroked box inside %s, which already frames it; use spacing, a soft fill or a divider instead of a second border."):format(art.Name))
			return
		end
		ancestor = ancestor.Parent
	end
end

function UiCheck.audit(root: Instance, options: Options?): Report
	local settings = options or {}
	local report: Report = { findings = {}, errors = 0, warnings = 0, checked = 0 }
	for _, object in ipairs(root:GetDescendants()) do
		if not isGuiObject(object) or ignored(object) then
			continue
		end
		report.checked += 1
		if isImage(object) then
			checkImage(report, object, settings)
		else
			checkFrameInFrame(report, object)
		end
		if TEXT_CLASSES[object.ClassName] and object.Visible ~= false and object.Text ~= "" and object.TextFits == false then
			add(report, "text_overflow", "warning", object, ("%q does not fit its box at the minimum size."):format(object.Text))
		end
	end
	return report
end

-- Wiring that closes a modal from a full-screen backdrop, scrim or overlay. A
-- panel's empty space passes clicks through to that backdrop, so the modal
-- closes whenever the player misses a button.
local DISMISS_NAMES = { "[Bb]ackdrop", "[Ss]crim", "[Oo]verlay", "[Dd]immer" }
local INPUT_SIGNALS = { Activated = true, MouseButton1Click = true, MouseButton1Down = true, MouseButton1Up = true, InputBegan = true, TouchTap = true }

function UiCheck.lintSource(source: string, name: string): Report
	local report: Report = { findings = {}, errors = 0, warnings = 0, checked = 1 }
	local lineNumber = 0
	for line in string.gmatch(source .. "\n", "(.-)\n") do
		lineNumber += 1
		if string.match(line, "^%s*%-%-") or not string.find(line, "Connect", 1, true) then
			continue
		end
		for variable, member in string.gmatch(line, "([%w_]+)%.([%w_]+):Connect") do
			local named = false
			for _, pattern in ipairs(DISMISS_NAMES) do
				named = named or string.find(variable, pattern) ~= nil
			end
			if named and INPUT_SIGNALS[member] then
				add(report, "modal_closes_on_stray_click", "error", { Name = ("%s:%d"):format(name, lineNumber) }, ("%s.%s is connected; a click that misses a button lands on the backdrop and closes the modal. Let the backdrop sink input and close only from the close button or a key."):format(variable, member))
			end
		end
	end
	return report
end

-- Points inside a modal panel that are not over any visible button, plus points
-- on the screen outside the panel. Click each one in play and assert the modal is
-- still open. Positions are in AbsolutePosition space; add the GUI inset when
-- the ScreenGui does not ignore it.
function UiCheck.strayClickPoints(panel: GuiObject, screenSize: Vector2, grid: number?): { StrayPoint }
	local steps = grid or 4
	local buttons = {}
	for _, object in ipairs(panel:GetDescendants()) do
		if BUTTON_CLASSES[object.ClassName] and object.Visible ~= false then
			table.insert(buttons, object)
		end
	end
	local function overButton(point: Vector2): boolean
		for _, button in ipairs(buttons) do
			local low, size = button.AbsolutePosition, button.AbsoluteSize
			if point.X >= low.X - 4 and point.X <= low.X + size.X + 4 and point.Y >= low.Y - 4 and point.Y <= low.Y + size.Y + 4 then
				return true
			end
		end
		return false
	end
	local points: { StrayPoint } = {}
	local low, size = panel.AbsolutePosition, panel.AbsoluteSize
	for column = 1, steps do
		for row = 1, steps do
			local point = Vector2.new(low.X + size.X * (column - 0.5) / steps, low.Y + size.Y * (row - 0.5) / steps)
			if not overButton(point) then
				table.insert(points, { position = point, label = ("panel %d,%d"):format(column, row) })
			end
		end
	end
	local outside = {
		{ Vector2.new(low.X / 2, screenSize.Y / 2), "left of panel" },
		{ Vector2.new((low.X + size.X + screenSize.X) / 2, screenSize.Y / 2), "right of panel" },
		{ Vector2.new(screenSize.X / 2, (low.Y + size.Y + screenSize.Y) / 2), "below panel" },
	}
	for _, entry in ipairs(outside) do
		local point = entry[1]
		local onScreen = point.X > 0 and point.X < screenSize.X and point.Y > 0 and point.Y < screenSize.Y
		if onScreen and not overButton(point) then
			table.insert(points, { position = point, label = entry[2] })
		end
	end
	return points
end

-- Where every visible surface came from.
--
-- The checks above each report a wrong thing. This one reports the positive
-- claim — an interface built from generated images and text labels rather than
-- from Studio primitives — as a number, so it can be handed to a reviewer
-- instead of argued from a screenshot.
--
-- A *surface* is an element that draws its own pixels:
--   * an image element whose Image is in the art registry is generated art with
--     known provenance;
--   * an image element whose Image is not is unattributable, and a Toolbox decal
--     looks exactly like one;
--   * a container or label that draws a fill or a border is a Studio primitive.
--
-- Primitives are allowed — the screen templates put text, glass pills, progress
-- bars and dividers in ordinary frames — so they are counted and warned, never
-- failed. Mark the deliberate ones with AllowPrimitive = true. A transparent
-- layout frame draws nothing and is not a surface at all, which is what keeps
-- the ratio meaningful.
--
-- Text labels are compliant by the same rule, but glyphs are not a surface, so
-- they are reported beside the ratio rather than inside it.
--
--   UiCheck.provenance(playerGui.Main, require(ReplicatedStorage.Game.ArtRegistry))

export type Provenance = {
	art: number,
	unregistered: number,
	primitive: number,
	text: number,
	surfaces: number,
	coverage: number,
}

-- "rbxassetid://123", "123", and an asset URL all name the same upload.
local function assetDigits(value: any): string?
	if type(value) ~= "string" or value == "" then
		return nil
	end
	return string.match(value, "[?&]id=(%d+)") or string.match(value, "(%d+)%s*$")
end

-- Accepts the GuiArt registry ({ coin = { id = "rbxassetid://..." } }), a plain
-- list of ids, or a map of name to id string.
local function registryIds(registry: any): { [string]: boolean }
	local ids: { [string]: boolean } = {}
	if type(registry) ~= "table" then
		return ids
	end
	local function absorb(value: any)
		local digits = assetDigits(value)
		if digits then
			ids[digits] = true
		end
	end
	for _, entry in pairs(registry) do
		if type(entry) == "table" then
			absorb(entry.id)
			absorb(entry.Image)
		else
			absorb(entry)
		end
	end
	return ids
end

function UiCheck.provenance(root: Instance, registry: any, options: Options?): Report
	local _ = options
	local ids = registryIds(registry)
	local known = next(ids) ~= nil
	local tally: Provenance = { art = 0, unregistered = 0, primitive = 0, text = 0, surfaces = 0, coverage = 0 }
	local report: Report = { findings = {}, errors = 0, warnings = 0, checked = 0 }
	;(report :: any).provenance = tally

	if not known then
		add(report, "provenance_no_registry", "warning", root, "no art registry was supplied, so every image counts as generated art and the ratio below is not evidence; pass the place's ArtRegistry.")
	end

	for _, object in ipairs(root:GetDescendants()) do
		if not isGuiObject(object) or ignored(object) or object.Visible == false then
			continue
		end
		report.checked += 1
		if isImage(object) then
			tally.surfaces += 1
			local digits = assetDigits(object.Image)
			if known and (digits == nil or not ids[digits]) then
				tally.unregistered += 1
				add(report, "unregistered_image", "error", object, ("shows %s, which is not in the art registry; a generated asset is recorded there with its aspect, so an unlisted image is either an unrecorded upload or a Toolbox decal. Record it or replace it."):format(tostring(object.Image)))
			else
				tally.art += 1
			end
		elseif hasFill(object) or borderStroke(object) then
			tally.surfaces += 1
			tally.primitive += 1
			if object:GetAttribute("AllowPrimitive") ~= true then
				add(report, "primitive_surface", "warning", object, "draws a Roblox fill or border of its own. Chrome may do that — set AllowPrimitive = true to say so — but a panel, button or icon surface should be generated art.")
			end
		end
		if TEXT_CLASSES[object.ClassName] and object.Text ~= nil and object.Text ~= "" then
			tally.text += 1
		end
	end

	if tally.surfaces > 0 then
		tally.coverage = tally.art / tally.surfaces
	end
	return report
end

function UiCheck.merge(reports: { Report }): Report
	local merged: Report = { findings = {}, errors = 0, warnings = 0, checked = 0 }
	for _, report in ipairs(reports) do
		for _, finding in ipairs(report.findings) do
			table.insert(merged.findings, finding)
		end
		merged.errors += report.errors
		merged.warnings += report.warnings
		merged.checked += report.checked
	end
	return merged
end

function UiCheck.format(report: Report): string
	local lines = { ("UiCheck: %d error(s), %d warning(s), %d checked"):format(report.errors, report.warnings, report.checked) }
	local tally = (report :: any).provenance
	if tally then
		table.insert(lines, ("  surfaces: %d generated art, %d unattributed, %d primitive — %.0f%% generated; %d text label(s)"):format(tally.art, tally.unregistered, tally.primitive, tally.coverage * 100, tally.text))
	end
	for _, finding in ipairs(report.findings) do
		table.insert(lines, ("[%s] %s %s: %s"):format(finding.severity, finding.check, finding.subject, finding.detail))
	end
	return table.concat(lines, "\n")
end

return UiCheck
