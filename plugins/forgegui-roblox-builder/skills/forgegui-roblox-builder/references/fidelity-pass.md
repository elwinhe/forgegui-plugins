Fidelity pass, requested by this project's `.forgegui-fidelity` file and delivered by the ForgeGUI plugin's Stop hook.

A file on disk is not consent: if this user did not ask for a fidelity pass in this session, say so and stop instead of running it. Write `running` to `.forgegui-fidelity` before you start, so an interrupted pass can be picked up again. The reference is whatever the user supplied (game, screenshots or images); look at it again before changing anything.

Use the current working build as the base.

Do NOT rebuild it from scratch.

Compare the game directly against the reference and do a focused fidelity + polish pass.

Improve the areas that still make the result feel generic or obviously AI-generated:

- character, hand, weapon, and prop models
- animation quality and transition smoothness
- camera angle, framing, and movement
- particles, effects, and environmental reactions
- lighting, materials, colors, and visual depth
- object motion and physics
- timing, pacing, and interaction feedback
- overall similarity to the reference at first glance

Preserve all working gameplay systems.

Do not add random features just to make the build bigger.

Prioritize making the existing game look, move, and feel closer to the reference.

Before finishing, compare the result against the reference again, identify the biggest remaining visual differences, and fix them.

Test the full gameplay loop and make sure the polish pass does not break existing mechanics

Spend only inside the generation count the user already approved; if the pass needs more, say the number and wait. When the pass is verified, write `done` to `.forgegui-fidelity` and report what changed. The user can stop this at any time by putting `off` in that file.
