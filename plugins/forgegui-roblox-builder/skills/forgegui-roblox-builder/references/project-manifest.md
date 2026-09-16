# Project manifest: `forgegui-project.json`

One file per game project, kept in the working directory the agent runs from. It is **client-side bookkeeping**: it lets a new chat resume the same art direction and reuse existing artifacts. It is not server-side reference memory or a guarantee of generation quality. Pass relevant references only in fields supported by the live tool.

## Why it exists

- When no owner-scoped job listing is exposed, the ledger retains the IDs a new session needs to resume work without duplicate generation.
- Keep `art_direction`, palette, and material language consistent unless the user changes the look. `game_style` is a routing type, not a description; it stays fixed per project.
- Content references and style references must stay separate so "this exact sword" and "this world's look" do not get mixed.

## Shape

Illustrative IDs below are placeholders, not usable assets. Start a real project from `forgegui-project.example.json` and record returned identifiers.

```json
{
  "version": 1,
  "project": "Crystal Mine",
  "updated": "2026-09-15T21:40:00Z",
  "game_style": "roblox",
  "art_direction": "stylized low-poly, chunky silhouettes, soft cel shading, warm underground glow",
  "palette": ["#2B1F3A", "#6E4BFF", "#F5C86B", "#E8E4DD"],
  "material_language": "matte painted wood, brushed bronze, glowing crystal with soft emissive edges",
  "style_refs": ["mcp-artifact:00000000-0000-4000-8000-000000000001:0"],
  "assets": [
    {
      "key": "hud.panel",
      "kind": "gui_panel",
      "prompt_summary": "inventory panel, transparent corners, bronze trim",
      "request_id": "crystal-hud-panel-v1",
      "job_id": "00000000-0000-4000-8000-000000000001",
      "artifact_ref": "mcp-artifact:00000000-0000-4000-8000-000000000001:0",
      "roblox_asset_id": "ROBLOX_ASSET_ID",
      "studio_path": "StarterGui.HUD.Inventory",
      "verified": "screenshot 2026-09-15",
      "status": "inserted"
    }
  ]
}
```

Fields:

| Field | Meaning |
| --- | --- |
| `game_style` | Backend routing type passed as `game_style` on every generation that accepts it: `roblox`, `fortnite`, `minecraft`, or `general`. Default `roblox`; use `general` for non-Roblox-looking art. The other two routes are not fully built out, so do not pick them without a reason. Never put descriptive styling here. |
| `art_direction` | The descriptive look of the world (silhouette language, shading, mood). Goes into every prompt verbatim, never into `game_style`. |
| `palette` | Hex colors named in prompts and used for Studio UI/lighting choices. |
| `material_language` | Sentence used verbatim in 3D and GUI prompts. |
| `style_refs` | Relevant theme-pack or hero-asset references passed in `reference_asset_ids` when the tool accepts them. |
| `assets[].key` | Stable human name (`hud.panel`, `prop.tree.pine`). |
| `assets[].artifact_ref` | The content reference to pass when regenerating or deriving *this object*. |
| `assets[].roblox_asset_id` / `studio_path` | Filled after import; a URL is never written here. |
| `assets[].status` | `planned`, `generating`, `generated`, `handoff`, `inserted`, `verified`, `failed`. |

## Rules

1. Read the manifest before planning. If `assets` already has the item with a `roblox_asset_id` or `artifact_ref`, reuse it; do not generate again. Entries that are `planned`, `generating`, or `failed` carry no reusable output; check job status before generating.
2. Write the ledger entry when the job is accepted, not after it succeeds, so a lost session can still recover the job.
3. Keep `style_refs` short (one to three). A style reference is not a content reference; do not put every generated asset in `style_refs`.
4. Never store keys, tokens, headers, or account ids in the manifest.
5. When a ForgeGUI listing tool becomes available, the server record wins over the manifest; reconcile and keep the manifest as a cache.
