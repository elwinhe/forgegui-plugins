# ForgeGUI client plugin setup checklist

This download installs local client configuration and connects that client to the ForgeGUI account represented by the API key you supply. It is not a silent browser one-click setup, does not issue a key, and does not prove that generation or Roblox Studio import works.

## Account key and endpoint

In ForgeGUI, open **Profile → MCP API keys** and create an expiring, revocable account key with only the scopes you need:

- `library:read` allows free library discovery.
- `generation:read` reads account-owned jobs and preparation results.
- `publication:read` polls owned publications; `publication:write` explicitly uploads owned artifacts to the configured shared group.
- `runs:read` retrieves run records; `runs:write` creates and records runs.
- `generation:write` also authorizes preparation (which does not charge generation credits); generation can spend credits and requires a paid Starter-or-higher entitlement. Omit it until the account owner authorizes generation.

The ForgeGUI account key is separate from a Claude or Codex subscription and from the Roblox Studio connection. Never put the key in chat, command arguments, shell history, logs, screenshots, source files, or archives.

This package targets the ForgeGUI staging project at `vzzqjekupwutoaasswwd.supabase.co`; confirm it before installation by opening `plugins/forgegui-roblox-builder/.mcp.json` and reading the `url`. Staging keys, data, and behavior are not production. Do not hand-edit that URL to repoint the bundle; a package for a different environment must be rebuilt from source against a reviewed endpoint.

Before installing, disable or remove any manually configured ForgeGUI MCP connection in the client. Record its name and settings first so you can roll back. Running the bundled and manual definitions together can produce duplicate connections or ambiguous tool names.

## Connect Roblox Studio separately

On the machine running Studio, use the official Studio flow:

1. Open **Assistant** in Roblox Studio.
2. Select **… → Manage MCP Servers**.
3. Turn on **Enable Studio as MCP server**.
4. Expand **Quick connect** and enable **Codex CLI** or **Claude Code**, matching the client you installed.
5. Confirm Studio shows the connection indicator, then start a new client session.

The current authoritative instructions are at <https://create.roblox.com/docs/studio/mcp>. This bundle contains no Studio adapter, executable path, or remote Studio endpoint. ForgeGUI and Studio remain two separate MCP connections.

## Verify without spending

Start a new client session after installation or configuration changes. Confirm exactly one ForgeGUI connection is loaded and, when Studio work is intended, that the official Studio connection is listed separately.

1. List or discover ForgeGUI tools. Loading the definition alone does not prove authentication. If the ForgeGUI server is absent from `/mcp` entirely, with no failure listed, the `forgegui_api_key` configuration is unset and the client skipped the server silently; run `/plugin configure` and start a new session before concluding anything about the backend.
2. With a `library:read` key, call `library_search` using a harmless query such as `tree`.
3. Treat an HTTP 401 as an authentication failure: re-enter or re-export the key and start another new session.
4. If a tool reports a missing scope, deliberately mint or select an appropriately scoped replacement key. Do not broaden permissions by default.

No paid call is part of connection verification.

## Manual end-to-end checklist

Proceed only after the free check succeeds and the account owner authorizes a bounded spend:

- Select the intended Studio place and carry its `studio_id` through Studio calls.
- Confirm `generation:write`, paid entitlement, requested asset count, and budget.
- Verify a supported route from the expected ForgeGUI artifact format into Studio before spending.
- Generate one authorized asset with one stable `request_id`; retain the returned `job_id`.
- Poll `generation_status` to a terminal result. Never automatically retry `outcome_unknown`, timeouts, or ambiguous provider outcomes.
- Verify artifact format and integrity before import. A URL is not a Roblox asset ID.
- Import only through a verified route, inspect the saved Edit-mode instance, and run a focused playtest if gameplay changed.
- Record the job ID, imported Roblox asset ID or instance path, and checks actually performed. Keep “generated,” “imported,” and “gameplay verified” distinct.

Check the bundled skill for import findings and live-tool requirements. Personal-account Open Cloud tests reported image, audio and GLB uploads, but do not establish that the connected MCP exposes publishing or that the target experience has access. Verify that route before spending; use a manual handoff only with the user's agreement.

## Rollback

Uninstall or disable this bundle, start a new client session, and restore the recorded manual ForgeGUI entry only after the bundled copy is gone. Revoke the bundle's ForgeGUI key from **Profile → MCP API keys** if it is no longer needed or may have been exposed. Removing this bundle does not disable the separate Studio MCP server.
