# ForgeGUI OpenAI staging preview

This package is generated from the shared Claude skill source. It is an offline
release artifact, not an installed, authenticated or submitted plugin. The
endpoint is staging, with separate accounts/data from production. OpenAI OAuth
readiness is **unverified**; do not put API keys in manifests or headers.

The root plugin.json and mcp.json use the portable Agent Plugins layout.
The .codex-plugin/plugin.json and .mcp.json provide compatibility for legacy
loaders. No app ID is invented, no Claude userConfig is copied, and no hooks
are bundled. Authentication must use the host's secure connection setup once
the backend supports it. Missing tools or authentication are blockers, not
permission to switch endpoints or request keys in chat.

Read [the runtime skill](skills/forgegui-roblox-builder/SKILL.md) first. Remote-only
ChatGPT/Codex can perform exposed ForgeGUI operations within authorization and
then hand off assets; Studio editing and verification require separate local
Studio tools. A filesystem is optional: retain the handoff ledger in the
response or a downloadable artifact when local files are unavailable.

## Rebuild and check (from the source repository)

```bash
python3 release/openai_package.py build
python3 release/openai_package.py check
python3 tests/test_openai_package.py
```

Output is dist/openai/forgegui-roblox-builder, separate from the Claude plugin.
Use --output /your/chosen/path/forgegui-roblox-builder on either command for a
caller-chosen destination. The final folder name must match the plugin name.
No global installation, marketplace registration or network request is made.
An existing output must exactly match; drift fails without overwriting files.
After reviewing source changes, build into a new destination or explicitly
remove only the old generated directory, then rebuild. Do not edit copies.

release/openai/sources.json is the reviewed source allowlist. Add entries there
when adding shared resources. Source files are copied byte-for-byte; shared
SKILL.md becomes WORKFLOW.md beside the OpenAI routing SKILL.md, preserving
relative references. provenance.json records source hashes. Check compares
every byte and the complete file inventory, rejecting extra files and symlinks.
Caches and unlisted files are never copied. Build and check also require the
backticked resource paths in WORKFLOW.md to be bundled, including its
`luau/`, `tools/` and `tests/` shorthand under `references/`.

## Remaining release gates

Both --channel production and --mode submission fail closed. Endpoint
availability comes only from release/channels.json; production is unavailable.
Even a future available endpoint will require an explicit packaging review to
remove the OpenAI OAuth gate. Required evidence before release includes hosted
OAuth/secure authentication and tenant/scope isolation, real registered MCP
mapping if required by the target surface, fresh-client loading, supported
publication and selected-creator access, and a separately authorized bounded
Studio import/playback/playtest. Offline checks prove none of those live facts.
Marketplace submission, deployment, legal/license decisions and registration
remain separate work.

Packaging format reference, inspected September 23, 2026:
[OpenAI package documentation](https://developers.openai.com/plugins/build/plugins).
