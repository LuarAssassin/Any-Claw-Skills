# Golden Path Example: Standard Python Productivity Assistant

## Scenario

A Claude Code user wants a personal assistant for daily task management, summaries, and a Telegram entrypoint. They do not care about advanced architecture choices and want the most supported path.

## Selected Options

| Choice | Value |
|-------|-------|
| Project name | `my-productivity-assistant` |
| Tier | `Standard` |
| Stack | `Python` |
| Provider | `OpenAI` |
| Channels | `CLI`, `Telegram` |
| Domain | `Productivity` |
| Options | `.env.example`, `Docker`, `MCP server` |

## Generated Tree

```text
my-productivity-assistant/
├── src/
│   └── my_productivity_assistant/
│       ├── __init__.py
│       ├── __main__.py
│       ├── config.py
│       ├── core/
│       ├── providers/
│       │   └── openai.py
│       ├── channels/
│       │   ├── cli.py
│       │   └── telegram.py
│       ├── tools/
│       │   └── productivity/
│       └── mcp/
│           └── productivity_server.py
├── tests/
├── pyproject.toml
├── Dockerfile
├── docker-compose.yml
├── .env.example
└── README.md
```

## Critical Files

- `pyproject.toml`: dependencies for the Standard/Python assistant
- `src/my_productivity_assistant/providers/openai.py`: primary provider implementation
- `src/my_productivity_assistant/channels/cli.py`: local validation path
- `src/my_productivity_assistant/channels/telegram.py`: real messaging path
- `src/my_productivity_assistant/tools/productivity/`: domain pack tools
- `src/my_productivity_assistant/mcp/productivity_server.py`: optional MCP surface
- `.env.example`: OpenAI, Telegram, and runtime configuration

## Run Steps

1. Fill in `.env` from `.env.example`
2. Install project dependencies
3. Start the CLI entrypoint to validate locally
4. Enable the Telegram bot token and webhook or polling mode
5. Expand later with `/add-domain`, `/add-channel`, `/add-provider`, or `/add-tool`

## Why This Is The Golden Path

- strongest documentation coverage
- strongest release verification coverage
- easiest story for a new Claude Code user
- clear upgrade path to Beta surfaces later
