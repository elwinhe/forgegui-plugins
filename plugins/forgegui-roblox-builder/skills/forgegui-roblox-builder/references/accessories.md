# Fitting gear to the standard R15 rig

A rigid accessory needs no fitting tool, no auto-rigging and no skinning. It needs one correctly
named `Attachment`.

## The route

1. `Accessory` instance.
2. A `Handle` part inside it, carrying the generated mesh.
3. An `Attachment` inside the `Handle`, **named for the attachment point it targets** —
   `HatAttachment` for a hat.
4. `Humanoid:AddAccessory(accessory)`.

Roblox matches the `Attachment` name against the character's own attachment of the same name and
welds the two together. Verified on a standard R15: the handle seated 0.88 studs above head centre,
sitting on top of the head with no gap.

The attachment's own `CFrame` offsets the mesh relative to that point, so nudge the fit there rather
than by moving the `Handle`.

**Do not auto-rig a generated mesh for this.** A rigid accessory is welded, not skinned. Auto-rigging
returns a provider bone skeleton that has nothing to do with R15 and cannot drive a Roblox character
without retargeting — an entirely different and much larger problem than the one you have.

## Keep it light

Accessories want roughly 4k triangles or fewer. A generated mesh at default quality comes back far
heavier than that and needs remeshing before it goes on a head.

## Check the mesh is closed before you upload it

**This is the failure that reached a player's head.** A generated hat had a hole in its crown. It
uploaded cleanly, passed moderation, imported into Studio without a warning, and its thumbnail hid the
hole entirely. It was caught only by walking around the character in Play — and the workaround was a
primitive cap welded over the gap.

Neither Open Cloud, nor moderation, nor the Studio import checks whether a surface is closed. Count the GLB's boundary edges before
uploading — an edge used by exactly one triangle means an open surface — and treat a non-zero count as a
rejection, not a warning. The mesh topology gate change ships a script that does this; until it lands,
do the count yourself rather than skipping it.

## Check the fit in Play

On the live character, not the template:

- the `Accessory` is present under the character
- its `Handle` has an `Attachment` with the expected name
- the handle's position relative to the head is what you intended — measure it, do not eyeball it
- the gear is visible from the sides and from **above**, which is where an open mesh shows

A thumbnail is not a check. The thumbnail is what hid the hole.
