# Config Templates

These templates describe the configuration surfaces the generated project should expose. For v0.1.0, optimize them for the golden path first.

## Golden Path Defaults

The most important generated config should support:

- `OPENAI_API_KEY`
- `TELEGRAM_BOT_TOKEN`
- logging level
- optional database path
- optional MCP server settings

## `.env.example`

Every generated project should include `.env.example` with only the variables required by the selected providers, channels, and domains.

For the golden path, that means at minimum:

```env
OPENAI_API_KEY=sk-your-key-here
OPENAI_MODEL=gpt-4o-mini
TELEGRAM_BOT_TOKEN=your-bot-token
LOG_LEVEL=info
DATABASE_URL=sqlite:///data/{{PROJECT_NAME}}.db
```

## Docker

If Docker is selected, generate the Docker assets that match the chosen stack. For the golden path, Docker is recommended and should be documented clearly in the generated project README.

## CI

If CI is selected for the generated project, keep it simple and stack-specific. Do not overbuild a workflow that the selected tier does not need.

## Integration Rule

Whenever channels, providers, or domains are added later, the extension skill should update `.env.example` and related config surfaces to match the project contract.
