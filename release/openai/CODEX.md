# ForgeGUI for local Codex

This package uses the same ForgeGUI MCP service and generation, preparation,
run-linking and publishing workflow as Claude. Its endpoint is recorded in
`codex-config.toml`; the default Codex build targets production. Staging keys
cannot authenticate production requests. Account capabilities, credits and
publishing-connection permissions still apply.

## Install

Use Codex on the machine running Roblox Studio. Configure the ForgeGUI MCP
connection separately from the bundled skill, using Codex's native bearer-token
support. This package deliberately has no bundled MCP server, avoiding a second
unauthenticated connection or a credential embedded in an archive.

1. Create a production ForgeGUI account key at https://forgegui.com under
   **Profile → MCP API keys**. Use `library:read` for free discovery;
   `generation:read` for owned job status and `generation:write` only for
   authorized generation. Keep the key out of chat, files and command arguments.
2. Supply `FORGEGUI_API_KEY` through the environment of the Codex process using
   your local secret manager. A desktop application launched outside that
   environment will not inherit it. OAuth login is not required for this path.
3. Review existing ForgeGUI entries with `codex mcp list`. Keep a rollback copy
   of existing settings; disable any preview/plugin connection before replacing
   it. Merge the packaged `codex-config.toml` table into `~/.codex/config.toml`,
   replacing an existing `[mcp_servers.forgegui]` table rather than duplicating it.
   Do not replace the entire user configuration or remove the Studio connection.
4. From this extracted package directory, copy the shared skill to Codex's user
   skill directory. The command refuses to overwrite an existing skill:

   ```bash
   mkdir -p ~/.agents/skills
   test ! -e ~/.agents/skills/forgegui-roblox-builder && cp -R skills/forgegui-roblox-builder ~/.agents/skills/
   ```

   For an update, first move the existing skill outside the discovery directory
   as a rollback copy, then install the replacement. Alternatively, load this
   skill-only package through your existing local plugin marketplace; do not
   install both copies.
5. Restart Codex. Confirm exactly one ForgeGUI server in `/mcp`, invoke
   `$forgegui-roblox-builder`, and perform a free `library_search` for `tree`.
   Missing credentials or HTTP 401 mean authentication failed; do not generate
   or change endpoints to work around it. Missing scopes require a deliberately
   selected replacement key, not automatic privilege expansion.

## Studio and generation acceptance

Connect Roblox Studio separately through **Assistant → … → Manage MCP Servers →
Enable Studio as MCP server → Quick connect → Codex CLI**, then restart Codex.
Follow the bundled [skill](skills/forgegui-roblox-builder/SKILL.md), including
selected-place preflight, capability checks and publisher selection.

With an explicitly authorized asset count and credit ceiling, generate one
asset, preserve its request/job identifiers, poll it, and use the same ForgeGUI
publication tools and pinned receipts as Claude. Verify insertion and orientation
in the selected Studio place; for audio, verify experience access and actual
playback. Never automatically retry ambiguous paid requests. Package validation
and a free production search do not prove these Studio acceptance steps.

## Build and rollback

From the source repository, run `python3 release/openai_package.py build --mode codex`
and `python3 release/openai_package.py check --mode codex`. Output defaults to
`dist/openai/codex/forgegui-roblox-builder`. `--channel staging-beta` selects an
explicit staging test package. The separate default OpenAI preview remains
staging-only, and hosted marketplace submission remains blocked pending its
own authentication/review work. No backend or database deployment is needed.

To roll back, remove the installed skill (or disable its plugin), remove only
the ForgeGUI MCP table, and restore the recorded configuration. Restart Codex.
Revoke the ForgeGUI key when no longer needed; leave Studio configured.

[Codex MCP authentication](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)
