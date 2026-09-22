# Generated music and sound-effect publication

This workflow supports integrated generation-time publication and standalone Audio `artifact_publish`. Discover each route independently; standalone Audio support alone does not establish integrated delivery support. Check live tool schemas and `asset_capabilities` before planning dependent work. The package version and this document do not prove deployment, provider entitlement, Roblox moderation or playback.

## Generate or reuse

Prefer an existing owned audio artifact when suitable. Otherwise use `generation_sound_effect` for short effects or `generation_music` for a soundtrack with an authorized budget. Save the exact request and stable request ID before submission, then retain the generation job ID and poll `generation_status`. For direct delivery or reuse, select the returned audio artifact reference for the intended batch member; never substitute a download URL or assume index zero represents every result.

Both generators already produce MP3. The generation service holds its provider key; never ask the user for `SoundMusic_KEY`. Music's direct-generation duration range can exceed Roblox's publication limit. Consult the advertised audio limits before spending on a track intended for Roblox. Do not trim, transcode or regenerate rejected audio automatically. `loopable` is a prompt hint, not a verified seamless loop.

## Prefer integrated delivery for new Roblox audio

For newly generated Roblox audio, prefer `delivery: {"mode": "publish", "platform": "roblox"}` on `generation_music` or `generation_sound_effect` when that generator's live schema advertises it and account capabilities report Audio publication usable. Require `generation:write` and `publication:write` before paid submission, plus `generation:read` for job polling and `publication:read` for individual publication polling. Confirm the configured shared-group destination and intended experience access first; this does not select user OAuth.

Omitting delivery or passing `delivery: {"mode": "direct"}` preserves file delivery without publishing. Use direct delivery when files are wanted, and standalone publication below for existing owned artifacts. Executable examples for omitted, direct and publish requests for both generators are in `tests/preparation-requests.json`.

Direct music supports up to 600 seconds; integrated publication requires a requested duration strictly below 420 seconds. Measured audio validation still applies after generation. Do not silently shorten the request or switch delivery modes on rejection.

Integrated publish responses have `result: null`; consume `delivery.outputs[]` rather than looking for raw audio URLs or a single model-style `delivery.asset_id`. Poll the original job with `generation_status` even after generation succeeds. Retain each member's `index`, `artifact_ref` when present, `publication_id`, decimal-string `asset_id`, status and moderation metadata independently in ledger v2. IDs can be null while work is pending. Generation success does not mean delivery is ready.

- `publishing`: keep polling the existing job/publications; no new generation or upload.
- `ready`: every output is ready for the separate access and Studio playback checks below.
- `partially_ready`: inspect every member; only ready members may proceed to those checks. Others may still be pending, failed or require reconciliation.
- `incomplete`: inspect member errors and missing outputs; preserve successful receipts and report the missing/failed portion. Do not regenerate the batch automatically.
- `needs_reconciliation` on the aggregate or a member, or `outcome_unknown`: retain all IDs and errors and reconcile the original work. Never resubmit, change routes, or assume billing settled.

Never call `artifact_publish` for outputs already submitted by integrated delivery. A temporarily missing publication ID is not permission to publish manually: the durable handoff may still be recovering. Use only an explicitly supported publication-only recovery action after reconciling the original state. Standalone/local publication is not a fallback for interrupted integrated delivery.

## Publish existing artifacts through ForgeGUI

Require all of the following: the live `artifact_publish` input enum includes `Audio`, the configured shared-group publication route is usable for this account, its capabilities include Audio, and the intended experience has an authorized access path. A Model/Image-only publisher is not an Audio publisher.

Use `publication:write` for submission and `publication:read` for polling. `generation:write` is needed only for new generation. Pass an owned `run_id` when recording the operation in a run.

```json
{
  "request_id": "desert-ambience-publish-v1",
  "artifact_ref": "mcp-artifact:00000000-0000-4000-8000-000000000003:0",
  "asset_type": "Audio",
  "destination": {
    "platform": "roblox",
    "creator": "configured_shared_group"
  }
}
```

Replace the placeholder with the owned returned reference. The group and credentials are selected by the server. This is not a user-OAuth upload, does not publish to the Creator Store and does not grant arbitrary experiences access. Never silently change destination.

Save the returned `publication_id` immediately and poll `publication_status`. Keep the Roblox asset ID as a decimal string. Pending moderation is not ready for installation. On a failed publication, retain the generated artifact; use only an explicitly supported publication-only retry. For `needs_reconciliation`, `outcome_unknown`, a lost response or unfamiliar state, follow `asset-upload.md` and SKILL.md §4: preserve evidence, reconcile the original operation and never submit a replacement or switch upload routes automatically.

## Install, verify and record

For a ready Audio publication, verify its asset type, creator, moderation and target-experience access. Use the returned ID as `rbxassetid://<asset_id>` in the appropriate Studio audio property; never assign the MP3 URL. Follow `sound-placement.md` for spatial sources and mixing. Server-reported measurements describe the stored audio, not the intended volume, placement or loop behavior.

In the intended experience, check loading errors, duration and actual audible playback. For spatial effects, move toward and away from the emitter; for loops, listen across the seam. A property such as `IsPlaying` alone is not audible verification. Record the instance path, source artifact, generation/publication IDs, creator and checks in ledger v2; append playback checks to the owned run as caller-reported evidence using `preparation-installation.md`. Leave unperformed checks marked `not_performed` and do not upgrade server verification flags.

If shared-group access is unsuitable, stop and explain the destination limitation. OAuth remains unavailable until the live server explicitly supports it. The local Open Cloud helper remains an explicit fallback with user-approved credentials/destination and durable receipts, not a recovery mechanism for an ambiguous ForgeGUI submission.
