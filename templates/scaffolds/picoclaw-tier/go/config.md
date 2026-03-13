# config.md

Template for the Pico/Go tier scaffold. Documents every environment variable
the application reads at startup.

## Generated File: `CONFIG.md`

```markdown
# {{PROJECT_NAME}} -- Configuration

All configuration is read from environment variables. No config files are needed.

## Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `PROVIDER_API_KEY` | API key for the LLM provider. **Must be set.** | `sk-abc123...` |

## Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PROJECT_NAME` | `{{PROJECT_NAME}}` | Display name used in logs and health endpoint |
| `PORT` | `8080` | HTTP listen port |
| `LOG_LEVEL` | `info` | Log verbosity (`debug`, `info`, `warn`, `error`) |
| `PROVIDER_BASE_URL` | `{{PROVIDER_DEFAULT_URL}}` | Base URL of the OpenAI-compatible chat completions API |
| `PROVIDER_MODEL` | `{{PROVIDER_DEFAULT_MODEL}}` | Model identifier to send in requests |
| `CHANNEL_TOKEN` | *(empty)* | Auth token for the messaging channel (e.g. bot token) |
| `CHANNEL_SECRET` | *(empty)* | Signing secret for verifying inbound webhooks |
| `SYSTEM_PROMPT` | `You are {{ASSISTANT_NAME}}, a helpful personal assistant.` | System-level instruction prepended to every conversation |

## Provider Compatibility

The LLM client speaks the OpenAI chat-completions wire format (`POST /chat/completions`).
Any provider that implements this interface works out of the box:

| Provider | `PROVIDER_BASE_URL` | Notes |
|----------|---------------------|-------|
| OpenAI | `https://api.openai.com/v1` | Default |
| Anthropic (proxy) | `https://api.anthropic.com/v1` | Requires an OpenAI-compatible proxy |
| Azure OpenAI | `https://<resource>.openai.azure.com/openai/deployments/<deployment>` | Set model to deployment name |
| Ollama | `http://localhost:11434/v1` | Local models |
| LM Studio | `http://localhost:1234/v1` | Local models |
| Together AI | `https://api.together.xyz/v1` | Hosted open-source models |
| Groq | `https://api.groq.com/openai/v1` | Fast inference |

## Channel Webhook

Inbound messages arrive at `POST /webhook`. The default parser expects:

```json
{
  "user_id": "u123",
  "message": "Hello!"
}
```

Replace `parseChannelMessage` and `sendChannelReply` in `main.go` to support
your specific messaging platform.

## Example `.env` File

```bash
PROVIDER_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
PROVIDER_BASE_URL=https://api.openai.com/v1
PROVIDER_MODEL=gpt-4o-mini
CHANNEL_TOKEN=xoxb-your-bot-token
SYSTEM_PROMPT=You are a concise, friendly assistant called {{ASSISTANT_NAME}}.
```

> **Security note:** Never commit `.env` files to version control. Add `.env`
> to your `.gitignore`.
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{PROJECT_NAME}}` | Name of the project |
| `{{ASSISTANT_NAME}}` | Display name of the assistant persona |
| `{{PROVIDER_DEFAULT_URL}}` | Default base URL for the LLM provider |
| `{{PROVIDER_DEFAULT_MODEL}}` | Default model identifier |
