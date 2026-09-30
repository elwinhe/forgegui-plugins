# Changelog

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
