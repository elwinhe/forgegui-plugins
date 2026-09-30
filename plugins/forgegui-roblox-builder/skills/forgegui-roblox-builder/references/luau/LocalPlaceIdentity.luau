-- Run only through the explicitly selected Studio Edit data model.
-- candidate is a fresh OS-random UUIDv4 emitted by local_place_identity.py,
-- never a manifest, model-generated, session, file-name or global identity.
local Identity = {}
Identity.attribute = "ForgeGUI_LocalPlaceId"
local function valid(value)
    return type(value) == "string" and #value == 36 and string.match(string.lower(value),
        "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end
local function decimal(value)
    assert(type(value) == "number" and value >= 0 and value <= 9007199254740991 and value % 1 == 0,
        "ID cannot be represented exactly by this numeric probe")
    if value == 0 then return nil end
    return string.format("%.0f", value)
end
function Identity.probe(model, candidate)
    local run = model:GetService("RunService")
    assert(run:IsStudio() and run:IsEdit() and not run:IsRunning(), "Select the Studio Edit data model; stop playtest first")
    -- Validate observations before any mutation. Zero means absent, not identity.
    local place = decimal(model.PlaceId)
    local universe = decimal(model.GameId)
    local storage = model:GetService("ServerStorage")
    local value = storage:GetAttribute(Identity.attribute)
    local created = false
    if value == nil then
        assert(valid(candidate), "A fresh cryptographic UUIDv4 candidate is required")
        value = string.lower(candidate)
        storage:SetAttribute(Identity.attribute, value)
        created = true
    else
        assert(valid(value), "Invalid ForgeGUI_LocalPlaceId attribute; reconcile explicitly, never overwrite automatically")
    end
    assert(storage:GetAttribute(Identity.attribute) == value, "Local place identity readback failed")
    return {
        local_place_id = string.lower(value), place_id = place, universe_id = universe,
        name = model.Name, created = created, edit_mode = true,
        persistence = "Save this Edit place to .rbxl/.rbxlx to retain identity after close; Roblox publication is not required",
    }
end
return Identity
