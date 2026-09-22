# Fitting gear to the standard R15 rig

A rigid accessory needs no fitting tool, no skinning and no auto-rigging. It needs one correctly
named `Attachment`. The verified route is in SKILL.md §4 under rigid accessories; this page is how
to build one and what to check.

**Do not auto-rig a generated mesh for this.** A rigid accessory is welded, not skinned. Auto-rigging
returns a provider bone skeleton unrelated to the standard rig, which cannot drive a Roblox character
without retargeting — a much larger problem than the one you have.

## Build it

Upload the mesh first as `assetType: "Model"` (SKILL.md §4) and use the returned id.

```lua
local MESH_ID = "rbxassetid://0"
local TEXTURE_ID = "rbxassetid://0"

local function makeHat(): Accessory
    local accessory = Instance.new("Accessory")
    accessory.Name = "GeneratedHat"

    local handle = Instance.new("MeshPart")
    handle.Name = "Handle"            -- the name matters; AddAccessory looks for it
    handle.MeshId = MESH_ID
    handle.TextureID = TEXTURE_ID
    handle.Size = Vector3.new(1.4, 1.2, 1.4)
    handle.CanCollide = false
    handle.Massless = true
    handle.Parent = accessory

    -- The name is what Roblox matches against the character's own attachment.
    local attachment = Instance.new("Attachment")
    attachment.Name = "HatAttachment"
    attachment.CFrame = CFrame.new(0, -0.3, 0)   -- nudge the fit here, not by moving the Handle
    attachment.Parent = handle

    return accessory
end

-- on a character with a Humanoid
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
humanoid:AddAccessory(makeHat())
```

Roblox matches the `Attachment` name against the character's attachment of the same name and welds
them. `HatAttachment` is one of several on the head; enumerate `head:GetChildren()` to see the rest.

## Keep it light

Remesh before upload with `generation_remesh_3d` — budgets and arguments are in
`references/3d-assets.md`, where a hat falls in the kit-prop range. A generated mesh at high quality
comes back far over that and must be remeshed; at standard quality it is closer but still worth
checking.

## Check the mesh is closed before you upload it

**This is the failure that reached a player's head.** A generated hat had a hole in its crown; it
uploaded, moderated, imported and thumbnailed without a single warning, and was caught only by
walking around the character in Play. The full account and the threshold are in SKILL.md §4 under
the mesh topology check.

Count boundary edges before uploading — an edge used by exactly one triangle means an open surface —
and treat a non-zero count as a rejection, not a warning. `scripts/glb_quality.py` reports
`boundary_edges` per mesh:

```sh
python3 scripts/glb_quality.py hat.glb
```

## Check the fit in Play

On the live character, not the template:

- the `Accessory` is parented to the character and its `Handle` carries the expected `Attachment`
- the offset is what you intended — measure it rather than eyeballing:
  `print((handle.Position - head.Position).Y)`. A hat built this way measured 0.84 and 0.88 studs above
  head centre in two Play runs; treat that as the shape of the answer, not a target, since it
  depends on the mesh.
- the gear reads correctly from the sides **and from above**, which is where an open mesh shows
- the thumbnail is not a check — the thumbnail is what hid the hole
