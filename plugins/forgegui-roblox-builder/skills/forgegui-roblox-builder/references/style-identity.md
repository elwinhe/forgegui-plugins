# Style identities

A style identity is an account-owned, server-side record of a project's look: a name, a detailed brief, and up to four owned reference images. Generations pinned to it stay consistent across sessions and machines without re-pasting the brief. The tool family is `style_list`, `style_get`, `style_create`, `style_revise`, and `generations_by_style`.

**Verified absent on staging as of 2026-09-19.** Tool discovery against `vzzqjekupwutoaasswwd.supabase.co` returned 17 tools and none of this family; `generation_gui` and `generation_model_3d` are both `additionalProperties: false` with no style fields, so a pin sent today is rejected rather than ignored. Everything below describes the intended shape for when it lands — re-check before relying on it.

**These tools may not be exposed yet.** Discover the live tool list first (SKILL.md §1). When the family is absent, use the manifest's `art_direction`, `material_language`, and `style_refs` exactly as before and say nothing about styles being unavailable unless the user asks. Never treat a missing style tool as an error or substitute another endpoint.

## Resolve one identity per project

Do this once, before the first paid visual generation, not per asset:

1. `style_list` and compare against the manifest's `style_id` and the project's art direction. A returned identity whose brief matches the project is reused, not recreated.
2. No match: `style_create` with
   - `name` — short and stable (≤ 120 chars), e.g. `"Crystal Mine — warm low-poly"`.
   - `detailed_brief` (≤ 8000 chars) — the intake style answer plus the manifest's `art_direction`, `palette` words, and `material_language`, written as full sentences. This brief is the reusable style contract; write it as carefully as a generation prompt.
   - `reference_asset_ids` — up to 4 **owned asset UUIDs**. This field does not accept `mcp-artifact:` references; register artifacts or user images first (below).
3. Record the returned `style_id` and `style_version` in the manifest. Both are passed together on every generation call; the server rejects one without the other.

Style management calls do not charge credits.

## User-supplied style images

A pasted or local image is not a reference until it is an owned asset. When the upload family is exposed: `image_upload_authorize` (PNG, JPEG, or WebP, ≤ 12 MB — returns a bounded signed upload), upload the bytes, then `image_upload_register` with the `upload_id` to verify and register the immutable owned image. The returned asset UUID is valid in `style_create`/`style_revise` `reference_asset_ids` and in per-call reference fields. Neither call charges credits. If the upload family is absent, say so and build the brief from words plus existing owned references.

## Pinning generations

On `generation_model_3d` (and any other generation whose live schema shows the fields):

- Pass `style_id` and `style_version` from the manifest on every call. Together or neither — never one.
- `style_brief` (≤ 4000 chars) and `style_reference_asset_ids` (≤ 4) are per-call *additions* layered on the pinned identity — for one asset that needs an extra nuance ("this one is ceremonial, gilded"). They are rejected without `style_id`/`style_version`. They do not modify the saved identity.
- Combined `reference_asset_ids` + `style_reference_asset_ids` cannot exceed 6. Content references still describe *this object*; style fields describe the world. Do not duplicate an ID across both.
- `game_style` remains the routing type and is unchanged by any of this.

`generations_by_style` lists the account's generations pinned to an identity — use it to find reusable prior output before generating (SKILL.md §3 reuse rule applies).

## Revising a look

Revisions are immutable and appended: `style_revise` with `style_id`, `expected_version` (the version you believe is latest — a mismatch means someone else revised; re-read with `style_get` before retrying), the full new `detailed_brief`, and the full `reference_asset_ids` array (it replaces, not merges). Then update the manifest's `style_version` pin. Existing generations never change retroactively; regenerate anything that must match the new revision, subject to the normal spend rules.

Do not revise the identity to serve one asset — that is what per-call `style_brief` is for. Revise when the *user* changes the project's look.
