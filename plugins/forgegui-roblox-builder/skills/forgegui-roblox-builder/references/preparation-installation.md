# Prepare, publish, install

Use **generate/reuse → prepare → publish → Studio install → verify → record in run**.
This is caller guidance for the #606 backend contract at `18faae7b`; it is not
evidence that hosted conversion, publication or Studio acceptance passed.

## Preflight and recovery

Discover tools and call `asset_capabilities`. Check route usability for this
account, not just whether a schema contains a variant. Preparation requires
`generation:write`, job polling `generation:read`, publication
`publication:write/read`, and run recording `runs:write/read`. Never broaden a
key without authorization. A configured route may still be disabled or restricted.

Create or retrieve an owned run when available. Pass its `run_id` on preparation,
publication and generation calls that expose that field. Server-observed work is
linked automatically; record actual Studio checks separately with `run_append`.
Use the returned revision, rereading on `revision_conflict`. Never overwrite a
completed run; use a new run for further work. Follow pagination when rebuilding
the ledger through `run_get`/`run_list`, and recover prepared bundles through their linked preparation jobs with
`generation_status`. The local ledger is a cache, not the only source of truth.

Keep separate stable request IDs for generation, preparation and publication.
Replay only identical parameters. After a timeout, reconcile the recorded job or
publication before retrying. Do not regenerate an asset to get an import route.
Do not blindly retry `outcome_unknown` or `needs_reconciliation`.

## Read the prepared bundle

Call `asset_prepare` with the nested `asset.kind` discriminator. Poll its job via
`generation_status`; success returns `result.prepared_bundle`. Retain
`schema_version`, `bundle_id`, `kind`, `profile`, `members`, `metrics`,
`studio_recipe`, `provenance`, `validation` and `warnings`. Resolve a member by
`member_key` and intended type, never by array position. Publish its `asset_ref`,
not a source reference, URL, bundle ID, or an auxiliary preview.

| Returned facts | How to use them |
| --- | --- |
| Member `sha256`, `byte_size`, `media_type`, `asset_ref` | Preserve identity of the exact prepared output through publication and the ledger |
| Model `metrics.source` and `metrics.prepared` | Bounds (`min`/`max`), dimensions, triangles, primitives and vertices before/after the explicit transform |
| Model `metrics.coordinate_convention` | glTF right-handed, +Y up, meters; not proof of Studio's imported size |
| `provenance.settings.transform` and `matrix_column_major` | Already applied to the prepared GLB; do not apply them again in Studio |
| Image `metrics.source_dimensions` / `output_dimensions`, member width/height | Actual prepared canvas dimensions, not visible-content bounds |
| Image `provenance.settings.operations` and `alpha_representation` | Ordered alpha/resize operations already applied; straight RGBA8, not an instruction to repeat processing locally |
| `provenance.sources` and `transform_version` | Original owned refs, pinned hashes/byte sizes and converter identity |
| `studio_recipe.id` / `version` | Accept known recipes: `roblox-static-model-install` v1 or `roblox-image-install` v1; report an unsupported version instead of guessing |

Bundle schema v1 does **not** supply image content bounds, transparent padding,
validated nine-slice settings, semantic front detection, automatic fitting, or
authored installation intent. Treat missing measurements as unknown, not zero.
Model recipes explicitly say `semantic_front: not_inferred`, `fitting:
not_performed`, and `actual_import_verification: not_performed`. Structural
validation is not Studio verification; never rewrite those server flags.

## Models

Reuse an existing owned direct-generation or remesh artifact. `asset_prepare`
with `asset.kind: model` inspects it and optionally applies `uniform_scale`,
`pivot` (`preserve`, `bounds_center`, `bounds_bottom_center`) and
`orientation_degrees`. Omit the transform for inspection without intentional
scale/pivot/orientation changes. Preserve the original reference and retain the
new `Model` member separately.

Choose transforms explicitly from a known convention or measured requirement.
Bounds do not identify a helmet's front or a weapon's grip. After insertion,
measure Studio bounds and pivot again. Compute any additional scene scaling from
the **imported** dimensions and intended size; don't assume meters became studs
at a universal ratio. Record that installation adjustment separately from the
backend's baked transform. Inspect textures, anchor/collision settings and
attachment offsets; verify held gear during movement in Play.

## Images

Use server `asset_prepare` for `color_key_to_alpha`, `luminance_to_alpha` and
`resize` when the route is usable. Pick alpha rules intentionally: keyed colors
may be legitimate artwork, luminance alpha can remove dark detail, and resize
`contain`, `cover`, and `stretch` respectively pad, crop, and distort aspect.
Do not run an equivalent local script on the prepared member again.

Sheet separation and nine-slice analysis are separate operations not supplied by
this image preparation contract. Use existing supported separation or the
documented local tools only for that missing step, and record the manual/local
provenance. If local bytes change, register the new image through the supported
upload flow before publishing; never reuse the old artifact ref for changed bytes.
Preserve a prepared image's native aspect. Nine-slice coordinates must refer to
the actual stored Roblox image dimensions and be authored or visually validated;
canvas dimensions alone cannot establish safe stretch regions. Without a valid
slice definition, use ordinary aspect-preserving art rather than guessing.

## Publish the prepared member

Use `artifact_publish` for one owned `Model` GLB or PNG `Image`, with
`destination: {platform: roblox, creator: configured_shared_group}`. The
destination is server-selected; no OAuth, arbitrary creator, audio publication
or whole-bundle publication is implied. Confirm shared-group ownership fits the
task and verify target-experience access. Do not switch destinations silently.

The standalone tool and `publication_status` return a **top-level**
`publication_id`, `status`, `asset_id`, `asset_type`, `creator: {type, id}`,
`moderation_state`, `safe_error_code`, `safe_error`, and
`publisher_profile_version`. This differs from legacy generation-time
`delivery.status` / `creator_group_id`. Do not conflate the two envelopes.

| Standalone status | Next action |
| --- | --- |
| `publishing`, `pending_moderation` | Retain ID; poll `publication_status` with bounded backoff; an asset ID alone is not ready |
| `ready` | Check expected asset type/creator and decimal-string ID; then verify access and insert |
| `failed` | Report safe error; use publication-only retry only if explicitly permitted; preserve generated/prepared output |
| `needs_reconciliation`, unfamiliar state | Stop automatic writes; retain IDs and report reconciliation needed |

Keep Roblox IDs as decimal strings in records. Adapt only at the Studio tool
boundary if required, without lossy numeric conversion. Insert Models through
the exposed Studio insertion tool; use Image IDs for image properties, never a
Model or Decal container ID. Upload success does not prove cross-creator access.
Inspect the current place before retrying an ambiguous insertion; publisher
deduplication does not deduplicate Studio instances.

## Installation intent and evidence

Keep caller-authored intent separate from returned measurements in ledger v2:
intended usage, desired size with units, target instance/attachment, relative
position in studs and rotation convention, and optional authored nine-slice
settings. These are local planning fields, **not** extra MCP request fields or
server-verified facts. Missing intent means unspecified. Don't infer semantic
front, fit, or a nine-slice region from an asset's name.

Install in Edit, retain the actual instance path, then verify in Edit and Play.
Report checks not executed as `not_performed`. Append caller-reported checks to
the run without upgrading their trust. On a fresh session retrieve the run and
bundles, reconcile pending publications, and inspect Studio before new work.

## Remaining backend/acceptance work

Content bounds/padding, typed authored placement intent and validated nine-slice
metadata need a companion backend contract change. Real PNG/Model publication,
prepared output appearance/scale, replay/recovery and fresh-session reconstruction
remain hosted/Studio acceptance tasks. This plugin update does not mark them done.
