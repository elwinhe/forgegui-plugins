# Portable package schema fixtures

Unmodified Agent Plugins 1.0.0 schemas fetched September 23, 2026:

- https://agent-plugins.org/schemas/1.0.0/plugin.schema.json
- https://agent-plugins.org/schemas/1.0.0/mcp.schema.json

These are the schema URLs declared by the current official OpenAI packaging
documentation: https://developers.openai.com/plugins/build/plugins.
Tests use these pinned files offline. The schemas validate portable structure;
builder checks additionally enforce release channels, credential-free remote
configuration, path containment and source drift. OpenAI compatibility fields
are separately checked with plugin-creator's validate_plugin.py at handoff.
