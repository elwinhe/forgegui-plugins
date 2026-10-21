# Intake: asking what the user actually wants

Two moments, and only two: **once at the start of a project**, and **at the start of a later prompt
when that prompt opens a decision nobody has made yet**. Everything else is building.

This exists because guessing is expensive. On the project these notes come from, the first build was
rejected as "AI-looking", the second because "it does not match at all what I wanted", and a third
round was spent adding things the user had always assumed were coming: a startup animation, their
character on the title screen, a level system, an admin panel. Each of those was one question. None
was asked, because the request read as complete ("build the entire base game, AAA look") and the
intake covered budget and scope but not taste or expectations.

## The rule for whether to ask

Ask when **all three** are true:

1. The answer changes what gets built, how it looks, or what gets spent.
2. It is not settled by the prompt, by an earlier answer, or by `decisions` in
   `forgegui-project.json`.
3. You cannot find it out yourself (Studio state, connected tools, files and the ledger are yours
   to check, never the user's to recite).

If any one is false, do not ask. State the assumption in one line and build.

## Round one: the start of a project

At most **five** questions, plus a fidelity pass question asked conditionally when reference availability is not yet known. Five is a
ceiling. Pick the ones still open after reading the request, most consequential first. Use the
client's structured question tool when it has one (`AskUserQuestion` in Claude Code); otherwise the
numbered format in `SKILL.md`. Every question carries likely options and your recommended answer, so
"defaults" is a complete reply.

| # | Question | Ask it when | Why it earns a slot |
| --- | --- | --- | --- |
| 1 | **Reference.** A game, a video, screenshots to match? | No reference was given | Decides the look more than any adjective. Prefer extracting frames from supplied videos or links with `scripts/reference_frames.py` (see `reference-capture.md`); ask for screenshots only if extraction is unavailable or fails. Retain the selected capture path in the ledger |
| 2 | **Interface tone.** Restrained and flat (hairline edges, one accent colour, lots of air), or ornate and stylised (rims, crests, glow)? Name a game whose menus they like | The genre does not settle it | The stock panel and button prompts produce ornate gold rims. On a grounded game that is what users call "AI-looking", and it costs a full regeneration to undo |
| 3 | **What is in the game.** Offer a checklist for the genre rather than an open question (below) | The request names a genre, not a feature list | Users assume features. A checklist turns an assumption into a decision in one reply |
| 4 | **Players.** Solo against bots, multiplayer, or multiplayer with bots filling empty slots? | Not stated | Changes the server architecture, not just content |
| 5 | **Spend.** How many paid generations, and is paid generation authorized? | Always, unless already given | Recommend a number sized to the build: one generation for each distinct object the player will see, plus the main surface materials (ground, paths, docks, walls) and planned follow-ups. Recommend 0 only when the user has already declined paid generation |
| 6 | **Finish.** Playable prototype, or a polished build that is checked screen by screen? | Not stated | Sets how much verification and iteration to plan |
| 7 | **Fidelity pass.** | Ask plainly with a supplied reference; otherwise ask "if you have a reference, do you want a fidelity pass against it?" in the same round. A "none" reference answer also settles this as inapplicable; never fold it into "finish" or add a second intake round | See `fidelity-pass.md` |

### Feature checklists (question 3)

Multi-select. Lead with your recommended set already ticked. Shooter:

- Startup sequence (studio-style ident before the title screen)
- Title screen with the player's character on it
- Lobby / matchmaking screen, loadout screen, settings, how-to-play
- HUD beyond health and ammo: minimap or sensor, damage direction and screen feedback, kill feed,
  scoreboard
- Progression: levels, ranks, unlocks, a results screen that shows what the match earned
- Bots
- Admin or debug panel for the owner
- Mobile layout

Tycoon / simulator: currency HUD, shop, upgrades, rebirth, offline earnings, pets or tools, daily
reward, settings, codes. Obby / platformer: checkpoints, stage select, timer and leaderboard, skins,
win screen. Write a list for any other genre in the same shape: the screens, the systems, the things
players of that genre take for granted.

Anything unticked is **out**, and you say so in the brief, so its absence later is a decision the
user made rather than something you forgot.

## The opening prompt

Users who want a maximal-fidelity build open with the prompt below; it is the starter prompt in the
root README and the Codex guide. It is written in the user's words rather than one line per slot,
and it does not skip round one. Read it against the question bank, record what it settles in
`decisions` with `by: "user"`, and ask only the questions it leaves open.

```text
I want you to make the game exactly like "<put the exact game idea and game link if helpful here, and provide minimum 4 image references for builds and GUI if you want a specific style>", no cap on generations, do as much as needed on all ends to make it exactly like the references I provided in VFX, build style, skybox, and GUI style down to the tiniest detail, take as long as you need. Spam fidelity passes until it is perfect, triple-A style quality like the references. Search up as many pictures and videos as needed to make everything 1 to 1 perfect for the game, so get the references.
```

Read each phrase as the slot it belongs to, and take the slot's rule rather than the literal
instruction:

| Phrase | Slot | Reading |
| --- | --- | --- |
| "exactly like <game>", images attached | 1 Reference | Supplied. The attached images are the reference the likeness claim is measured against and the stills the fidelity pass compares (`reference-capture.md`). Run `scripts/reference_frames.py` on a linked clip only after the user confirms they own it |
| "exactly like <game>", nothing attached | 1 Reference | A likeness claim that cannot be measured. Ask question 1 for screenshots or a clip the user owns; if they decline, build to the style words, record `"reference": { "supplied": false }` and make no likeness claim |
| "search up as many pictures and videos as needed" | 1 Reference | Not an instruction to fetch footage: the builder never goes looking (`reference-capture.md`). It points at the images the user attached |
| "no cap on generations" | 5 Spend | Paid generation authorized, no number. The ledger needs a numeric ceiling, so ask question 5 for it. Recommend the full build (one generation per distinct object, the surface materials, planned follow-ups) plus headroom for the fidelity pass: the user has said they would rather spend than stop. A pass that needs more still states the number and waits |
| "down to the tiniest detail", "take as long as you need", "triple-A quality" | 6 Finish | Polished build, checked screen by screen |
| "spam fidelity passes until it is perfect" | 7 Fidelity pass | Opt-in: with a supplied reference, write `opted_in` to `.forgegui-fidelity`. One consented pass already loops compare, fix the biggest gaps, compare again; another pass is a new request after the report, not a standing order |

Still open, asked in the same round, most consequential first: **features** (question 3, the genre
checklist with the named game's set already ticked, because "exactly like X" names the game, not
its screens), **players** (question 4), the **spend number** (question 5), and **interface tone**
(question 2) only when no attached image shows the HUD or a menu. That is three or four questions,
inside the ceiling; the fidelity pass is settled and is not asked again.

A placeholder left in the quotes is an open reference: ask question 1 and read the rest of the
prompt as above. This is an opening prompt for a directory with no `forgegui-project.json`. On an
existing project the same text is a later round: a line that explicitly changes a recorded decision
supersedes it, and only an ambiguous contradiction earns a question.

## Later rounds: the start of a prompt

Before acting on each new user message, read it against what is already decided and apply the rule
above. Most prompts need **no** question. When one does, ask at most **three**, in the same format,
then build. Never stack a check-in on top of a brief or a go-ahead: one interruption per prompt.

Ask when the prompt:

- **Names a new system or screen without saying what it does or where it shows.** "Add a level
  system": what earns experience, is it saved, where is the level displayed? "Add an admin panel":
  who counts as an admin, and which commands?
- **Complains about the look without giving a target.** "It doesn't look right", "not what I wanted",
  "make it AAA". Do not guess again. Ask which screen is furthest off and what it should resemble,
  and ask for a reference if there still is none. A second guess costs a rebuild; the question costs
  a line.
- **Is a wholesale redo.** "Redo everything": what must survive, what is the single biggest miss?
- **Needs more paid generation than was authorized.** Say the new number and what it buys.
- **Ambiguously contradicts an earlier decision.** Clarify only what is ambiguous. An explicit change supersedes the prior decision immediately; record it and proceed.

Do not ask when the prompt is a bug report, a specified tweak ("make the buttons flat dark bars"),
"continue", or anything whose answer is already in `decisions`. Do not ask about taste you can
resolve from the recorded interface tone and reference. Do not ask the same question twice in a
project, in any wording.

## Record the answers

Write answers to `decisions` in `forgegui-project.json` (see `project-manifest.md`). Record each resolved answer with its topic, date and source. When the user accepts "defaults", store the concrete recommendation they accepted (including the numeric paid-generation ceiling, explicit spending authorization, and selected/excluded features for the relevant topics), with `by: "defaults"`; never store only the word "defaults" or invent an unoffered recommendation. Append changes to preserve history; the latest entry in array order for a topic supersedes earlier entries. An explicit user change is the new decision: record it with `by: "user"` and proceed without redundant confirmation. Ask only when the change is ambiguous. A later session, a resumed job,
or a context compaction then has the decision without the conversation. Read `decisions` at the
start of every prompt, before deciding whether to ask anything.

## After the answers

Play back a brief of three to five lines: what you will build, what is explicitly out, the
reference and interface tone, and the planned generation count. The brief is notice, not a second
gate, when spend was authorized and the plan fits it.
