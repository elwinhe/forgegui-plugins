local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local source = "plugins/forgegui-roblox-builder/skills/forgegui-roblox-builder/references/luau/LocalPlaceIdentity.luau"
local function load() return luau.load(fs.readFile(source))() end
local a = "12345678-1234-4234-8234-123456789abc"
local b = "12345678-1234-4234-9234-123456789abc"
local writes = 0
local function model(attrs, edit, broken)
    local storage = {}
    function storage:GetAttribute(key) return attrs[key] end
    function storage:SetAttribute(key, value)
        writes += 1
        if not broken then attrs[key] = value end
    end
    local run = { IsStudio = function() return true end, IsEdit = function() return edit ~= false end,
        IsRunning = function() return edit == false end }
    return { PlaceId = 0, GameId = 0, Name = "Unsaved", GetService = function(_, name)
        return if name == "ServerStorage" then storage else run
    end }
end
local function rejects(fn, pattern)
    local ok, err = pcall(fn)
    assert(not ok and string.find(tostring(err), pattern), tostring(err))
end
local attrs = {}
local place = model(attrs)
local first = load().probe(place, a)
assert(first.created and first.local_place_id == a and first.place_id == nil and first.universe_id == nil)
assert(writes == 1)
-- Fresh module/session ignores a different candidate and retains the attribute.
assert(load().probe(place, b).local_place_id == a and writes == 1)
-- Persisted-attribute snapshot roundtrip models save/reopen; actual Studio save
-- and reopen is a separate live acceptance check, not claimed by this mock.
local reopened = model(serde.decode("json", serde.encode("json", attrs)))
assert(load().probe(reopened, b).local_place_id == a)
local blank = model({})
assert(load().probe(blank, b).local_place_id == b)
place.PlaceId, place.GameId = 123456789, 987654321
local published = load().probe(place, b)
assert(published.local_place_id == a and published.place_id == "123456789" and published.universe_id == "987654321")
local copied = model(table.clone(attrs))
assert(load().probe(copied, b).local_place_id == a, "copies inherit identity until explicit fork")
local before = writes
rejects(function() load().probe(model({}, false), a) end, "Edit")
rejects(function() load().probe(model({ ForgeGUI_LocalPlaceId = "invalid" }), a) end, "Invalid")
rejects(function() load().probe(model({ ForgeGUI_LocalPlaceId = 123 }), a) end, "Invalid")
rejects(function() load().probe(model({}), "invented") end, "cryptographic")
local unsafe = model({}); unsafe.PlaceId = 9007199254740992
rejects(function() load().probe(unsafe, a) end, "exactly")
assert(writes == before, "invalid observations never write")
rejects(function() load().probe(model({}, true, true), a) end, "readback")
-- Explicit user-directed fork clears only the attribute in the selected copy.
local forkAttrs = table.clone(attrs); forkAttrs.ForgeGUI_LocalPlaceId = nil
assert(load().probe(model(forkAttrs), b).local_place_id == b)
assert(attrs.ForgeGUI_LocalPlaceId == a)
print("Local place Luau lifecycle: reuse, blank separation, publication, copied-file fork, Edit guard, invalid attribute, precision and readback passed")
