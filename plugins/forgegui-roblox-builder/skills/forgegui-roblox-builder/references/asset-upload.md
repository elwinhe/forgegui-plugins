# Open Cloud asset upload

The route that turns a file on disk into a numeric Roblox asset id. `SKILL.md` §4 documents it from PR #1; this
page adds the runnable script, the accepted formats, and what was and was not tested about ownership.

## The route

`POST https://apis.roblox.com/assets/v1/assets` (multipart: a JSON `request` part and the `fileContent` part),
then poll `GET /assets/v1/operations/{id}` until `done`, and read `response.assetId`, `response.assetType` and
`response.moderationResult.moderationState`. `scripts/open_cloud_upload.sh` does exactly that:

```sh
scripts/open_cloud_upload.sh <file> <Image|Audio|Model|Animation> "<display name>"
# -> assetId=76875404707631 assetType=Audio moderation=Reviewing   (later re-checked: Approved)
```

Credentials come from the environment. The key is never printed, and never appears in a command line: the
script pipes it to `curl` as a header on stdin (`-H @-`), so it does not show up in the process table for
anyone running `ps` while an upload is in flight.

```sh
# .env (git-ignored; never commit it)
ROBLOX_API_KEY=...            # Open Cloud key with Assets read+write scope
ROBLOX_CREATOR_USER_ID=...    # the user id the key belongs to (uploads land in that account)

set -a; . ./.env; set +a      # load it for this shell
```

The script refuses to run, with a clear message, if either variable is unset. It has a 20 MB size guard and
no dependencies beyond `curl` and `python3`. A `Model` upload also has the 20k-triangle-per-mesh limit from
PR #1; check with a local triangle count before uploading, not by waiting for a rejection.

This script was run against the live endpoint on 20 September 2026 with a 256x256 PNG as `Image`: it returned an asset id with moderation `Reviewing`, the ordinary state for a fresh upload. That run covers the `png → Image` mapping, the operation poll and the output line. The other three mappings were exercised against the same endpoint by an earlier helper of the same shape rather than by this script, and `.rbxm` as `Model` has not been exercised at all — the script warns when asked for it.

**Verify the script without credentials** with `--dry-run`, which prints the request it would send (file, size,
content type, JSON body) and whether the key is set, never its value:

```sh
scripts/open_cloud_upload.sh --dry-run star-chime.mp3 Audio "Star chime"
```

## Asset types and formats

Four mappings have been run end to end against this endpoint — one (`png -> Image`) through this script, the
other three through an earlier helper of the same shape. The script accepts only those four:

| `assetType` | Verified extension (content type) | Used as |
| --- | --- | --- |
| `Image` | `.png` (`image/png`) | `ImageLabel.Image`, `Decal.Texture`, `SurfaceAppearance` maps, `Sky` faces, `Shirt.ShirtTemplate` |
| `Audio` | `.mp3` (`audio/mpeg`) | `Sound.SoundId` |
| `Model` | `.glb` (`model/gltf-binary`) | `InsertService:LoadAsset(id)` → MeshPart(s) |
| `Animation` | `.rbxm` (`model/x-rbxm`) holding a `KeyframeSequence` | `Animation.AnimationId` on an R15 `Animator` |

**Everything else is untested here and the script refuses it**, so a run cannot spend an upload on a
server-side rejection: `.jpg`, `.ogg`, `.fbx`, `.rbxmx`. Roblox's own docs list `.mp3` and `.ogg` for audio, so
`.ogg` is likely fine — but likely is not measured, and `.wav`/`.flac` were asserted in an earlier draft of this
page on no evidence at all. If you need one of them, upload a single throwaway file by hand first, record the
result, then add the extension to the script's table and to this one.

`.rbxm` is not exclusively an Animation container. The requested `assetType` decides, and the script only
refuses combinations it knows are wrong: `.rbxm` may be uploaded as `Model` as well as `Animation` (it warns
that the `Model` case is unexercised), while `.glb` as `Image` is refused outright. Use the id as
`rbxassetid://<id>` where a content string is expected.

## Moderation

An id can be returned while `moderationState` is still `Reviewing`; in the showcase, images stayed `Reviewing`
for hours while models were `Approved` at once. A `Reviewing` asset rendered in Play for the uploading account.
That does not show it loads for anyone else: re-read moderation (`GET /assets/v1/assets/{id}`, or the exposed
equivalent) before calling an asset ready, and record the state in the ledger beside the id.

## Ownership: what is tested and what is not

- Phase 1 (PR #1) found audio uploaded with a personal key was **private to the uploader**: it played in a place
  owned by that account and was not verified for any other owner or group.
- Whether `Image` and `Model` assets behave the same is **untested**. Every showcase place was owned by the
  uploading account, so nothing here shows a generated texture or mesh loading in someone else's experience.
  Treat every personal-key upload as account-scoped until a cross-account test says otherwise.
- The key uploads into a user account. Group-owned experiences, hosted OAuth and production permissions were not
  exercised.

## Audio: two sources, one route

**A generated clip.** `generation_sound_effect` returns a terminal `succeeded` job whose
result carries `audio_urls` / an `artifact_ref` of kind `audio`: a plain public `.mp3` URL. (`generation_music`
returns the same shape, but no run of it was kept, so treat that as untested.) Measured on
September 19–20, 2026 (`evidence/audio-route/` in the showcase repo): request `audio-route-test-2026-09-19-a`,
job `b948de0a-2dff-4fb9-9c5c-4dffa9c1baed`, a 2 s clip, 33 KB, 128 kbps 44.1 kHz stereo. Download it, upload it
as `Audio` — that run went through `tools/roblox-upload.sh`, a helper of the same shape, not through this
script — and the operation returned **assetId 76875404707631**, `Reviewing` at upload.
That id is then a `Sound.SoundId`, and it was carried the rest of the way: a moderation re-check about ten
minutes later returned `Approved`/`Active`, and in a Studio play session the `Sound` reported `IsLoaded = true`,
a 2.0 s length and `IsPlaying` after `Play()` (`evidence/audio-route/RESULT.md`). Audible output was not
measured — no audio capture — and playback for any account other than the uploader's is untested, as for every
asset here.

**A library or licensed file.** The same command with the file you already have; the Roblox free audio library
needs no upload at all, its ids go straight into `Sound.SoundId`.

This means the "no import route for generated audio" line in the open PR #14 (§2) is no longer accurate as of
September 20, 2026: the generation tools return a downloadable file and Open Cloud accepts it. What is still
true is narrower and worth keeping: the connected MCP exposes no generation-side publishing step, so the bytes go
through this script or its successor; moderation may still read `Reviewing`; and whether one account's audio
plays for another is untested (above). Record the id, the source (generated job id or library id) and the route
in the ledger either way.

## Forward compatibility: this script is the stopgap

The MCP is moving to server-side publishing with OAuth and an asset library. When that lands, the upload step
becomes a tool call and nothing around it changes: the ledger still records asset ids, moderation is still read
before an id is called ready, verification still happens in Studio, and only "how the bytes get there" moves
from a personal key on the agent's machine to the server.

Rule for the next agent:

1. Discover the live tools first. If a publishing tool is exposed (any tool that takes a file or artifact ref and
   returns a Roblox asset id), prefer it; check its schema for the asset type and the returned moderation state.
2. Otherwise fall back to `scripts/open_cloud_upload.sh` with the user's own key, and say so in the report as a
   substitute route.
3. Record which route produced each id in the ledger (`"route": "open_cloud_script"` or the tool name), so a
   later session can tell personal-account assets from library assets when ownership questions come up.
