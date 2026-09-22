# Sound placement conventions

Where a `Sound` lives decides how it behaves. Get the parent right before tuning anything.

| Sound | Parent | Why |
| --- | --- | --- |
| UI clicks, notifications, menu music | `SoundService` (or a `SoundGroup` under it) | Non-spatial, same for every player, never attenuates |
| Ambient loop for a whole map (wind, crowd) | `SoundService`, `Looped = true` | Global bed; one instance, not per player |
| Zone ambience (cave drip, waterfall) | A `Part` or `Attachment` at the zone center | Spatial rolloff makes it fade naturally |
| Object sounds (torch crackle, machine hum) | The emitting `Part`/`Attachment` | Moves and dies with the object |
| Player actions (swing, footstep, hit) | The character part or a `Sound` cloned onto it, `PlayOnRemove = true` for one-shots | Correct position, automatic cleanup |

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
- Cap concurrency for spammy sources (footsteps, hits): reuse one `Sound` and `:Play()` again, or clone with `PlayOnRemove` and destroy.

## Generated audio

`generation_sound_effect` and `generation_music` return downloadable files and owned audio artifact references. They are not Roblox audio ids until published. Follow `audio-publication.md`: when the live schema accepts `Audio` and `asset_capabilities` reports the publication route usable for this account and type, send the owned reference to `artifact_publish`. Do not download or reprocess it locally for that route. A plugin update alone does not enable backend publication.

Before spending, confirm the destination and target experience's access. If no usable route exists, disclose the blocker and use the explicitly authorized local/manual fallback in `asset-upload.md`, or agree on Creator Store placeholders. Never switch routes after an ambiguous submission. Keep request, generation, artifact and publication identifiers in ledger v2.

`loopable` guides the generation prompt; it is not a measured seamless-loop guarantee. Listen across the loop boundary before calling a music or ambience loop seamless. Moderation approval and loaded/playing properties do not prove audible output; verify it by ear in Play and record unperformed checks honestly.

## Verify

Play the place, walk toward and away from a spatial source, and confirm attenuation and that nothing is still playing after its object is destroyed. `get_console_output` catches `Sound failed to load` errors from bad or unmoderated ids.
