# readme.md

Template for the Standard/Python tier scaffold.

## Generated File: `README.md`

```markdown
# {{PROJECT_NAME}}

{{PROJECT_DESCRIPTION}}

## Quick start

### Prerequisites

- Python 3.11+
- An API key for your LLM provider

### Install from source

```bash
git clone {{REPOSITORY_URL}}
cd {{PROJECT_NAME_SLUG}}
pip install -e ".[dev]"
```

### Configure

Copy the example environment file and fill in your values:

```bash
cp .env.example .env
```

Key variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `{{ENV_PREFIX}}_PROVIDER_API_KEY` | Yes | API key for the LLM provider |
| `{{ENV_PREFIX}}_PROVIDER_MODEL` | No | Model to use (default: `{{DEFAULT_MODEL}}`) |
| `{{ENV_PREFIX}}_ENABLED_CHANNELS` | No | Comma-separated channel list (default: `cli`) |
| `{{ENV_PREFIX}}_LOG_LEVEL` | No | `DEBUG`, `INFO`, `WARNING`, `ERROR` (default: `INFO`) |

### Run

```bash
# Using the CLI entry point
{{CLI_COMMAND}}

# Or directly as a module
python -m {{PACKAGE_NAME}}
```

### Docker

```bash
docker build -t {{PROJECT_NAME_SLUG}} .
docker run --env-file .env -p {{PORT}}:{{PORT}} {{PROJECT_NAME_SLUG}}
```

## Development

```bash
# Install dev dependencies
pip install -e ".[dev]"

# Run tests
pytest

# Lint and format
ruff check .
ruff format .

# Type check
mypy {{PACKAGE_NAME}}/
```

## Project structure

```
{{PROJECT_NAME_SLUG}}/
  {{PACKAGE_NAME}}/
    __init__.py
    __main__.py      # Entry point, agent loop, shutdown handling
    config.py        # Pydantic settings, .env loading
  tests/
    __init__.py
    test_config.py
  pyproject.toml
  Dockerfile
  .env.example
  README.md
```

## Architecture

```
User --> Channel Adapter --> Agent Loop --> Provider Router --> LLM
                                |
                           Tool Registry
```

- **Provider Router** -- sends chat-completion requests to the configured LLM backend (OpenAI-compatible API).
- **Tool Registry** -- discovers and invokes callable tools the agent can use.
- **Channel Adapters** -- abstract inbound/outbound messaging (CLI, Discord, Slack, webhooks, etc.).

## License

{{LICENSE}}
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{PROJECT_NAME}}` | Human-readable project name |
| `{{PROJECT_NAME_SLUG}}` | Lowercase hyphenated name for URLs and directory names |
| `{{PROJECT_DESCRIPTION}}` | One-line project description |
| `{{REPOSITORY_URL}}` | Git clone URL |
| `{{ENV_PREFIX}}` | Environment-variable prefix, uppercase |
| `{{DEFAULT_MODEL}}` | Default LLM model identifier |
| `{{CLI_COMMAND}}` | CLI entry-point command name |
| `{{PACKAGE_NAME}}` | Python package name for imports |
| `{{PORT}}` | Port the application listens on |
| `{{LICENSE}}` | License name (e.g. MIT, Apache-2.0) |
