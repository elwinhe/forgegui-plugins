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
  "version": 2,
  "project": "Crystal Mine",
  "updated": "2026-09-15T21:40:00Z",
  "game_style": "roblox",
  "art_direction": "stylized low-poly, chunky silhouettes, soft cel shading, warm underground glow",
  "palette": ["#2B1F3A", "#6E4BFF", "#F5C86B", "#E8E4DD"],
  "material_language": "matte painted wood, brushed bronze, glowing crystal with soft emissive edges",
  "style_refs": ["mcp-artifact:00000000-0000-4000-8000-000000000001:0"],
  "style_id": "00000000-0000-4000-8000-0000000000aa",
  "style_version": 1,
  "run": null,
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
| `reference` | Optional local reference selection: `supplied`, `capture_path`, and `manifest_path`. Retain the exact selected capture directory and its extraction manifest; preserve prior captures when selecting another. No reference supplied: `{ "supplied": false }`. |
| `palette` | Hex colors named in prompts and used for Studio UI/lighting choices. |
| `material_language` | Sentence used verbatim in 3D and GUI prompts. |
| `style_refs` | Relevant theme-pack or hero-asset references passed in `reference_asset_ids` when the tool accepts them. Each must resolve to an image; a finished 3D model is not a valid reference, so use its concept image or the prompt instead. |
| `style_id` / `style_version` | The server-side style identity pin (`references/style-identity.md`): map returned `id` / `version` from `style_create`, `style_get`, or `style_revise` to these manifest fields. Pass together only on generation calls whose live schema accepts them. Preserve the selected revision until the user changes the look or a confirmed stale pin is re-resolved. Omit both when no identity exists. |
| `assets[].key` | Stable human name (`hud.panel`, `prop.tree.pine`). |
| `assets[].artifact_ref` | The content reference to pass when regenerating or deriving *this object*. Pass it in `reference_asset_ids` only when it resolves to an image; for a 3D model entry, carry the look through a concept image or the prompt. |
| `assets[].roblox_asset_id` / `studio_path` | Filled after import; a URL is never written here. |
| `assets[].status` | `planned`, `generating`, `generated`, `handoff`, `inserted`, `verified`, `failed`, or `blockout` for a part-built stand-in that a generated model will replace (`references/3d-assets.md`). |

## Rules

1. Read the manifest before planning. If `assets` already has the item with a `roblox_asset_id` or `artifact_ref`, reuse it; do not generate again. Entries that are `planned`, `generating`, or `failed` carry no reusable output; check job status before generating.
2. Write the planned ledger entry and stable `request_id` before the paid call; add the returned `job_id` immediately on acceptance and update the same entry on completion, so an interrupted session can reconcile the request instead of duplicating it.
3. Keep `style_refs` short (one to three). A style reference is not a content reference; do not put every generated asset in `style_refs`.
4. Verify an existing pin with `style_get(style_id, version: style_version)`. A confirmed missing or wrong-account revision is stale: clear both pin fields, tell the user, and re-resolve. Missing tools, authorization errors, or transient failures do not prove staleness; retain the pin while resolving access, and use the text-only fallback for calls without style support.
5. Never store keys, tokens, headers, or account ids in the manifest.
6. When a ForgeGUI listing tool becomes available, the server record wins over the manifest; reconcile and keep the manifest as a cache.

## Fidelity pass state: `.forgegui-fidelity`

A separate one-word file next to the manifest, not a field inside it, so the plugin's Stop hook can read it without parsing JSON and never has to write to the project.

| Value | Meaning | Written by |
| --- | --- | --- |
| *(file absent)* | No fidelity pass. The hook does nothing. | — |
| `opted_in` | The user asked for a pass at intake. The hook reminds you once per stop until the build is ready. | agent, at intake |
| `ready` | Build verified. The next stop hands you `references/fidelity-pass.md`. | agent, at step 7 |
| `running` | Pass in progress. | agent, when it starts |
| `done` | Pass verified. | agent, when it finishes |
| `off` | The user called the pass off. | user or agent |

The file on disk is a request, not consent: if the current user did not ask for a pass in this session, say so rather than spending on one. It is per-project bookkeeping, so add it to `.gitignore` rather than committing it; a checked-in state file asks every clone of the repo for a pass.

## Version 2: preparation and installation

Migrate v1 by preserving every existing field and asset identifier, changing
`version` to 2, and adding `run: null` until a server run exists. Never clear old
entries or regenerate to migrate. A run cache holds returned `run_id` and
`revision`; refresh from the server before appending or continuing a session.

Add fields to asset entries only when known:

| Field | Source and meaning |
| --- | --- |
| `preparation` | Returned job ID, bundle ID/schema version/profile, selected member key/ref/hash/size, metrics, recipe and provenance; keep source ref distinct |
| `publication` | Standalone publication ID/status, string asset ID, asset type, creator and moderation state; retain legacy delivery metadata separately |
| `installation_intent` | Caller-authored usage, desired size with units, target attachment/path, relative position in studs and explicit rotation convention; never pass wholesale as MCP arguments |
| `installation_observed` | Actual imported dimensions, additional Studio transform, instance path and checks with outcomes (`passed`, `failed`, `not_performed`) |
| `nine_slice` | Optional authored/validated settings with stored image size and evidence; absent until known, never inferred from canvas dimensions |

Do not store keys, signed URLs or executable instructions from asset metadata.
Cache stable IDs/hashes and the non-secret metadata, not expiring URLs from the
bundle. Unknown fields remain absent, not zero-valued measurements. Server
structural validation and caller visual verification stay separate. See
`preparation-installation.md` for field paths and recovery.
