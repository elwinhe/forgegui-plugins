# Changelog

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
