--!nocheck
-- Headless checks for WorldCheck and UiCheck. From the skill root:
--
--   lune run references/tests/qa
--
-- Each check is proven against the fault that motivated it: a spawn buried
-- under terrain, a tree canopy over a launch pad, an icon boxed in a stroked
-- chip, a stroked card inside a framed panel, and a backdrop wired to close.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

-- Minimal value types --------------------------------------------------------

local Vector3 = {}
local vectorMeta = {}
function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, vectorMeta)
end
vectorMeta.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
vectorMeta.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
vectorMeta.__mul = function(a, b)
	if type(a) == "number" then
		a, b = b, a
	end
	return Vector3.new(a.X * b, a.Y * b, a.Z * b)
end
vectorMeta.__div = function(a, b)
	return Vector3.new(a.X / b, a.Y / b, a.Z / b)
end

local Vector2 = {}
function Vector2.new(x, y)
	return { X = x or 0, Y = y or 0 }
end

local CFrame = {}
function CFrame.new(x, y, z)
	return { Position = Vector3.new(x, y, z) }
end

local env = { Vector3 = Vector3, Vector2 = Vector2, CFrame = CFrame }
local function load(path, name)
	return luau.load(fs.readFile(path), { debugName = name, environment = env })()
end
local WorldCheck = load("references/luau/WorldCheck.luau", "WorldCheck")
local UiCheck = load("references/luau/UiCheck.luau", "UiCheck")

local checks, failures = 0, 0
local function check(condition, label)
	checks += 1
	if not condition then
		failures += 1
		print(("  FAIL %s"):format(label))
	end
end
local function count(report, name)
	local total = 0
	for _, finding in ipairs(report.findings) do
		if finding.check == name then
			total += 1
		end
	end
	return total
end

-- A stub world of axis-aligned boxes -------------------------------------------

local function object(name, props)
	local attributes = props.attributes or {}
	props.Name = name
	props.GetAttribute = function(_, key)
		return attributes[key]
	end
	props.GetFullName = function()
		return "Workspace." .. name
	end
	return props
end

-- A box is { name, low = Vector3, high = Vector3 }; `owner` lets a check ignore it.
local function world(boxes, spawns)
	local function ignoredBy(box, ignore)
		for _, item in ipairs(ignore or {}) do
			if box.owner == item then
				return true
			end
		end
		return false
	end
	return {
		spawns = function()
			return spawns
		end,
		extents = function(item)
			return item.center, item.halfHeight
		end,
		footprint = function(spawn)
			return spawn.width or 8, spawn.depth or 8
		end,
		raycast = function(origin, direction, ignore)
			local bottom = origin.Y + direction.Y
			local best
			for _, box in ipairs(boxes) do
				local inside = origin.X >= box.low.X and origin.X <= box.high.X and origin.Z >= box.low.Z and origin.Z <= box.high.Z
				if inside and not ignoredBy(box, ignore) and box.high.Y <= origin.Y and box.high.Y >= bottom then
					if not best or box.high.Y > best.high.Y then
						best = box
					end
				end
			end
			return best and { position = Vector3.new(origin.X, best.high.Y, origin.Z), name = best.name } or nil
		end,
		solidInBox = function(cframe, size, ignore)
			local low, high = cframe.Position - size / 2, cframe.Position + size / 2
			local names = {}
			for _, box in ipairs(boxes) do
				local overlaps = box.low.X < high.X and box.high.X > low.X and box.low.Y < high.Y and box.high.Y > low.Y and box.low.Z < high.Z and box.high.Z > low.Z
				if overlaps and not ignoredBy(box, ignore) then
					table.insert(names, box.name)
				end
			end
			return names
		end,
	}
end

local function spawnAt(name, x, y, z, props)
	local spawn = object(name, props or {})
	spawn.Enabled = if spawn.Enabled == nil then true else spawn.Enabled
	spawn.Neutral = if spawn.Neutral == nil then true else spawn.Neutral
	spawn.center = Vector3.new(x, y, z)
	spawn.halfHeight = 0.5
	return spawn
end

local function box(name, low, high, owner)
	return { name = name, low = low, high = high, owner = owner }
end

-- The hub island: a floor whose top is at 22, and terrain from far below up to 21.5.
local hubFloor = object("Hub.Top", { center = Vector3.new(0, 20, 0), halfHeight = 2 })
local hub = {
	box("Terrain (LeafyGrass)", Vector3.new(-30, -20, -30), Vector3.new(30, 21.5, 30)),
	box("Hub.Top", Vector3.new(-30, 18, -30), Vector3.new(30, 22, 30), hubFloor),
}

-- WorldCheck -------------------------------------------------------------------

do
	-- The Baseplate template's spawn at the origin, under the island (the bug a player hit).
	local template = spawnAt("SpawnLocation", 0, 0.5, 0)
	local report = WorldCheck.run({ adapter = world(hub, { template }) })
	check(count(report, "spawn_buried") == 1, "a spawn under terrain is reported as buried")
	check(count(report, "spawn_clearance") == 1, "the space above a buried spawn is reported as blocked")
	check(report.errors == 2 and report.warnings == 0, "a single buried spawn gives two errors and no warning")
	check(string.find(report.findings[1].detail, "Hub.Top", 1, true) ~= nil, "the finding names what covers the spawn")
end

do
	-- The game's own spawn, standing on the floor.
	local spawn = spawnAt("Game.Spawn", 0, 22.5, 6)
	local report = WorldCheck.run({ adapter = world(hub, { spawn }) })
	check(report.errors == 0 and report.warnings == 0, "a spawn on top of the floor passes")
	check(report.checked.spawns == 1, "the enabled spawn is counted")
end

do
	local template = spawnAt("SpawnLocation", 0, 0.5, 0)
	local spawn = spawnAt("Game.Spawn", 0, 22.5, 6)
	local report = WorldCheck.run({ adapter = world(hub, { template, spawn }) })
	check(count(report, "multiple_spawns") == 1, "two enabled neutral spawns warn that Roblox picks at random")

	local off = spawnAt("SpawnLocation", 0, 0.5, 0, { Enabled = false })
	report = WorldCheck.run({ adapter = world(hub, { off, spawn }) })
	check(report.errors == 0 and report.warnings == 0 and report.checked.spawns == 1, "a disabled spawn is ignored")

	local a = spawnAt("A", 0, 22.5, 6, { attributes = { MultipleSpawnsIntended = true } })
	local b = spawnAt("B", 10, 22.5, 6)
	report = WorldCheck.run({ adapter = world(hub, { a, b }) })
	check(count(report, "multiple_spawns") == 0, "MultipleSpawnsIntended silences the pool warning")

	local red = spawnAt("Red", 0, 22.5, 6, { Neutral = false, TeamColor = "Bright red" })
	local blue = spawnAt("Blue", 10, 22.5, 6, { Neutral = false, TeamColor = "Bright blue" })
	report = WorldCheck.run({ adapter = world(hub, { red, blue }) })
	check(count(report, "multiple_spawns") == 0, "one spawn per team is not a shared pool")
end

do
	-- A roofed spawn inside a building is legitimate when marked.
	local roof = box("Temple.Roof", Vector3.new(-6, 30, -6), Vector3.new(6, 31, 6))
	local spawn = spawnAt("Temple.Spawn", 0, 22.5, 0, { attributes = { AllowCovered = true } })
	local report = WorldCheck.run({ adapter = world({ hub[1], hub[2], roof }, { spawn }) })
	check(count(report, "spawn_buried") == 0, "AllowCovered accepts a roof above a spawn")

	local low = box("Arch.Beam", Vector3.new(-6, 25, -6), Vector3.new(6, 26, 6))
	report = WorldCheck.run({ adapter = world({ hub[1], hub[2], low }, { spawn }) })
	check(count(report, "spawn_clearance") == 1, "a beam at head height still blocks a covered spawn")
end

do
	-- An island floating far overhead is sky; the same island just above is a roof.
	local spawn = spawnAt("Spawn", 0, 22.5, 0)
	local high = box("Isle6.Top", Vector3.new(-20, 120, -20), Vector3.new(20, 124, 20))
	local report = WorldCheck.run({ adapter = world({ hub[1], hub[2], high }, { spawn }) })
	check(count(report, "spawn_buried") == 0, "geometry far above a spawn is not cover")
	report = WorldCheck.run({ adapter = world({ hub[1], hub[2], high }, { spawn }), coverHeight = 150 })
	check(count(report, "spawn_buried") == 1, "the cover height is configurable")

	-- A pad too small for Roblox to spread players over.
	local tiny = spawnAt("Tiny", 0, 22.5, 0, { width = 2, depth = 6 })
	report = WorldCheck.run({ adapter = world(hub, { tiny }) })
	check(count(report, "spawn_small") == 1 and report.errors == 0, "a spawn under 4 studs on a side is a warning")
end

do
	-- Terrain that pokes a little above a spawn is within tolerance; a lot is not.
	local spawn = spawnAt("Spawn", 0, 21, 0)
	local bump = { box("Terrain (Grass)", Vector3.new(-30, -20, -30), Vector3.new(30, 21.8, 30)) }
	local report = WorldCheck.run({ adapter = world(bump, { spawn }) })
	check(count(report, "spawn_buried") == 0, "a surface 0.3 studs above the spawn top is tolerated")
	report = WorldCheck.run({ adapter = world(bump, { spawn }), tolerance = 0.1 })
	check(count(report, "spawn_buried") == 1, "the tolerance is configurable")
end

do
	-- Terrain grown over an invisible floor, and a canopy over a launch pad.
	local floor = object("Isle1.Top", { center = Vector3.new(78, 28, 0), halfHeight = 2 })
	local pad = object("Pad_Isle2_to_Isle3", { center = Vector3.new(38, 45.8, 84), halfHeight = 0.3 })
	local canopy = box("Decor.TreeTemplate.tree.Icosphere", Vector3.new(34, 50, 80), Vector3.new(42, 55, 88))
	local grown = box("Terrain (Rock)", Vector3.new(60, 0, -18), Vector3.new(96, 33, 18))
	local report = WorldCheck.run({
		adapter = world({ canopy, grown }, {}),
		floors = { floor },
		interactives = { pad },
	})
	check(count(report, "floor_covered") == 1, "terrain above a walkable floor is reported")
	check(count(report, "interactive_covered") == 1, "a canopy over a launch pad is reported")

	local clear = WorldCheck.run({ adapter = world({}, {}), floors = { floor }, interactives = { pad } })
	check(clear.errors == 0 and clear.checked.floor_covered == 1 and clear.checked.interactive_covered == 1, "uncovered floors and pads pass and are counted")
end

do
	local text = WorldCheck.format(WorldCheck.run({ adapter = world(hub, { spawnAt("SpawnLocation", 0, 0.5, 0) }) }))
	check(string.find(text, "WorldCheck: 2 error(s), 0 warning(s)", 1, true) == 1, "format leads with the totals")
	check(string.find(text, "[error] spawn_buried Workspace.SpawnLocation", 1, true) ~= nil, "format lists each finding")
end

-- A stub GUI tree ----------------------------------------------------------------

local function gui(className, name, props, children)
	local node = props or {}
	node.ClassName = className
	node.Name = name
	node.children = {}
	if node.Visible == nil then
		node.Visible = true
	end
	if node.BackgroundTransparency == nil and className ~= "UIStroke" then
		node.BackgroundTransparency = 1
	end
	node.GetAttribute = function(self, key)
		return (self.attributes or {})[key]
	end
	node.GetChildren = function(self)
		return self.children
	end
	node.GetDescendants = function(self)
		local list = {}
		local function walk(parent)
			for _, child in ipairs(parent.children) do
				table.insert(list, child)
				walk(child)
			end
		end
		walk(self)
		return list
	end
	node.GetFullName = function(self)
		return if self.Parent and self.Parent.GetFullName then self.Parent:GetFullName() .. "." .. self.Name else self.Name
	end
	for _, child in ipairs(children or {}) do
		child.Parent = node
		table.insert(node.children, child)
	end
	return node
end

local function px(x, y)
	return Vector2.new(x, y)
end
local function stroke()
	return gui("UIStroke", "UIStroke", { Enabled = true, Transparency = 0, ApplyStrokeMode = { Name = "Border" } })
end

do
	-- The shop that shipped: stroked glass cards inside the framed panel art, each
	-- with an icon in a stroked chip.
	local panel = gui("Frame", "Panel", { AbsoluteSize = px(1000, 440), AbsolutePosition = px(140, 100) }, {
		gui("ImageLabel", "Art", { Image = "rbxassetid://1", AbsoluteSize = px(1000, 440) }),
		gui("Frame", "Card", { BackgroundTransparency = 0.3, AbsoluteSize = px(290, 250) }, {
			stroke(),
			gui("Frame", "IconChip", { BackgroundTransparency = 0.2, AbsoluteSize = px(84, 84) }, {
				stroke(),
				gui("ImageLabel", "Icon", { Image = "rbxassetid://2", AbsoluteSize = px(64, 64) }),
			}),
			gui("TextLabel", "Title", { Text = "Bigger Backpack", TextFits = true, AbsoluteSize = px(200, 30) }, {
				gui("UIStroke", "Outline", { Enabled = true, Transparency = 0, ApplyStrokeMode = { Name = "Contextual" } }),
			}),
		}),
		gui("ImageButton", "Close", { Image = "rbxassetid://3", AbsoluteSize = px(62, 62), AbsolutePosition = px(1045, 103) }),
	})
	local report = UiCheck.audit(gui("ScreenGui", "GameUI", {}, { panel }))
	check(count(report, "stroke_in_framed_art") == 2, "stroked card and chip inside framed art are both reported")
	check(count(report, "bordered_icon") == 1, "an icon boxed in a stroked chip is reported")
	check(count(report, "art_stroke") == 0 and count(report, "art_background") == 0, "clean art is not reported")
	check(count(report, "text_overflow") == 0, "a contextual text outline is not a border, and fitting text passes")

	-- Deliberate chrome can opt out.
	local badge = gui("Frame", "Badge", { BackgroundTransparency = 0, AbsoluteSize = px(70, 70), attributes = { UiCheckIgnore = true } }, {
		gui("ImageLabel", "Icon", { Image = "rbxassetid://4", AbsoluteSize = px(56, 56) }),
	})
	check(UiCheck.audit(gui("ScreenGui", "Hud", {}, { badge })).errors == 0, "UiCheckIgnore on a chip silences the bordered icon check")

	-- Either kind of chrome alone is still a box around the icon.
	local strokeOnly = gui("Frame", "Ring", { AbsoluteSize = px(64, 64) }, {
		stroke(),
		gui("ImageLabel", "Icon", { Image = "rbxassetid://7", AbsoluteSize = px(48, 48) }),
	})
	local fillOnly = gui("Frame", "Disc", { BackgroundTransparency = 0.4, AbsoluteSize = px(64, 64) }, {
		gui("ImageLabel", "Icon", { Image = "rbxassetid://8", AbsoluteSize = px(48, 48) }),
	})
	local chips = UiCheck.audit(gui("ScreenGui", "Hud", {}, { strokeOnly, fillOnly }))
	check(count(chips, "bordered_icon") == 2, "a stroke-only ring and a fill-only disc around an icon are both reported")
end

do
	-- The same shop done right: cards are soft fills without strokes, icons sit bare.
	local root = gui("ScreenGui", "GameUI", {}, {
		gui("Frame", "Panel", { AbsoluteSize = px(1000, 440) }, {
			gui("ImageLabel", "Art", { Image = "rbxassetid://1", AbsoluteSize = px(1000, 440) }),
			gui("Frame", "Card", { BackgroundTransparency = 0.82, AbsoluteSize = px(290, 250) }, {
				gui("ImageLabel", "Icon", { Image = "rbxassetid://2", AbsoluteSize = px(96, 96) }),
				gui("TextLabel", "Price", { Text = "1.2K", TextFits = true, AbsoluteSize = px(120, 30) }),
			}),
		}),
	})
	local report = UiCheck.audit(root)
	check(report.errors == 0 and report.warnings == 0, "unstroked cards and bare icons pass")
	check(report.checked == 5, "every GUI object is visited")
end

do
	-- Art with a Roblox background or stroke, and text that does not fit.
	local root = gui("ScreenGui", "Hud", {}, {
		gui("ImageLabel", "Coin", { Image = "rbxassetid://5", BackgroundTransparency = 0, AbsoluteSize = px(48, 48) }, { stroke() }),
		gui("TextLabel", "Count", { Text = "1,234,567,890", TextFits = false, AbsoluteSize = px(40, 20) }),
		gui("TextLabel", "Hidden", { Text = "long", TextFits = false, Visible = false, AbsoluteSize = px(10, 10) }),
	})
	local report = UiCheck.audit(root)
	check(count(report, "art_background") == 1, "a visible background behind art is reported")
	check(count(report, "art_stroke") == 1, "a stroke around art is reported")
	check(count(report, "text_overflow") == 1, "visible text that does not fit is a warning; hidden text is skipped")
end

do
	-- Action-bar icons laid on a framed square plate, next to a coin on a wide buy button.
	local plate = gui("ImageButton", "SHOP", { Image = "rbxassetid://9", AbsoluteSize = px(119, 140) }, {
		gui("ImageLabel", "Icon", { Image = "rbxassetid://10", AbsoluteSize = px(74, 74) }),
	})
	local buy = gui("ImageButton", "Buy", { Image = "rbxassetid://11", AbsoluteSize = px(196, 80) }, {
		gui("ImageLabel", "Coin", { Image = "rbxassetid://12", AbsoluteSize = px(34, 34) }),
	})
	local layered = gui("ImageLabel", "Logo", { Image = "rbxassetid://13", AbsoluteSize = px(100, 100) }, {
		gui("ImageLabel", "Shine", { Image = "rbxassetid://14", AbsoluteSize = px(100, 100) }),
	})
	local report = UiCheck.audit(gui("ScreenGui", "Hud", {}, { plate, buy, layered }))
	check(count(report, "icon_on_plate") == 1, "an icon laid on a framed plate is reported")
	check(report.errors == 1, "a small coin on a wide button and a full-size overlay are not")

	-- A switch inside a framed settings panel keeps its outline.
	local settings = gui("Frame", "Panel", { AbsoluteSize = px(720, 400) }, {
		gui("ImageLabel", "Art", { Image = "rbxassetid://1", AbsoluteSize = px(720, 400) }),
		gui("Frame", "Row", { BackgroundTransparency = 0.8, AbsoluteSize = px(520, 58) }, {
			gui("TextButton", "Switch", { Text = "", TextFits = true, BackgroundTransparency = 0, AbsoluteSize = px(92, 40) }, { stroke() }),
		}),
	})
	check(UiCheck.audit(gui("ScreenGui", "Hud", {}, { settings })).errors == 0, "a control's outline inside framed art is not a second frame")
end

do
	-- A wide stat pill is a container, not a chip, so its icon is not boxed in.
	local root = gui("ScreenGui", "Hud", {}, {
		gui("Frame", "CoinsPill", { BackgroundTransparency = 0.35, AbsoluteSize = px(220, 56) }, {
			gui("ImageLabel", "Icon", { Image = "rbxassetid://6", AbsoluteSize = px(48, 48) }),
		}),
	})
	check(UiCheck.audit(root).errors == 0, "an icon in a wide pill is not a bordered icon")
end

do
	local shipped = table.concat({
		"local backdrop = Ui.new(\"TextButton\", { Name = \"ShopBackdrop\" })",
		"backdrop.Activated:Connect(onClose)",
		"close.Activated:Connect(onClose)",
		"-- shopBackdrop.MouseButton1Click:Connect(onClose) was the old wiring",
		"scrimFrame.InputBegan:Connect(function() end)",
	}, "\n")
	local report = UiCheck.lintSource(shipped, "Shop")
	check(count(report, "modal_closes_on_stray_click") == 2, "backdrop and scrim input handlers are reported, commented lines are not")
	check(report.findings[1] ~= nil and report.findings[1].subject == "Shop:2", "the finding points at the line")

	local fixed = "local backdrop = Ui.new(\"TextButton\", { Name = \"ShopBackdrop\", Active = true })\nclose.Activated:Connect(onClose)\nbackdrop:GetPropertyChangedSignal(\"Visible\"):Connect(sync)"
	check(UiCheck.lintSource(fixed, "Shop").errors == 0, "a backdrop that only sinks input passes")
	check(UiCheck.lintSource("backdrop.MouseEnter:Connect(playHover)", "Shop").errors == 0, "a backdrop signal that cannot be a click is not reported")
end

do
	local panel = gui("Frame", "Panel", { AbsolutePosition = px(200, 100), AbsoluteSize = px(800, 400) }, {
		gui("ImageButton", "Close", { Image = "rbxassetid://3", AbsolutePosition = px(920, 110), AbsoluteSize = px(60, 60) }),
		gui("TextButton", "Buy", { Text = "BUY", AbsolutePosition = px(200, 400), AbsoluteSize = px(400, 100) }),
	})
	local points = UiCheck.strayClickPoints(panel, px(1200, 700))
	local function hits(button)
		for _, point in ipairs(points) do
			local p, low, size = point.position, button.AbsolutePosition, button.AbsoluteSize
			if p.X >= low.X and p.X <= low.X + size.X and p.Y >= low.Y and p.Y <= low.Y + size.Y then
				return true
			end
		end
		return false
	end
	check(#points > 8, "stray click points cover the panel and the screen around it")
	check(not hits(panel.children[1]) and not hits(panel.children[2]), "no stray click point lands on a button")
	local outside = 0
	for _, point in ipairs(points) do
		if not string.find(point.label, "^panel") then
			outside += 1
		end
	end
	check(outside == 3, "three points fall outside the panel")
end

do
	local merged = UiCheck.merge({
		{ findings = { { check = "art_stroke", severity = "error", subject = "Hud.Coin", detail = "stroke" } }, errors = 1, warnings = 0, checked = 3 },
		{ findings = {}, errors = 0, warnings = 2, checked = 1 },
	})
	check(merged.errors == 1 and merged.warnings == 2 and merged.checked == 4 and #merged.findings == 1, "merge sums reports")
	check(string.find(UiCheck.format(merged), "UiCheck: 1 error(s), 2 warning(s), 4 checked", 1, true) == 1, "format leads with the totals")
end

-- Provenance: the positive claim, as a number -----------------------------------

do
	-- A HUD carrying one of each kind of surface: registered art, an unrecorded
	-- image, a primitive that admits it, and one that does not.
	local registry = {
		panel = { id = "rbxassetid://811", aspect = 2.27 },
		ammo = { id = "rbxassetid://822", aspect = 1 },
	}
	local root = gui("ScreenGui", "Hud", {}, {
		gui("Frame", "Root", { AbsoluteSize = px(1920, 1080) }, {
			gui("ImageLabel", "PanelArt", { Image = "rbxassetid://811", AbsoluteSize = px(720, 320) }),
			gui("ImageLabel", "AmmoIcon", { Image = "rbxassetid://822", AbsoluteSize = px(48, 48) }),
			gui("TextLabel", "AmmoCount", { Text = "30 / 120", TextFits = true, AbsoluteSize = px(160, 40) }),
			gui("ImageLabel", "StockDecal", { Image = "rbxassetid://999", AbsoluteSize = px(64, 64) }),
			gui("Frame", "HealthBar", { BackgroundTransparency = 0, AbsoluteSize = px(300, 18) }),
			gui("Frame", "Divider", { BackgroundTransparency = 0, AbsoluteSize = px(300, 2), attributes = { AllowPrimitive = true } }),
		}),
	})
	local report = UiCheck.provenance(root, registry)
	local tally = report.provenance
	check(tally.art == 2, "registered images count as generated art")
	check(tally.unregistered == 1, "an image outside the registry is unattributed")
	check(tally.primitive == 2, "both drawn frames count as primitive surfaces")
	check(tally.text == 1, "text labels are tallied beside the ratio")
	check(tally.surfaces == 5, "a transparent layout frame is not a surface")
	check(math.abs(tally.coverage - 0.4) < 1e-9, "coverage is generated art over drawn surfaces")
	check(count(report, "unregistered_image") == 1, "the unrecorded image is reported as an error")
	check(count(report, "primitive_surface") == 1, "AllowPrimitive silences the divider but not the health bar")
	check(report.errors == 1 and report.warnings == 1, "an unrecorded image fails, a primitive only warns")
	check(string.find(UiCheck.format(report), "40% generated", 1, true) ~= nil, "format prints the surface ratio")
end

do
	-- A screen built entirely from generated art: every surface is registered.
	local registry = { panel = { id = "rbxassetid://811" }, close = { id = "rbxassetid://812" } }
	local clean = gui("ScreenGui", "Loadout", {}, {
		gui("Frame", "Anchor", {}, {
			gui("ImageLabel", "Panel", { Image = "rbxassetid://811", AbsoluteSize = px(1000, 560) }),
			gui("ImageButton", "Close", { Image = "rbxassetid://812", AbsoluteSize = px(62, 62) }),
			gui("TextLabel", "Title", { Text = "LOADOUT", TextFits = true, AbsoluteSize = px(300, 48) }),
		}),
	})
	local report = UiCheck.provenance(clean, registry)
	check(report.errors == 0 and report.warnings == 0, "an all-generated screen reports nothing")
	check(report.provenance.coverage == 1, "an all-generated screen is 100% generated")

	-- The same screen rebuilt from Studio primitives is what provenance exists to catch.
	local primitives = gui("ScreenGui", "Loadout", {}, {
		gui("Frame", "Panel", { BackgroundTransparency = 0, AbsoluteSize = px(1000, 560) }, { stroke() }),
		gui("Frame", "Close", { BackgroundTransparency = 0, AbsoluteSize = px(62, 62) }),
	})
	local built = UiCheck.provenance(primitives, registry)
	check(built.provenance.coverage == 0, "a primitive-built screen scores zero")
	check(count(built, "primitive_surface") == 2, "every undeclared primitive surface is named")
end

do
	-- Without a registry the ratio is not evidence, and the report says so.
	local root = gui("ScreenGui", "Hud", {}, {
		gui("ImageLabel", "Art", { Image = "rbxassetid://5", AbsoluteSize = px(100, 100) }),
	})
	local report = UiCheck.provenance(root, nil)
	check(count(report, "provenance_no_registry") == 1, "a missing registry is called out")
	check(report.provenance.coverage == 1 and report.errors == 0, "without a registry no image can be judged unattributed")

	-- An id is an id however the registry and the property spell it.
	local spelled = gui("ScreenGui", "Hud", {}, {
		gui("ImageLabel", "A", { Image = "rbxassetid://811", AbsoluteSize = px(64, 64) }),
		gui("ImageLabel", "B", { Image = "http://www.roblox.com/asset/?id=822", AbsoluteSize = px(64, 64) }),
	})
	local matched = UiCheck.provenance(spelled, { a = "811", b = { id = "rbxassetid://822" } })
	check(matched.provenance.art == 2 and matched.errors == 0, "bare digits and an asset URL match rbxassetid ids")
end

print(("\n%d checks, %d failures"):format(checks, failures))
if failures > 0 then
	process.exit(1)
end
