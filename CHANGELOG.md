# Changelog

## 1.9.6 — production

- The starter prompt in the root README, the Codex guide and `references/intake.md` is now the maximal-fidelity prompt in the user's own words ("make the game exactly like …, no cap on generations, … spam fidelity passes until it is perfect …", with at least four reference images attached), and round one is kept: the skill reads the prompt against the question bank, records what it settles with `by: "user"` (the reference when images are attached, the finish, the fidelity-pass opt-in and spend authorization) and asks only what it leaves open (features, players, and interface tone when no attached image shows the HUD). Before this change the published prompt was a slot-by-slot template that skipped round one (FOR-748).
- A likeness claim is read into a prompt only when there is something to compare against. With references attached, partial references (fewer than four shots, GUI only, world only) still count as supplied: no second ask, the fidelity pass measures only what they show, and the brief says which surfaces that is. With nothing attached, or the placeholder still in the quotes, "exactly like" and "1 to 1" are read as the finish and as spend authorization; question 1 asks first for the game idea or link plus four shots (wide, HUD, menu, sky or VFX), the rest of the round follows in the same round, `.forgegui-fidelity` waits for the reference, and the brief after round one is the completed prompt built from the answers. A declined reference means a build to the style words with no likeness claim.
- Uncapped paid generation is the default. The skill never asks for a generation number: question 5 asks whether paid generation is authorized and whether the user wants a cap, recommends "authorized, no cap", and is skipped when the prompt already authorizes spend. A cap exists only when the user names one, and only then does the plan reserve inside it, a fidelity pass stop to ask for more, or a later prompt trigger the "needs more than the cap" question. The plan and the brief still state the planned count as notice. The maintainer acceptance steps keep their bounded test spend.
- Guidance only: no scripts, MCP endpoint or tool contract changes. The one consented fidelity pass that loops, the rule that the builder never goes looking for footage, and the rule that there is no likeness claim without a reference are unchanged. The OpenAI staging preview keeps its `1.9.0-beta.1` label.

## 1.9.5 — production

- When any ForgeGUI result carries `error_code: insufficient_credits` or an `upgrade_url`, the builder skill (Claude and Codex) stops every paid call, tells the user in one sentence that their ForgeGUI account is out of credits, gives them https://forgegui.com/plans to upgrade, reports how many planned assets remain unbuilt, and opens a new `request_id` for the same asset only after the user confirms credits were added (the refused job is settled and not retryable; `outcome_unknown` jobs are still never regenerated). Before this change rule 5 only said to stop on insufficient credits, and an account that ran out mid-job reached the agent as an unknown provider outcome, so it retried the same asset under new request IDs (FOR-769).
- Pairs with the ForgeGUI server change that ends an out-of-credits job as `failed` with `error_code: insufficient_credits`, the plans-page message and `upgrade_url`, and refuses a claim below the job's minimum cost. Connector sessions get that guidance from the server instructions; this release carries it into the installed skill.
- Reuse now starts with the account's own earlier work. The skill calls the free `generation_list` tool (ForgeMCP backend, FOR-766) before paying for a new generation or asking the user for job IDs when a request refers to something already made; each listed item carries the `artifact_ref` values that `artifact_publish`, `generation_rig_3d` and the reference fields accept, plus a preview and publication state. `library_search`, `library_details` and `toolbox_search` keep covering public catalog and store assets.
- `references/3d-assets.md` and `references/asset-upload.md` point to the same tool for recovering a lost `job_id` or `artifact_ref` instead of regenerating. A lost `request_id` or publication UUID still cannot be recovered that way.
- Guidance only: no scripts, MCP endpoint or tool contract changes. `generation_list` itself reaches every client when the ForgeMCP backend deploys; this release only updates the skill text. The OpenAI staging preview keeps its `1.9.0-beta.1` label.

## 1.9.4 — production

- ForgeGUI 3D is now the default for every object the player sees whenever a generation route exists, including small props, furniture and background set dressing. Before this change the default covered identity assets and close-up props, the skill called generating every scene object "the expensive failure", and its plan example built a campfire log from Roblox parts.
- The intake spend question recommends a number sized to the build: one generation for each distinct object plus the main surface materials. It recommends 0 only when the user has already declined paid generation.
- Roblox parts and terrain stay for ground and structure shape, collision, triggers, the grey-box layout and backdrops the player can never reach. Main surfaces keep their ForgeGUI materials. Minor surfaces (a trim, a small or rarely seen patch) can stay on a Roblox material by judgment and are not logged as blockouts.
- The typical kit grows from 8-20 to 10-30 props, stated as a typical range rather than a cap.
- Guidance only: no scripts, MCP endpoint or tool contract changes. The OpenAI staging preview keeps its `1.9.0-beta.1` label.

## 1.9.3 — production

- The bundled `forgegui` server sends the plugin version as `X-ForgeGUI-Plugin-Version` and `claude-code` as `X-ForgeGUI-Plugin-Client` on every request. ForgeGUI compares the version with the latest release. When an install is behind, ForgeGUI's MCP instructions tell Claude to recommend the update once, with the update commands, without blocking the request.
- Installs from 1.9.2 and earlier send no version header. ForgeGUI treats a Claude Code connection without it as an older plugin or a manually added server and recommends the same update, so existing installs are covered from the day the server change ships.
- The local Codex package's `codex-config.toml` table sends the same version with `X-ForgeGUI-Plugin-Client: codex`, so outdated Codex packages get Codex update steps instead of Claude commands. The Codex guide gains an Update section. Codex connections without the headers (an older package or `codex mcp add`) get no notice.
- `release/release_channel.py set` writes both headers, and `check` fails when either drifts from `plugin.json`. Release steps now include setting ForgeGUI's `FORGEGUI_MCP_PLUGIN_LATEST_VERSION` secret after merge; one value covers the Claude plugin and the Codex package.
- The README recommends enabling auto-update for the `forgegui` marketplace. Claude Code leaves it off by default for third-party marketplaces.
- No skill guidance or tool contract changes. The OpenAI staging preview keeps its `1.9.0-beta.1` label and sends no version header.

## 1.9.2 — production

- Terrain and structure surfaces now get ForgeGUI materials by default. The builder skill plans one tiled material per player-visible surface (sand, grass, rock, paths, dock planks, walls): a `generation_image` colour tile, prepared with `texture_prep.py`, given normal, roughness and cavity maps by `pbr_maps.py`, and applied as a MaterialVariant with `MaterialKit.luau`. Before this change, the skill left floors, docks and terrain on stock Roblox materials and reached the texture route only after ground "read flat up close".
- Close-up ground that needs relief gets a generated `GroundScatter` patch template, and terrain dressing (rocks, boulders, driftwood, dock pilings, grass clumps) joins the generated kit. Water stays native terrain water.
- Surface materials count in the plan, the typical first pass and the intake spend recommendation, and are generated early, right after the style card. A player-visible surface left on a stock material is logged and reported as a `blockout`.
- Guidance only: no scripts, MCP endpoint or tool contract changes. The OpenAI staging preview keeps its `1.9.0-beta.1` label.

## 1.9.1 — production

- `scripts/reference_frames.py` requires yt-dlp 2026.08.19 (the latest release) or newer before fetching a link. With an older copy it stops before downloading and prints the update command, instead of failing partway through a YouTube download.
- Updates the yt-dlp install hint to follow yt-dlp's current guidance: `pipx install "yt-dlp[default]"` plus a JavaScript runtime such as Deno for full YouTube support (Homebrew's `yt-dlp` already includes Deno).
- `--selftest` covers yt-dlp version parsing. No MCP endpoint or workflow changes. The OpenAI staging preview keeps its `1.9.0-beta.1` label.

## 1.9.0 — production

- Bumps both Claude manifests so existing `1.9.0-beta.1` installs can detect the production endpoint update.
- Selects the production release channel and restores the separate staging endpoint and production denylist.
- Documents replacing staging MCP keys with production keys and verifying free discovery after updating.
- Keeps the separate OpenAI preview on staging at `1.9.0-beta.1`; production/submission remain blocked pending OpenAI OAuth readiness.

## 1.9.0-beta.1 — staging beta

- Labels the owned-catalog release as a staging beta in both manifests; the endpoint, version and label are declared in `release/channels.json` and enforced in CI.
- Installed package: removes committed Python bytecode caches and replaces links that pointed outside the plugin directory with repository URLs marked repository-only.
- Adds an installed `README.md` covering components, requirements, data flow, costs, support and policy links.
- No workflow guidance or MCP endpoint changes; the endpoint is still ForgeGUI staging.

## 1.8.0

- Publishing-connections guidance (#38). Pointed at ForgeGUI staging without a beta label.
