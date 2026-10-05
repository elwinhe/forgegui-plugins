# Changelog

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
