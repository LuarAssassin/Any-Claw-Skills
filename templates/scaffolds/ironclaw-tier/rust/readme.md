# readme.md

Template for the Enterprise/Rust (IronClaw-tier) scaffold.

## Generated File: `README.md`

```markdown
# {{PROJECT_NAME}}

{{PROJECT_DESCRIPTION}}

> **IronClaw-tier scaffold** -- this is a minimal starting point, not a
> production-ready system. Expect to expand substantially before deploying.

## What you get

- Tokio async runtime with graceful shutdown via `tokio::select!`
- `Provider` trait wrapping an OpenAI-compatible chat completions endpoint
- `Channel` trait with a stdin/stdout reference implementation
- Conversation history management with configurable depth
- Structured logging via `tracing`
- Configuration from environment variables (`.env` supported via `dotenv`)

## What you still need to build

- **Authentication and secrets management** -- replace the bare env-var key
  loading with a vault or secret manager for production use.
- **Persistent storage** -- conversation history lives in memory; add a database
  or file-backed store.
- **Real channel adapters** -- the scaffold ships with stdin only. Implement the
  `Channel` trait for HTTP webhooks, WebSocket, gRPC, or messaging platforms.
- **Tool / function-calling support** -- extend the `Provider` trait and agent
  loop to handle tool-use responses.
- **Error handling and retries** -- add exponential backoff, circuit breakers,
  and structured error types.
- **Tests** -- unit tests for the provider, integration tests for the agent
  loop, and end-to-end tests for each channel.
- **CI/CD pipeline** -- `cargo fmt --check`, `cargo clippy`, `cargo test`, and
  container builds.

## Quick start

```bash
# Create a .env file
cat > .env << 'EOF'
{{PROVIDER_API_KEY_ENV}}=sk-your-key-here
{{PROVIDER_MODEL_ENV}}={{DEFAULT_MODEL}}
{{PROVIDER_BASE_URL_ENV}}={{DEFAULT_PROVIDER_URL}}
MAX_HISTORY=20
EOF

# Build and run
cargo build --release
cargo run
```

## Project structure

```
{{PROJECT_NAME}}/
  Cargo.toml
  .env
  src/
    main.rs      # Entrypoint, config, traits, agent loop
```

As the project grows, split `main.rs` into modules:

```
src/
  main.rs        # Entrypoint only
  config.rs      # Config struct and loading
  provider.rs    # Provider trait + implementations
  channel/
    mod.rs       # Channel trait
    stdin.rs     # Stdin adapter
    http.rs      # HTTP webhook adapter
  agent.rs       # Agent loop and history management
```

## License

{{LICENSE}}
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{PROJECT_NAME}}` | Project / crate name |
| `{{PROJECT_DESCRIPTION}}` | One-line project description |
| `{{PROVIDER_API_KEY_ENV}}` | Environment variable name for the LLM API key |
| `{{PROVIDER_MODEL_ENV}}` | Environment variable name for the model identifier |
| `{{DEFAULT_MODEL}}` | Default model string (e.g. `gpt-4o`) |
| `{{PROVIDER_BASE_URL_ENV}}` | Environment variable name for the provider base URL |
| `{{DEFAULT_PROVIDER_URL}}` | Default provider API base URL (e.g. `https://api.openai.com/v1`) |
| `{{LICENSE}}` | License identifier (e.g. `MIT`, `Apache-2.0`) |
