# Project manifest: `forgegui-project.json`

One file per game project, kept in the working directory the agent runs from. It is **client-side bookkeeping**: it lets a new chat resume the same art direction and reuse existing artifacts. It is not server-side reference memory, and it does not make the model's first shot better on its own. Denser prompts and real `reference_asset_ids` do that.

## Why it exists

- A new session cannot list prior generations (no owner-scoped listing tool yet). Without a ledger the agent regenerates, paying twice and drifting the style.
- `game_style`, palette, and material language must be identical across every call in a project, or the assets stop looking like one game.
- Content references and style references must stay separate so "this exact sword" and "this world's look" do not get mixed.

## Shape

```json
{
  "version": 1,
  "project": "Crystal Mine",
  "updated": "2026-09-15T21:40:00Z",
  "game_style": "stylized low-poly, chunky silhouettes, soft cel shading, warm underground glow",
  "palette": ["#2B1F3A", "#6E4BFF", "#F5C86B", "#E8E4DD"],
  "material_language": "matte painted wood, brushed bronze, glowing crystal with soft emissive edges",
  "style_refs": ["mcp-artifact:1096a2f6-fe2f-44b2-b26d-4064f4341c4c:0"],
  "assets": [
    {
      "key": "hud.panel",
      "kind": "gui_panel",
      "prompt_summary": "inventory panel, transparent corners, bronze trim",
      "request_id": "crystal-hud-panel-v1",
      "job_id": "1096a2f6-fe2f-44b2-b26d-4064f4341c4c",
      "artifact_ref": "mcp-artifact:1096a2f6-fe2f-44b2-b26d-4064f4341c4c:0",
      "roblox_asset_id": "106938821097585",
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
| `game_style` | The exact string passed as `game_style` on every generation that accepts it. Never paraphrase it per call. |
| `palette` | Hex colors named in prompts and used for Studio UI/lighting choices. |
| `material_language` | Sentence used verbatim in 3D and GUI prompts. |
| `style_refs` | Artifact references passed in `reference_asset_ids` on **every** generation in the project. Theme pack or hero asset. |
| `assets[].key` | Stable human name (`hud.panel`, `prop.tree.pine`). |
| `assets[].artifact_ref` | The content reference to pass when regenerating or deriving *this object*. |
| `assets[].roblox_asset_id` / `studio_path` | Filled after import; a URL is never written here. |
| `assets[].status` | `planned`, `generating`, `generated`, `handoff`, `inserted`, `verified`, `failed`. |

## Rules

1. Read the manifest before planning. If `assets` already has the item, reuse its `roblox_asset_id` or `artifact_ref`; do not generate again.
2. Write the ledger entry when the job is accepted, not after it succeeds, so a lost session can still recover the job.
3. Keep `style_refs` short (one to three). A style reference is not a content reference; do not put every generated asset in `style_refs`.
4. Never store keys, tokens, headers, or account ids in the manifest.
5. When a ForgeGUI listing tool becomes available, the server record wins over the manifest; reconcile and keep the manifest as a cache.
