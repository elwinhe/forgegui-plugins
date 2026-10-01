# ForgeGUI for Claude Desktop

Install `forgegui.mcpb` to connect Claude Desktop on macOS or Windows to your production ForgeGUI account. This package bundles its Node server and dependencies; users do not run npm.

## Install and verify

1. Download `forgegui.mcpb` from the reviewed Desktop extension workflow artifact. Extract the GitHub artifact ZIP first.
2. Open the bundle in Claude Desktop, or use Settings → Extensions → Advanced settings → Install Extension. Organization policy may restrict local extensions.
3. Enter a **production ForgeGUI MCP API key** from https://forgegui.com, Profile → MCP API keys, in the masked extension setting. Start with `library:read`; add `generation:read` for job status and `generation:write` only for authorized generation. Never enter a Roblox Open Cloud key here.
4. Disable duplicate manual ForgeGUI connections. Start a new chat, list the ForgeGUI tools, and perform a free `library_search` to verify authentication before generating anything.

Generation spends your ForgeGUI credits. Use stable request IDs, save returned job IDs, and check job status after a timeout or lost response. The bridge never automatically retries paid requests; an unknown outcome does not mean the server stopped working.

## Roblox Studio and limitations

This extension connects ForgeGUI only. Connect the official Roblox Studio MCP separately for editing and insertion. Claude Code skills, hooks, local scripts, filesystem access, and terminal tools are not installed by this bundle. Do not assume the Claude Code workflow is available in Desktop. Verify the intended place, delivery/import route, budget, and available tools before paid work; generation or publication alone does not prove Studio import or playback.

The bundle is built and protocol-tested on Linux. Installation in Claude Desktop on macOS/Windows, masked configuration, free authenticated discovery, and separate Studio connection require live acceptance before a general release. No automatic update feed or directory submission is configured: install a newly reviewed bundle to update. Keep the previous bundle for rollback. Uninstall through Desktop's extension settings and revoke the ForgeGUI key when no longer needed.

## Maintainers

From `desktop/`, run `npm ci`, `npm test`, `npm run build`, then `npm run test:bundle`. Build output is `dist/forgegui.mcpb` and its SHA-256 checksum. The build reads the production endpoint from `release/channels.json` and refuses a channel/Claude endpoint mismatch. No credentials are packaged. The CI workflow uploads the installer and checksum for review; it does not deploy or publish a release.

Format reference: https://github.com/modelcontextprotocol/mcpb/blob/main/MANIFEST.md
