# Project Structure Templates

The generated project should follow a predictable contract so the extension skills can inspect and modify it later.

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
- config
- providers
- channels
- tools
- optional MCP or integration surface

If a Preview tier uses a shallower structure, keep the mapping from these concepts obvious.
