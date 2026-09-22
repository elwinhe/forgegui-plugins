# Fidelity pass A/B

September 16, 2026. Claude Code (Opus 5), ForgeGUI MCP, legacy standalone Roblox Studio MCP, skill at `release/claude-mcp-v1 @ 9f197fb`. One run per arm.

## Setup

- **Reference:** *We Who Are About To Die* gameplay video (https://www.youtube.com/watch?v=eSiOU3ZniWQ), given to every agent as 49 still frames.
- **Base:** one agent built a gladiator arena game from a short brief with up to 8 generations, saved as `base.rbxl`.
- **Arms:** two fresh agents each opened a copy of `base.rbxl` with identical context (frames, skill, tools, 4-generation budget). Only the pass prompt differed:
  - **A (control):** "Use the current working build as the base. Do NOT rebuild it from scratch. Do a polish pass to improve the game using the reference. Preserve all working gameplay systems. Test the full gameplay loop…"
  - **B (treatment):** the fidelity block now shipped as `references/fidelity-pass.md`.
- A never saw B's work, and B never saw A's. `base.rbxl` was read-only and its hash was unchanged throughout.

## Results

| | A · plain polish | B · fidelity block |
| --- | --- | --- |
| Active agent time | ~28 min | ~53 min |
| Generations used | 3 of 4 | 3 of 4 |
| Open Cloud uploads | 4 | 5 |
| Camera | High chase camera | High chase camera (−40°, FOV 62) |
| Characters | Blocky bodies; generated helmet, faces | Roblox Base Body, limb-fitted gear, realistic walk/run |
| Animation | Stock | Per-weapon guard stances, timed windup/strike, blade trail |
| Lighting | Less washed out | Three moods, including a torch-lit dusk pit matching the reference |
| Bugs fixed | Stacked outfits, sunken pedestal character | Weapon grip axis (thrown weapons flew sideways) |

In matched screenshots, B changed more of what the fidelity block lists and looked closer to the reference's pit fights. B also worked about twice as long, which comes from the block's "compare again and fix" step. That is the cost the skill now asks users to accept.

## Limits

- One run per arm; a rerun could differ.
- Ladder rungs 3–6 were not played by hand in either arm.
- No ForgeGUI billing amount was returned, so credit cost is unknown.
- The base build's long orchestrator prompt is not what a one-line user prompt produces; the intake step is meant to close that gap.
