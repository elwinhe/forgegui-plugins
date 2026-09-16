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

`generation_sound_effect` and `generation_music` return downloadable files. They are not Roblox audio ids until published through a verified route. Until a publish tool exists (#53, #63): disclose the manual upload step before spending, keep the job id in the manifest, and fall back to `search_asset` on the Creator Store for placeholders. Roblox audio moderation is asynchronous; a freshly uploaded id can be silent for minutes and must be checked in a playtest, not assumed.

## Verify

Play the place, walk toward and away from a spatial source, and confirm attenuation and that nothing is still playing after its object is destroyed. `get_console_output` catches `Sound failed to load` errors from bad or unmoderated ids.
