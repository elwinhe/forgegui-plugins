# Dressing a character beyond the default avatar

Three separate pieces make a player look generated rather than default: clothing, a face, and gear.
Gear is in `accessories.md`; this page covers the first two, plus applying them at spawn.

## Clothing is just an uploaded image

An `assetType: "Image"` id works **directly** as `Shirt.ShirtTemplate` and `Pants.PantsTemplate`.
There is no separate clothing upload, and Open Cloud cannot upload `Shirt` or `Pants` assets —
it does not need to for in-experience clothing.

```lua
local shirt = Instance.new("Shirt")
shirt.ShirtTemplate = "rbxassetid://<image id>"
shirt.Parent = character
```

Verified: templates set to plain Image ids preloaded successfully and the image wrapped onto the
torso and limbs on a standard R15 dummy.

Generate with `generation_image` type `clothing_shirt` / `clothing_pants`, which lay the art out on
the classic template. **Check the returned dimensions** rather than assuming: a request that should
produce a template can come back at an unrelated aspect, and a template image at the wrong size wraps
visibly wrong. The one measured here came back 585x559.

Any image is *accepted* as a clothing template — the engine will not reject a texture, a photograph or
a skybox face. Accepted is not the same as correct; only a template-laid-out image wraps properly.

## The face is a Decal, not clothing

Set a `Decal` on the `Head` with the generated image as its `Texture`. It does not go through the
clothing properties.

Note what this category can and cannot demonstrate: a generated face at play distance can read as a
plain default smiley, and only the asset id proves otherwise. If the face is meant to be visible
evidence, check it at the distance a player sees it, not in a close-up.

## Apply at spawn, and strip the defaults

Do this on `CharacterAdded`, and **remove the default accessories** first — a generated look with the
stock avatar's hat and hair still reads as default. Set an attribute once applied so a later check can
confirm it happened rather than assuming.

Order: strip defaults → clothing → face → gear.

## Check before you call it done

Read the properties back **off the live character in Play**, not off the template you built:

- `Shirt.ShirtTemplate` and `Pants.PantsTemplate` hold the ids you set
- the `Head` carries a `Decal` with the face id
- the default accessories are gone
- the attribute you set is present

A character built correctly in Edit and never checked in Play is the most common way this category
silently fails, because `StarterCharacter` handling and spawn timing differ between them.
