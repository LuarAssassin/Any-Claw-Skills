# Project Structure Templates

The generated project should follow a predictable contract so the extension skills can inspect and modify it later.

The key rule is: the project structure should express an **assistant product**, not just a programming language layout.

## Golden Path Contract

The primary release contract is the `Standard / Python` structure:

```text
{{PROJECT_NAME}}/
├── src/
│   └── {{package_name}}/
│       ├── __init__.py
│       ├── __main__.py
│       ├── config.py
│       ├── core/
│       ├── providers/
│       ├── channels/
│       ├── tools/
│       └── mcp/
├── tests/
├── pyproject.toml
├── Dockerfile
├── docker-compose.yml
├── .env.example
└── README.md
```

This is the structure that `add-channel`, `add-domain`, `add-provider`, and `add-tool` should expect first.

## Other Tier Layouts

Other tier layouts may differ, but they should still preserve the same conceptual areas:

- entrypoint
- assistant core or runtime loop
- config
- providers
- channels
- domain packs / tools
- memory or persistence surface when selected
- automation or scheduling surface when selected
- security or policy surface when selected
- optional MCP or integration surface

If a Preview tier uses a shallower structure, keep the mapping from these concepts obvious.

## Composition Rule

No matter which tier is chosen, the generated project should still read as one assistant product:

- channels should look like part of the assistant
- domain packs should look first-class
- prompts, tools, and MCP should align with the chosen vertical
- later `add-*` skills should be able to inspect and extend the result
