# Style identities

A style identity is an account-owned, server-side record of a project's look: a name, a detailed brief, and up to four owned reference images. Pinning preserves the same style inputs across sessions and machines without re-pasting the brief; visual consistency still requires inspection. The tool family is `style_list`, `style_get`, `style_create`, `style_revise`, and `generations_by_style`.

**These tools may not be exposed yet.** Discover the live tool list first (SKILL.md §1). When the family is absent, use the manifest's `art_direction`, `material_language`, and `style_refs` exactly as before and say nothing about styles being unavailable unless the user asks. Never treat a missing style tool as an error or substitute another endpoint.

## Resolve one identity per project

Do this once, before the first paid visual generation, not per asset:

1. If the manifest has a pin, call `style_get` with its `style_id` and `version: style_version` and preserve that revision when it still matches the project. Otherwise use `style_list` to find candidates, then `style_get` to inspect their briefs and reference images: list results contain identity metadata and `current_version`, not the brief. Reuse a matching identity rather than recreating it. Follow the manifest's stale-pin rule; do not discard a pin on a transient error or silently advance it to the latest revision.
2. No match: `style_create` with
   - `name` — short and stable (≤ 120 chars), e.g. `"Crystal Mine — warm low-poly"`.
   - `detailed_brief` (≤ 8000 chars) — the intake style answer plus the manifest's `art_direction`, `palette` words, and `material_language`, written as full sentences. This brief is the reusable style contract; write it as carefully as a generation prompt.
   - `reference_asset_ids` — up to 4 account-owned image UUIDs or image-backed `mcp-artifact:<job>:<index>` references, as supported by the live schema. `style_create` and `style_revise` copy and register image artifacts at write time, deduplicating by owner and SHA-256; an existing image artifact does not need a separate upload. Every reference must resolve to an image: finished `generation_model_3d` artifacts and audio are invalid, even when their identifier format is valid. Use a concept image or the written brief instead.
3. Map the returned `id` to manifest `style_id` and returned `version` to `style_version` (also the selected revision returned by `style_get`). Pass the pair together only on generation calls whose live schema supports it; currently the inspected contract exposes it on `generation_model_3d`.

Style management calls do not charge credits, but creating/revising styles and authorizing/registering uploads require `generation:write`; style reads require `generation:read`.

## User-supplied style images

A pasted or local image is not a reference until it is an owned asset. When the upload family is exposed: `image_upload_authorize` (PNG, JPEG, or WebP, ≤ 12 MiB — returns a bounded signed upload), upload the bytes, then `image_upload_register` with the `upload_id` to verify and register the immutable owned image before the returned registration deadline. The returned asset UUID is valid in `style_create`/`style_revise` `reference_asset_ids` and in per-call reference fields. Neither call charges credits. If the upload family is absent, say so and build the brief from words plus existing owned image references; existing image-backed `mcp-artifact:` references can still be passed directly when the style schema accepts them.

## Pinning generations

On `generation_model_3d` (and any other generation whose live schema shows the fields):

- Pass `style_id` and `style_version` from the manifest on every call. Together or neither — never one.
- `style_brief` (≤ 4000 chars) and `style_reference_asset_ids` (≤ 4) are per-call *additions* layered on the pinned identity — for one asset that needs an extra nuance ("this one is ceremonial, gilded"). They are rejected without `style_id`/`style_version`. They do not modify the saved identity.
- Each per-call reference array has at most 4 entries, and combined `reference_asset_ids` + `style_reference_asset_ids` cannot exceed 6. The resolved limit also includes saved style images: object references plus the deduplicated union of saved and per-call style references must total at most 6. Inspect the pinned revision's saved references before adding per-call references. All must resolve to images; finished model artifacts are invalid in either array. Content references still describe *this object*; style fields describe the world. Do not duplicate an ID across both.
- `game_style` remains the routing type and is unchanged by any of this.

`generations_by_style` lists the account's generations pinned to an identity — use it to find reusable prior output before generating (SKILL.md §3 reuse rule applies).

## Revising a look

Revisions are immutable and appended: `style_revise` with `style_id`, `expected_version` (the version you believe is latest — a mismatch means someone else revised; re-read with `style_get` before retrying), the full new `detailed_brief`, and the full image-backed `reference_asset_ids` array (it replaces, not merges, and accepts the same UUID or artifact references as creation). Then map the returned `version` to the manifest's `style_version` pin. Existing generations never change retroactively; regenerate anything that must match the new revision only when authorized within the normal spend rules.

Do not revise the identity to serve one asset — that is what per-call `style_brief` is for. Revise when the *user* changes the project's look.

Contract checked against `gitreposit`'s `elwin/mcp-slice-identities-publisher` at `3fd5ffa8`: `docs/mcp/tool-contract.json`, the MCP registry, adapters, store, and style-revision RPCs. This is source verification, not evidence of a live staging deployment or an end-to-end generation test. Discover deployed tools and schemas before use.
