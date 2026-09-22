# Fitting gear to the standard R15 rig

A rigid accessory needs no fitting tool, no skinning and no auto-rigging. It needs one correctly
named `Attachment`. The verified route is in SKILL.md §4 under rigid accessories; this page is how
to build one and what to check.

**Do not auto-rig a generated mesh for this.** A rigid accessory is welded, not skinned. Auto-rigging
returns a provider bone skeleton unrelated to the standard rig, which cannot drive a Roblox character
without retargeting — a much larger problem than the one you have.

## Build it

Publish the prepared artifact and wait for readiness using
`references/preparation-installation.md`. The returned Model asset ID is a container ID,
**not a MeshId**. Insert it through the exposed Studio MCP insertion tool, inspect its
hierarchy, and select the actual imported MeshPart. Preserve its mesh and texture data,
including any SurfaceAppearance; do not assign the Model ID to MeshId.

For a single-piece hat, pass that inspected MeshPart to this helper. Multi-part gear needs
an explicit assembly with the additional parts welded to its Handle; do not silently discard
parts or choose the first descendant. Attachment placement still requires measured fitting.

```lua
local function makeHat(importedMesh: MeshPart): Accessory
    assert(importedMesh:IsA("MeshPart"), "Select the imported MeshPart")
    local accessory = Instance.new("Accessory")
    accessory.Name = "GeneratedHat"

    local handle = importedMesh:Clone()
    handle.Name = "Handle"
    handle.Anchored = false
    handle.CanCollide = false
    handle.Massless = true
    handle.Parent = accessory

    local attachment = handle:FindFirstChild("HatAttachment")
    if not attachment then
        attachment = Instance.new("Attachment")
        attachment.Name = "HatAttachment"
        attachment.Parent = handle
    end
    assert(attachment:IsA("Attachment"), "HatAttachment must be an Attachment")
    attachment.CFrame = CFrame.new(0, -0.3, 0)

    return accessory
end

local humanoid = character:WaitForChild("Humanoid") :: Humanoid
humanoid:AddAccessory(makeHat(importedMesh))
```

`character` and `importedMesh` must resolve to the intended live character and inspected
imported part. Preserve the imported proportions; derive any size adjustment from measured
bounds and intended dimensions. The example attachment offset is not an automatic fit.

Roblox matches the `Attachment` name against the character's attachment of the same name and welds
them. `HatAttachment` is one of several on the head; enumerate `head:GetChildren()` to see the rest.

## Keep it light

Inspect geometry first using server `asset_prepare` when available, retaining
`metrics.source` and `metrics.prepared` from `references/preparation-installation.md`.
Compare measured triangles and dimensions with the intended gear budget in
`references/3d-assets.md`. Quality labels alone do not establish triangle counts.
Request paid `generation_remesh_3d` only when measurements show a budget problem and
the additional generation is authorized. Reinspect its result; do not remesh every hat.

## Inspect suspicious openings

A generated hat once had an unintended hole in its crown despite successful upload,
moderation and import. Inspect it from above and at play distance; a thumbnail is insufficient.
Intentional openings (a hat's underside, cups, banners) are not defects.

Use server preparation first. If supplementary topology evidence is needed and source
bytes are available, run `scripts/glb_quality.py hat.glb`. Its boundary counts are advisory,
per primitive, with positions rounded to six decimals. Material boundaries can appear open,
and nearby vertices can merge. Unsupported geometry is not a passing inspection.
Inspect suspicious regions in Studio and record caller-reported evidence. A nonzero boundary
count alone must not reject the asset or trigger repair or paid regeneration.

## Check the fit in Play

On the live character, not the template:

- the `Accessory` is parented to the character and its `Handle` carries the expected `Attachment`
- the offset is what you intended — measure it rather than eyeballing:
  `print((handle.Position - head.Position).Y)`. A hat built this way measured 0.84 and 0.88 studs above
  head centre in two Play runs; treat that as the shape of the answer, not a target, since it
  depends on the mesh.
- the gear reads correctly from the sides **and from above**, which is where an open mesh shows
- the thumbnail is not a check — the thumbnail is what hid the hole
