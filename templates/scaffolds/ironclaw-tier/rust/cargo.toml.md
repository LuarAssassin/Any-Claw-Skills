# cargo.toml.md

Template for the Enterprise/Rust (IronClaw-tier) scaffold.

## Generated File: `Cargo.toml`

```toml
[package]
name = "{{PROJECT_NAME}}"
version = "0.1.0"
edition = "2021"
description = "{{PROJECT_DESCRIPTION}}"

[dependencies]
tokio = { version = "1", features = ["full"] }
reqwest = { version = "0.12", features = ["json"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
dotenv = "0.15"
tracing = "0.1"
tracing-subscriber = "0.3"
async-trait = "0.1"
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{PROJECT_NAME}}` | Crate name used by Cargo (lowercase, hyphens allowed, e.g. `my-agent`) |
| `{{PROJECT_DESCRIPTION}}` | One-line description embedded in the package metadata |
