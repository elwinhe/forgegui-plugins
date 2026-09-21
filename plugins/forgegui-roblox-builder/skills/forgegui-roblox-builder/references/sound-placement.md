# Sound placement conventions

Where a `Sound` lives decides how it behaves. Get the parent right before tuning anything.

| Sound | Parent | Why |
| --- | --- | --- |
| UI clicks, notifications, menu music | `SoundService` (or a `SoundGroup` under it) | Non-spatial, same for every player, never attenuates |
| Ambient loop for a whole map (wind, crowd) | `SoundService`, `Looped = true` | Global bed; one instance, not per player |
| Zone ambience (cave drip, waterfall) | A `Part` or `Attachment` at the zone center | Spatial rolloff makes it fade naturally |
| Object sounds (torch crackle, machine hum) | The emitting `Part`/`Attachment` | Moves and dies with the object |
| Player actions (swing, footstep, hit) | The character part or an attachment at the actual contact point | Spatial origin; reuse a voice or explicitly clean up after playback |

## Defaults that sound right

```lua
local sound = Instance.new("Sound")
sound.SoundId = "rbxassetid://<id>"        -- a Roblox audio id, never an external URL
sound.Volume = 0.5                          -- world one-shots 0.3–0.7, UI 0.2–0.4, beds 0.15–0.3
sound.RollOffMode = Enum.RollOffMode.InverseTapered
sound.RollOffMinDistance = 8               -- full volume within 8 studs
sound.RollOffMaxDistance = 80              -- silent past 80; 150–300 for large ambience
sound.PlaybackSpeed = 1 + (math.random() - 0.5) * 0.1  -- ±5% keeps repeats from sounding stamped
sound.Parent = emittingPart
```

## Mixing

- Create three `SoundGroup`s under `SoundService`: `Music`, `SFX`, `UI`. Assign every `Sound.SoundGroup`. Volume-budget at the group: `Music 0.35`, `SFX 0.8`, `UI 0.6`, then never fight the mix per sound.
- Layer ambience as one bed (looped, low) plus two or three sparse random one-shots (drip, bird, distant clank) on a 4–12 s random timer. One loud loop reads as noise.
- Fade, don't cut: use `TweenService` on `Volume` over 0.6–1.5 s when entering or leaving zones.
- Cap concurrency for spammy sources (footsteps, hits): reuse one sound per source/cue. Avoid `PlayOnRemove` when owner destruction must stop playback; it intentionally starts playback on removal.
- Repeated props do not each need the same loop. Use a few spaced sources, with rolloff distances fitted to their spacing, then listen at the overlap. Preserve existing mix groups instead of resetting unrelated audio.

## Free-library placement, without a generation job

Use Studio MCP's `search_asset` with `assetType = "Audio"`, `scope = "creator_store"`, `priceFilter = "free"` where supported. Record the returned ID, title, creator and free-library source. Prefer Roblox-provided libraries when their content fits. A free search result still needs a loading/access check in the target experience.

For free-library audio, use its returned Roblox IDs directly; no generation or upload is needed. For custom audio, follow the generated-audio route below.

Install [SoundPlacement.luau](luau/SoundPlacement.luau) as a ModuleScript named `SoundPlacement` in ReplicatedStorage. It creates or reuses one tagged Sound per parent/key, rejects unrelated name collisions, and keeps placement separate from playback. `ensure` applies the full configuration on every call: omitted options return to defaults, including clearing the mix group.

```lua
local S = require(game.ReplicatedStorage.SoundPlacement)
-- Resolve these bindings from the inspected place and the saved library search.
local loop = S.ensure(inspectedMachineAttachment, "machine_loop", verifiedLibraryAudioId, {
    looped = true, volume = 0.2, minDistance = 6, maxDistance = 36,
    group = existingSFXGroup,
})
S.play(loop) -- Call in Play. A repeated call does not restart a playing loop.
-- Reuse the same key for later updates; S.remove(loop) stops and removes only its owned sound.
```

For one-shots, `play` stops and retriggers the same voice rather than cloning it; this trades overlap for bounded concurrency. `remove` stops and destroys only a helper-owned sound, with `PlayOnRemove` disabled. Invalid numeric options are rejected before changing the sound.

Create source attachments on existing objects. Global ambience belongs directly under SoundService. For action cues, use the existing event convention at the actual world position. Persist scripts/placement in Edit so the next Play session reproduces the layer.

## Generated audio

`generation_sound_effect` and `generation_music` return downloadable files and owned audio artifact references. They are not Roblox audio ids until published. Follow `audio-publication.md`: when the live schema accepts `Audio` and `asset_capabilities` reports the publication route usable for this account and type, send the owned reference to `artifact_publish`. Do not download or reprocess it locally for that route. A plugin update alone does not enable backend publication.

Before spending, confirm the destination and target experience's access. If no usable route exists, disclose the blocker and use the explicitly authorized local/manual fallback in `asset-upload.md`, or agree on Creator Store placeholders. Never switch routes after an ambiguous submission. Keep request, generation, artifact and publication identifiers in ledger v2.

`loopable` guides the generation prompt; it is not a measured seamless-loop guarantee. Listen across the loop boundary before calling a music or ambience loop seamless. Moderation approval and loaded/playing properties do not prove audible output; verify it by ear in Play and record unperformed checks honestly.

## Verify

Preload candidate sounds on the client and inspect `IsLoaded`, `TimeLength`, `IsPlaying`, time-position progress and console errors. These establish loading/playback state, **not audible output**.

In the target place's Play session, listen to each selected sound separately and to the mix; walk toward and beyond the spatial rolloff boundary. Save a short recording with audio when possible. If audio capture/listening is unavailable, mark audibility unverified rather than using a screenshot or `IsPlaying` as proof. Record each sound's tree path, ID, parent, volume/group and rolloff values alongside the clip. Check setup twice for duplicate loops and destroy a disposable test owner to confirm its sound stops. Stop Play, save Edit, and verify the setup persists.
