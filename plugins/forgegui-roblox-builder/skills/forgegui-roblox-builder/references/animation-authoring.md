# Animation authoring for the standard R15 rig

An agent-authored `KeyframeSequence` uploaded as an `Animation` (see `asset-upload.md`) plays on any standard R15 avatar with no rigging step. These are the rules that make one read as motion rather than a pose slideshow. Measured September 20, 2026 on a looping dance emote in the showcase place; the numbers are a starting point, not a law.

## What is addressable

R15 is a chain of 15 parts joined by 15 joints. A `Pose` is named after the child part and nests under its parent's `Pose`, so the keyframe tree mirrors this chain:

```
HumanoidRootPart
└─ LowerTorso (Root joint)
   ├─ UpperTorso (Waist)
   │  ├─ Head (Neck)
   │  ├─ LeftUpperArm (LeftShoulder) → LeftLowerArm (LeftElbow) → LeftHand (LeftWrist)
   │  └─ RightUpperArm → RightLowerArm → RightHand
   ├─ LeftUpperLeg (LeftHip) → LeftLowerLeg (LeftKnee) → LeftFoot (LeftAnkle)
   └─ RightUpperLeg → RightLowerLeg → RightFoot
```

Each `Pose.CFrame` is a local offset applied between the joint's two attachment frames, in the parent part's axes: X points to the character's right, Y up, Z backward (the character faces -Z). `CFrame.Angles(x, y, z)` applies Z first, then Y, then X, so "swing the arm sideways (Z) then tilt it forward (X)" is one call.

- The `HumanoidRootPart` pose has no joint above it: a translation there is ignored at playback (measured 0.05 studs of hip travel from an authored 0.35). Root motion, hip shift and vertical bob go on the `LowerTorso` pose.
- Set every joint in every keyframe. A joint with no pose in one keyframe snaps to identity when the sequence reaches it.
- Rigs built by `Players:CreateHumanoidModelFromDescription` carry `AnimationConstraint`s (`Attachment0/1`) rather than `Motor6D`s (`C0/C1`); the pose maths is the same, only the property names differ.

## Drive the whole rig

A motion that only moves the arms reads as a puppet on a stick, however good the arm arcs are. Every joint should carry something, even if it is small: 2–4° of counter-rotation on the chest, a head turn, a knee.

## Weight

A shift in the hips needs a knee and a foot to answer it. When the pelvis moves toward one foot, bend that knee (15–20°) and straighten the other (3–5°), pitch the unweighted foot so its heel lifts (8–12°), and roll both upper legs so the feet stay planted rather than sliding with the pelvis (about 18° per 0.35 studs of hip travel plus 8° of hip roll). Without this the character hovers above the ground.

## Overlap and follow-through

Nothing arrives on the same frame. Hips lead; each level down the chain lags the one above. Rather than adding keys, sample every channel from the same pose table at `t - lag` (cyclic for a loop) so the lag is baked into the keyframes you already have. Lags that read well at 0.25 s per beat:

| Level | Lag |
| --- | --- |
| LowerTorso (hips), upper-leg roll | 0 |
| Upper-leg pitch | 0.02 s |
| Knees, UpperTorso | 0.03 s |
| Head, upper arms, feet | 0.05 s |
| Lower arms | 0.08 s |
| Hands | 0.11 s |

Hands should still be moving slightly when the arm has stopped; a wrist rotation of half the forward arm tilt, in the opposite sense, does it.

## Easing and holds

The extremes want a slow approach and a quick pass through the middle. Alternate extreme keys with passing keys (eight keys for a four-pose cycle) and set easing per `Pose`: `Cubic`/`InOut` on the extremes so the hold reads, `Linear` on the passing keys so the swing goes through fast. Leave the passing pose at the midpoint of its neighbours except for the vertical bob (up on the pass, down on the extremes) and knees (softer on the pass).

## Loop closure

For `Loop = true`, the last keyframe must be identical to the first, or the cycle hitches once per loop. Generate it from the same pose sampled at `t = 0`; do not hand-copy values. Check it before serializing: walk both keyframes' poses and compare every `CFrame`.

## Priority and length

Set `Priority` on the sequence (`Action` for emotes, `Idle` for idles) and set it again on the `AnimationTrack` after loading; the track value wins. Keep the authored cycle length exact (`keys * step`) so `track.Length` can be checked against it.

## The measurement that proves it played

A moderation state of `Approved` proves an upload, not motion. In Play, on the actual character:

1. `track.IsPlaying == true` after `Play()`.
2. `track.Length` within a few ms of the authored cycle.
3. A joint delta on more than one limb: sample part positions in root space over one cycle and report the min–max range of at least one hand, one knee angle and the torso. A hand range of zero with `IsPlaying == true` means the priority lost to another track.

`run_script_in_play_mode` on the server can do all three (client-owned characters replicate their animation transforms); the client-side numbers are the same to two decimals.

## Prose is not a reference

A motion authored from a written description of a named dance came out, by the user's judgement, as a plausible dance of that general kind, not the specific one named: the arm and hip mechanics were right and the character was clearly dancing, but nobody would have named it unprompted. The numbers above cannot fix that; they make motion read as flesh, not as a particular choreography. If a recognisable real-world dance is the goal, work from reference frames of it the same way a visual fidelity pass works from reference images: pull the extremes from the frames, match them side by side with the posed rig, and only then tune timing. Iterating on prose descriptions spends uploads without converging.

## Worked example

A four-pose looping cycle at 0.25 s per pose, 1.0 s total, sampled into 8 keys plus the closing key. Angles in degrees, translation in studs; `hipDir` is -1 or +1, `armDir = -hipDir`, `front` is +tilt for the arm that passes in front and -tilt for the one behind.

| Channel | Extreme | Passing |
| --- | --- | --- |
| LowerTorso translate X / Y | 0.35·hipDir / -0.14 | 0 / +0.04 |
| LowerTorso roll / yaw | 8·hipDir / -3·armDir | 0 |
| UpperTorso roll / yaw / pitch | -4·hipDir / 4·armDir / 2 | 0 / 0 / -1 |
| Head yaw / roll / pitch | -10·armDir / 4·hipDir / 3 | 0 / 0 / -2 |
| Upper arms Z (side) / X (front-back) | 30·armDir / ±22 | 0 |
| Elbows | 8 | 4 |
| Wrists | -front·0.5, Z -6·armDir | 0 |
| Knee under the hips / other knee | 18 / 4 | 8 / 8 |
| Upper-leg roll (feet planted) | -18·hipDir | 0 |
| Unweighted foot pitch | 10 | 0 |

Measured in Play: `Length 1.000`, hands sweeping 1.0 studs sideways and 0.7 studs front-to-back, knees -15°…+23°, wrists ±9.6°, head yaw ±6°. The same cycle with only six joints driven measured the same hand sweep and read as arm-waving.
