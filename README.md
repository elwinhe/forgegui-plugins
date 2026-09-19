# ForgeGUI MCP for Claude Code

Install ID: `mcp@forgegui`. Version `1.3.0` targets staging at `vzzqjekupwutoaasswwd.supabase.co`.

**Launch status (September 16, 2026):** this package intentionally uses the staging MCP while the backend and Studio import workflow are validated. Staging testing verified generation and authentication, not a complete Studio import workflow. `enhance_prompt` failed and `auto_separate` was not verified in the supplied test report. See the setup checklist and bundled skill for image, 3D, and audio import limitations.

This repository is a Claude Code marketplace. It targets the staging ForgeGUI endpoint recorded in `plugins/forgegui-roblox-builder/.mcp.json`. It asks for the ForgeGUI account API key as sensitive user configuration. Staging keys and data are separate from production. Read the [shared setup checklist](./SETUP.md) for key scopes, the exact Studio Quick Connect flow, free verification, the bounded end-to-end checklist, limitations, and rollback.

Create the key in ForgeGUI **Profile → MCP API keys**. Use `library:read` for free discovery, add `generation:read` only to inspect account-owned jobs, and add `generation:write` only when paid generation is intended and authorized. Generation write access requires a paid Starter-or-higher entitlement. The key is separate from the Claude subscription and from the Roblox Studio connection.

## Install

Remove or disable any existing manual ForgeGUI MCP entry first, while keeping a rollback copy of its settings.

```bash
claude plugin marketplace add elwinhe/forgegui-plugins
claude plugin install mcp@forgegui
```

Start Claude Code and run `/plugin configure mcp@forgegui`, then enter `forgegui_api_key` in the masked sensitive field. Do not pass the key as a command argument.

Start a new Claude Code session. Use `/mcp` to confirm one bundled ForgeGUI connection, then ask Claude to list ForgeGUI tools and call free `library_search` before any paid request. Successful loading alone is not evidence that the key authenticated.

Invoke the workflow with the namespaced skill shown by Claude Code, for example:

```text
/mcp:forgegui-roblox-builder Build a small prop, checking Studio import support before paid generation.
```

Enable the separate official Roblox Studio MCP server with the exact Quick Connect steps in [SETUP.md](./SETUP.md), then restart the session. This package does not configure Studio.

Before a manual paid end-to-end test, select the intended Studio place, confirm a bounded asset count and budget, and verify an import route for the expected format. Generate one asset with a stable `request_id`, retain its `job_id`, poll `generation_status` to a terminal result, and never automatically retry `outcome_unknown`. Verify the artifact before import, then record the imported asset ID or instance path and inspect the saved Edit-mode result. The bundled skill distinguishes reported import routes from tools actually exposed by the connected server; do not claim generation proves import or gameplay.

## Update or uninstall

```bash
claude plugin marketplace update forgegui
claude plugin update mcp@forgegui
claude plugin uninstall mcp@forgegui
```

Restart after update/uninstall. If rolling back, restore the previously recorded manual ForgeGUI MCP entry only after the bundled copy is gone. Revoke the ForgeGUI key in **Profile → MCP API keys** when it is no longer needed or may have been exposed.
