# Dressing a character beyond the default avatar

Clothing, a face, and gear. Gear is in `accessories.md`; this page covers clothing and the face,
plus applying them at spawn.

## Clothing is an uploaded image

An `assetType: "Image"` id works directly as `Shirt.ShirtTemplate` and `Pants.PantsTemplate` — the
verified route is in SKILL.md §4 under clothing. Upload the image first (SKILL.md §4,
`references/preparation-installation.md`), then use the returned id.

Generate with `generation_image` type `clothing_shirt` / `clothing_pants`, which lay the art out on
the classic template. **Target the classic template size, 585x559**, and check what came back before
uploading: any image is *accepted* as a clothing template — a photograph or a skybox face will not be
rejected — but only a template-laid-out image at the right proportions wraps correctly. If a
generation comes back at another size, regenerate rather than stretching it.

## The face is a Decal, and the default one is already there

A character head ships with a `face` Decal. Adding another one leaves two decals competing, which
reads as the stock face rather than the generated one. **Replace the existing decal's `Texture`
rather than adding a second**, and set `Face` so it points forward.

## Apply at spawn

```lua
local Players = game:GetService("Players")

local SHIRT, PANTS, FACE = "rbxassetid://0", "rbxassetid://0", "rbxassetid://0"

local function dress(character: Model)
    local humanoid = character:WaitForChild("Humanoid") :: Humanoid

    -- Strip the stock hat and hair, or a generated look still reads as default.
    humanoid:RemoveAccessories()

    local shirt = character:FindFirstChildOfClass("Shirt") or Instance.new("Shirt")
    shirt.ShirtTemplate = SHIRT
    shirt.Parent = character

    local pants = character:FindFirstChildOfClass("Pants") or Instance.new("Pants")
    pants.PantsTemplate = PANTS
    pants.Parent = character

    -- Reuse the existing face Decal instead of adding a second one.
    local head = character:WaitForChild("Head") :: BasePart
    local face = head:FindFirstChild("face") or head:FindFirstChildOfClass("Decal") or Instance.new("Decal")
    face.Name = "face"
    ;(face :: Decal).Texture = FACE
    ;(face :: Decal).Face = Enum.NormalId.Front
    face.Parent = head

    character:SetAttribute("GeneratedLookApplied", true)
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAppearanceLoaded:Connect(dress)
end)
```

Wait for `CharacterAppearanceLoaded` rather than `CharacterAdded`: the default appearance can land
after your edit otherwise and overwrite it. The attribute is what a later check reads, so it has a
fixed name rather than one each builder invents.

## Check before you call it done

Read these **off the live character in Play**, not off the template you built. Spawn timing differs
between Edit and Play, and a look applied correctly in Edit is the most common silent failure here.

- `Shirt.ShirtTemplate` and `Pants.PantsTemplate` hold the ids you set
- the `Head` has exactly **one** Decal, carrying the face id
- no stock accessories remain
- `character:GetAttribute("GeneratedLookApplied")` is `true`
- the face is looked at **at play distance**, not in a close-up — a generated face can read as a
  plain default smiley from where a player actually sees it, and only the id proves otherwise
