# Open Cloud asset upload

The route that turns a file on disk into a numeric Roblox asset id. `SKILL.md` §4 documents it from PR #1; this
page adds the runnable script, the accepted formats, and what was and was not tested about ownership.

## The route

`POST https://apis.roblox.com/assets/v1/assets` (multipart: a JSON `request` part and the `fileContent` part),
then poll `GET /assets/v1/operations/{id}` until `done`, and read `response.assetId`, `response.assetType` and
`response.moderationResult.moderationState`. `scripts/open_cloud_upload.sh` does exactly that:

```sh
scripts/open_cloud_upload.sh <file> <Image|Audio|Model|Animation> "<display name>"
# -> assetId=76875404707631 assetType=Audio moderation=Reviewing
```

Credentials come from the environment and are never printed or passed as tool arguments:

```sh
# .env (git-ignored; never commit it)
ROBLOX_API_KEY=...            # Open Cloud key with Assets read+write scope
ROBLOX_CREATOR_USER_ID=...    # the user id the key belongs to (uploads land in that account)

set -a; . ./.env; set +a      # load it for this shell
```

The script refuses to run, with a clear message, if either variable is unset. It has a 20 MB size guard and
no dependencies beyond `curl` and `python3`. A `Model` upload also has the 20k-triangle-per-mesh limit from
PR #1; check with a local triangle count before uploading, not by waiting for a rejection.

**Verify the script without credentials** with `--dry-run`, which prints the request it would send (file, size,
content type, JSON body) and whether the key is set, never its value:

```sh
scripts/open_cloud_upload.sh --dry-run star-chime.mp3 Audio "Star chime"
```

## Asset types and formats

| `assetType` | Extensions (content type) | Used as |
| --- | --- | --- |
| `Image` | `.png`, `.jpg` (`image/png`, `image/jpeg`) | `ImageLabel.Image`, `Decal.Texture`, `SurfaceAppearance` maps, `Sky` faces, `Shirt.ShirtTemplate` |
| `Audio` | `.mp3`, `.ogg`, `.wav`, `.flac` (`audio/*`) | `Sound.SoundId` |
| `Model` | `.glb`, `.fbx` (`model/gltf-binary`, `model/fbx`) | `InsertService:LoadAsset(id)` → MeshPart(s) |
| `Animation` | `.rbxm`, `.rbxmx` (`model/x-rbxm`) holding a `KeyframeSequence` | `Animation.AnimationId` on an R15 `Animator` |

The script checks that the extension matches the requested type (`.glb` as `Image` is refused). Use the id as
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

**A generated clip.** `generation_sound_effect` and `generation_music` return a terminal `succeeded` job whose
result carries `audio_urls` / an `artifact_ref` of kind `audio`: a plain public `.mp3` URL. Measured on
September 19–20, 2026 (`evidence/audio-route/` in the showcase repo): request `audio-route-test-2026-09-19-a`,
job `b948de0a-2dff-4fb9-9c5c-4dffa9c1baed`, a 2 s clip, 33 KB, 128 kbps 44.1 kHz stereo. Download it, upload it
as `Audio` through this script, and the operation returned **assetId 76875404707631**, `Reviewing` at upload.
That id is then a `Sound.SoundId`. In-game playback of that specific id was being confirmed in Studio when this
was written; `evidence/audio-route/RESULT.md` carries the outcome, so read it rather than assuming.

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
