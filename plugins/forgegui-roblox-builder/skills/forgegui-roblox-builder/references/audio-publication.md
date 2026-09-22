# Generated music and sound-effect publication

This workflow requires the deployed Audio extension to `artifact_publish`. Check live tool schemas and `asset_capabilities` before planning dependent work. The package version and this document do not prove deployment, provider entitlement, Roblox moderation or playback.

## Generate or reuse

Prefer an existing owned audio artifact when suitable. Otherwise use `generation_sound_effect` for short effects or `generation_music` for a soundtrack with an authorized budget. Save the exact request and stable request ID before submission, then retain the generation job ID and poll `generation_status`. Select the returned audio artifact reference for the intended batch member; never substitute a download URL or assume index zero represents every result.

Both generators already produce MP3. The generation service holds its provider key; never ask the user for `SoundMusic_KEY`. Music's direct-generation duration range can exceed Roblox's publication limit. Consult the advertised audio limits before spending on a track intended for Roblox. Do not trim, transcode or regenerate rejected audio automatically. `loopable` is a prompt hint, not a verified seamless loop.

## Publish through ForgeGUI

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
