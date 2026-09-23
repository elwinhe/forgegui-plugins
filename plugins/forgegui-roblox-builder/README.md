# ForgeGUI Roblox Builder

**Staging beta.** This package connects to ForgeGUI's staging project (`vzzqjekupwutoaasswwd.supabase.co`). Staging accounts, keys, credits and data are separate from production, and staging behavior can change without notice. A production release will be published under a non-beta version once the ForgeGUI MCP service is live in production.

The plugin helps Claude Code build Roblox Studio experiences with ForgeGUI-generated assets. It coordinates two separate MCP connections: ForgeGUI (bundled here) for generation, search, preparation and publication, and the official Roblox Studio MCP (configured separately in Studio) for inspecting, editing, inserting and playtesting.

## What installs

| Component | Purpose |
|---|---|
| Skill `forgegui-roblox-builder` | Workflow guidance, references, Luau modules and optional local helpers |
| MCP server `forgegui` | Remote Streamable HTTP endpoint authenticated with your ForgeGUI MCP key |
| `Stop` hook | Read-only reminder for an opted-in fidelity pass. It reads `./.forgegui-fidelity` in the working directory and does nothing when that file is absent. It never writes files or makes network calls |

The package includes shell and Python scripts. Its Bash Stop hook runs when Claude stops; optional helpers run only when invoked. It does not start a local server or install a Studio adapter. Nothing runs at install time.

## Requirements

- Bash for the bundled Stop hook.
- A ForgeGUI account and an expiring MCP key from **Profile → MCP API keys**, entered through `/plugin configure` as a masked value. Request only the scopes you need; `generation:write` spends credits and requires a paid Starter-or-higher plan.
- Roblox Studio with **Enable Studio as MCP server** turned on, for any Studio work. See <https://create.roblox.com/docs/studio/mcp>.
- Optional local helpers, used only when the skill or you run them:
  - Python 3 with Pillow and NumPy: image, palette, texture, skybox and GLB diagnostics.
  - `ffmpeg`/`ffprobe`: extracting frames from a reference video.
  - `lune`: headless checks of the bundled Luau modules.
  - `references/tools/oc_upload.py` and `scripts/open_cloud_upload.sh`: a manual Roblox Open Cloud upload path that reads **your own** `ROBLOX_API_KEY` from your environment. Prefer ForgeGUI publishing connections; never paste a Roblox key into chat.

## Data and effects

- Prompts, references and tool arguments you send through the `forgegui` server go to ForgeGUI. ForgeGUI forwards generation inputs to its AI generation providers to produce the requested assets.
- Generation tools spend ForgeGUI credits. Publishing tools create assets on Roblox under the ForgeGUI publishing connection you select; Roblox moderation applies.
- Your ForgeGUI key is sent only as the `Authorization` header to the configured ForgeGUI endpoint. Roblox publishing keys belong only in ForgeGUI settings, never in MCP arguments, chat or project files.
- Studio actions run through the separate Roblox Studio MCP, on your machine, under your Studio session.

## Support and policies

- Support: [team@forgegui.com](mailto:team@forgegui.com)
- Privacy policy: <https://forgegui.com/privacy>
- Terms of service: <https://forgegui.com/terms>
- Source, setup checklist and changelog: <https://github.com/elwinhe/forgegui-plugins>

Revoke a key in **Profile → MCP API keys** when it is no longer needed or may have been exposed. Uninstalling the plugin does not revoke the key or disable the Studio MCP server.
