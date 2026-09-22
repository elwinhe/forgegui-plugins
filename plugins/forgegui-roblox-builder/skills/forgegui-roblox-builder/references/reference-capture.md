# Reference capture

A request that carries a likeness claim ("like X", "same style as", "like the real thing") is a claim you will be measured against. A reference is a prerequisite: do not start building, and do not report a likeness percentage, until you hold one. A fidelity pass without an external target measures the model against its own memory: it converges on a remembered game rather than the real one, and reports a likeness figure nothing outside the model can check.

Nothing ships with this skill and the builder does not go looking for footage. The reference always comes from the
user. Before `scripts/reference_frames.py` fetches a link, confirm the user is entitled to that footage and is
handing it over for this build — the script downloads what it is pointed at and asks no questions.

## Getting a reference

1. **Use what the user attached or linked.** A clip, a link, screenshots, stills. Run `scripts/reference_frames.py` on a video; use images as they are.
2. **If nothing was supplied, ask for one.** A short clip, a handful of screenshots, or a link is enough. Say why in one sentence: without it, likeness cannot be measured, only guessed.
3. **If the user declines or is not available to ask,** build to the style words in the request. Record it in `forgegui-project.json` as `"reference": { "supplied": false }`, and do not report a likeness percentage anywhere in the report.

## From frames to numbers

This is the part that makes a build converge. Descriptions drift; numbers do not.

- **Extract:** `scripts/reference_frames.py <the user's clip or link> refs/ --frames 30` writes `frame_NNN.png` and contact sheets. Look at the sheets, then pick the four or five clearest frames: a wide shot of the play area, a ground-level shot, one showing the HUD, one mid-action.
- **Scale ruler:** find an object of known size in frame (a car, a character, a door, a goal). Decide its length in studs once, and derive everything else from it: play-area length and width, wall height, key structure sizes, camera distance and height above the subject, field of view where it can be inferred from foreshortening.
- **Palette:** `scripts/palette.py refs/ --k 6` prints hex values with proportions. Sample the play surface and each team or faction colour separately if they matter; record the hex values, not colour names.
- **HUD:** read each element's position and size as fractions of the screen (score at 0.5, 0.04; minimap bottom-right 0.15 wide). Note font weight, whether text has an outline, and what is animated.
- **Motion:** count what you can observe: seconds to cross the play area at top speed, jump height in object lengths, how long a boost or dash lasts, whether the camera lags the subject.
- Write all of it into the look-spec (`art_direction`, `palette`, and scene measurements in the manifest) **before** generating anything. A generation call made before the numbers exist is spend against a moving target.

## Keep the frames

Keep `refs/` for the whole project. The fidelity pass (`references/fidelity-pass.md`) compares Studio captures against these same stills, and the comparison is only falsifiable when the captures match: same camera angle, same distance from the subject, same moment (kickoff, mid-jump, HUD visible). Take each matched pair before judging likeness, and run `scripts/palette.py <capture-dir> --vs refs/` for the palette half of the comparison.

## Worked example (hypothetical, arena sports game)

The user asks for a car-football arena like the match clip they attached, and confirms the clip is theirs to
share. The numbers below are illustrative arithmetic — the point is the chain from a known-size object to every
other dimension, not these particular values.

1. `reference_frames.py <clip> refs/ --frames 30` → 30 frames, 3 sheets. The wide shot and the goal-mouth shot are the useful ones.
2. Ruler: set the car at 12 studs long (an avatar is about 5, so a car that shares the frame with one cannot be
   4). Counting car lengths off the wide shot: pitch ~87 long → ~1040 studs and ~69 wide → ~830 studs; goal mouth
   ~2.5 cars → ~30 studs; walls ~1.6 cars → ~19 studs. Camera sits ~2.3 cars behind and ~0.85 above.
3. `palette.py refs/ --k 6` → pitch green ~52%, two team colours, boost-orange accent, dark wall, white lines. Hex values go into the manifest.
4. HUD: score centred at 0.50 × 0.05 of the screen, timer under it, boost gauge bottom-right at 0.85 × 0.90.
5. Motion: top speed crosses the pitch end to end in ~8 s; jump ~1.5 car lengths; boost burst ~1 s.
6. Build to those numbers, then capture the same wide and goal-mouth angles and compare.
