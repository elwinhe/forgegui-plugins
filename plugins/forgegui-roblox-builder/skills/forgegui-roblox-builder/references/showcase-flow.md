# From a vague prompt to a finished game

Defaults and decision points for building a whole game ("make me a rocket league game", "make a floating
island collectathon") with this skill. Guidance, not a script: every number here is what one build used, not
a requirement, and each step says when to skip or shrink it. The loop in `SKILL.md` (intake → reference →
import preflight → generate → publish → assemble → verify) still governs each asset; this page is the order the
whole build happens in around that loop.

## 1. Turn the ask into a target you can measure

A vague prompt names a genre, not a game. Before planning assets, get something concrete to aim at: a video,
screenshots, an existing experience. Then measure it into a **look-spec**, a short file in the project with:

- **Scale.** Pick one anchor object, decide its size in studs, and derive everything else from the reference's
  real dimensions. One build set the car at 12 studs long, giving one stud = 9.83 reference units, and every
  wall, goal mouth and pad position came from that factor rather than from eyeballing.
- **Palette.** Six to twelve hexes sampled from frames, named by role (`team-blue`, `hud-dark`, `sky-day`),
  which also become the manifest's `palette` and the style card in every prompt (`SKILL.md` §3).
- **HUD.** Positions and sizes as screen fractions, so they survive any viewport.
- **Camera and motion.** Follow distance, FOV, top speed, jump height, respawn timing, whatever the genre lives
  on, as numbers with a note saying which are measured and which are estimates to tune.
- **The asset list** (`SKILL.md` §2) written before any spend, with the source of each item.

Why: both showcase builds only converged on their reference because the target was numeric. "Looks like a
stadium" gave three rounds of drift; "833 × 1041 studs, 26-stud fillets, `#1C60FD`" gave a build that
could be checked against the frames and either passed or did not. When the user has no reference and does not
want one, write the look-spec from your own choices anyway, so later passes still have something fixed to
compare against.

Decision point: an agent cannot watch a video. Ask for a handful of screenshots (a wide gameplay shot, the HUD,
menus, the win screen) rather than trying to describe a link.

## 2. Grey-box first, at the measured scale

Build the whole layout from primitives at look-spec scale, wire the gameplay, and play it before generating a
single asset: the map, spawns, triggers, pickups, the win condition, the camera. In one build this was a
`build_place` script that rebuilt the arena idempotently from a layout module, so changing a number in the
spec and re-running it was the whole iteration.

Reasons to do it in this order:

- Dressing a broken layout wastes generations. A goal mouth the ball cannot enter, a pickup radius that misses,
  a camera that clips the wall: all of these are found in ten minutes on grey boxes and cost nothing to fix.
- The grey-box tells you the real asset list. Repeats, silhouettes seen only from far away, things the camera
  never frames: those decide what gets generated at `standard` versus `high` versus not at all.
- It gives the regression guards their baseline (step 5) before any visual work can hide a break.

Decision point: for a small addition to an existing game, the grey-box is the existing game; skip this step.

## 3. Asset strategy

- **One asset per distinct object, duplicated for repeats.** A stand section placed twenty times beats fifty
  unique seats. One build's ledger had a wall rib placed 56 times, a small boost pad 28 times, a wheel 8 times,
  from one generation each. Scripts do the placement, so the count is a loop variable, not a spend.
- **Carry a style card in every prompt** (`SKILL.md` §3): the palette hexes, shading, line weight, material
  feel, proportions, appended after the content words and unchanged between assets. That is what makes twenty
  generations read as one game.
- **Single-object reference images only for 3D.** A scene concept passed to `generation_model_3d` returns the
  scene as one mesh (13 of 13 calls in one run). Concept images belong to `generation_image` and
  `generation_gui`; a 3D call gets an image of that one object on a plain background, or text alone.
- **Script-built beats generated for structure.** Floors, walls, fillets, trigger volumes, lines, and anything
  whose shape is a number in the look-spec comes from primitives in the build script and is textured, not
  generated. Generate the identity: the vehicle, the hero prop, the pickup, the landmark, the HUD art, the sky
  panorama, the tileable textures. Where a build's genre inverts this (a diorama, a mostly-organic island
  world), let the look-spec decide.
- **Order the spend by what unblocks other work:** concepts and the style card, the sky and ground textures,
  then the hero objects, then set dressing. Generation limits exist (`SKILL.md` §5); the first assets should be
  the ones that let the rest of the build continue while later ones are pending.
- **Sound** comes from the Roblox free library, from `generation_sound_effect` / `generation_music` uploaded
  through `references/asset-upload.md`, or both; either way the ids belong in the ledger with their source.

## 4. Assemble, then verify by playing

Import into the grey-box by replacing stand-ins in place (`SKILL.md` §6): same positions, same names, so the
build script and the ledger stay the source of truth. Then play it, on the client, before judging the look:
streaming, GUI loading, collisions from decorative parts, and effects that never emit are only visible there.
A capture of a background Studio window is stale; bring it forward first.

## 5. Iterate with fidelity passes, behind regression guards

Compare the build against the reference at the same camera angles, list the biggest differences, fix them, and
repeat. `references/fidelity-pass.md` (where present) is the procedure; do not restate it here. Two things make
it converge instead of wander:

- **A fixed capture set.** The same handful of camera CFrames every round (a wide kickoff, the goal front, the
  HUD, a close-up of the hero object), captured before and after, side by side. Differences become visible;
  "better" becomes checkable.
- **Regression guards from step 2, re-run every round.** A visual gain must not hide a broken game. In one build
  the guards were a 120 s bot playtest (ball hits, longest positional stall, minimum fps), static probes (pads
  seated, corner fillet sweep with zero misses, both goal mouths passable, ball containment at max speed, hit
  speeds inside ±15 % of target), and an instance inventory whose every delta had to be explained. A round that
  improved the stands and closed a goal mouth was caught by the probe, not by the screenshot.

Pick the guards from what the grey-box proved worked; write the threshold beside each; and keep failed probe
runs in the evidence rather than deleting outliers.

Decision point: the pass costs about twice a plain polish pass and can spend more generations; intake asks
about it because the user, not the agent, sets that ceiling.

## Worked example: arena sports game

Target: a 2v2 car-football match, measured from an eleven-minute reference video into a look-spec: car 12
studs, field 833 × 1041 studs, 208-stud ceiling, 26-stud fillets, six big and 28 small boost pads at canon
positions, palette of about twenty hexes, HUD as screen fractions. Generated (one each, remeshed from ~100k to
8–15k triangles where `high` quality was used): car body, ball, wheel, wall rib, goal frame, floodlight, big
and small pads, seat row, five HUD images, five tileable textures, one sky panorama cut into six faces.
Script-built: floor, walls, fillets, corner cuts, goal volumes, lines, pad triggers, stands rakers. Duplicated:
rib ×56, small pad ×28, wheel ×8, floodlight ×8, seat row per stand. Sound: eight free-library ids. Guards:
the bot playtest, the static probes and the inventory reconciliation above; four fidelity rounds passed them
all, and the one that hid a regression chain was the one that ran without the positional-stall metric.

## Worked example: exploration collectathon

Target: floating islands with rope bridges, collect every star within a round timer. No video; the target was
two style images and a written spec (island spacing, bridge span, star count, round length, kill plane height).
Generated: island, tower, bridge, tree, star, airship, one ground texture, one sky panorama, four GUI pieces,
a shirt, pants, a face and a hat, each once per style; the same prompts under two style cards gave two
complete kits, measured 2.5–3.5× closer in palette to their own reference. Script-built: the island layout
(spawn plus seven placements of the same island mesh), bridges spanned between them, star spawns, the round
loop, the kill plane. Duplicated: island ×8, bridge ×8, star ×14. Guards: a `PASS`-printing build script
(islands 8/8, bridges 8/8, textured bodies 8, failed ids empty), a walk across every deck in Play, a mesh
quality table per model, and a playtest that confirmed pickups and the round restart before any polish.
