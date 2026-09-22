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
| 5 | **Spend.** How many paid generations, and is paid generation authorized? | Always, unless already given | Recommend a number. 0 is a valid recommendation |
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
