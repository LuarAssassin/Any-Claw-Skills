# readme.md

Template for the Pico/Go tier scaffold. The project README with quick-start
instructions, API reference, and deployment notes.

## Generated File: `README.md`

```markdown
# {{PROJECT_NAME}}

{{PROJECT_DESCRIPTION}}

A lightweight personal assistant built with Go and the standard library.
Connects to any OpenAI-compatible LLM provider and exposes a simple HTTP API
for chat, webhooks, and conversation management.

---

## Quick Start

### Prerequisites

- Go 1.22+
- An API key for an OpenAI-compatible LLM provider

### Run Locally

```bash
# Clone and enter the project
git clone {{REPO_URL}}
cd {{PROJECT_NAME}}

# Set required environment variable
export PROVIDER_API_KEY="sk-your-key-here"

# Run
go run .
```

The server starts on `http://localhost:8080`.

### Try It

```bash
# Health check
curl http://localhost:8080/health

# Send a message
curl -X POST http://localhost:8080/chat \
  -H "Content-Type: application/json" \
  -d '{"user_id": "me", "message": "Hello, who are you?"}'

# Reset conversation
curl -X POST http://localhost:8080/reset \
  -H "Content-Type: application/json" \
  -d '{"user_id": "me"}'
```

---

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `PROVIDER_API_KEY` | Yes | -- | API key for the LLM provider |
| `PROVIDER_BASE_URL` | No | `{{PROVIDER_DEFAULT_URL}}` | Base URL for chat completions |
| `PROVIDER_MODEL` | No | `{{PROVIDER_DEFAULT_MODEL}}` | Model identifier |
| `PORT` | No | `8080` | HTTP listen port |
| `CHANNEL_TOKEN` | No | -- | Bot token for messaging channel |
| `CHANNEL_SECRET` | No | -- | Webhook signing secret |
| `SYSTEM_PROMPT` | No | *(built-in)* | System instruction for the assistant |
| `LOG_LEVEL` | No | `info` | Log verbosity |

See [CONFIG.md](CONFIG.md) for full details and provider compatibility table.

---

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Liveness check, returns `{"status":"ok"}` |
| `POST` | `/chat` | Send a message, receive the assistant reply |
| `POST` | `/webhook` | Inbound channel messages (platform-specific) |
| `POST` | `/reset` | Clear a user's conversation history |

### POST /chat

**Request:**

```json
{
  "user_id": "user-123",
  "message": "What is the capital of France?"
}
```

**Response:**

```json
{
  "reply": "The capital of France is Paris."
}
```

---

## Build & Deploy

### Build Binary

```bash
CGO_ENABLED=0 go build -ldflags="-s -w" -o {{PROJECT_NAME}} .
```

### Docker

```bash
docker build -t {{PROJECT_NAME}} .
docker run -p 8080:8080 -e PROVIDER_API_KEY="sk-..." {{PROJECT_NAME}}
```

### Deploy to Fly.io

```bash
fly launch --name {{PROJECT_NAME}}
fly secrets set PROVIDER_API_KEY="sk-..."
fly deploy
```

---

## Project Structure

```
.
├── main.go          # Application entry point (all logic in one file)
├── go.mod           # Go module definition
├── Dockerfile       # Multi-stage container build
├── CONFIG.md        # Environment variable reference
└── README.md        # This file
```

---

## License

{{LICENSE}}
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{PROJECT_NAME}}` | Name of the project and binary |
| `{{PROJECT_DESCRIPTION}}` | One-line project description |
| `{{REPO_URL}}` | Git clone URL for the repository |
| `{{PROVIDER_DEFAULT_URL}}` | Default LLM provider base URL |
| `{{PROVIDER_DEFAULT_MODEL}}` | Default model identifier |
| `{{LICENSE}}` | License statement (e.g. `MIT`, `Apache-2.0`, or full text) |
