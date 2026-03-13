# main.rs.md

Template for the Enterprise/Rust (IronClaw-tier) scaffold.

## Generated File: `src/main.rs`

```rust
//! {{PROJECT_NAME}} - {{PROJECT_DESCRIPTION}}
//!
//! Enterprise AI agent built on the IronClaw scaffold.
//! This is a minimal stub: extend Provider and Channel implementations
//! to build a production system.

use serde::{Deserialize, Serialize};
use std::env;
use std::sync::Arc;
use tokio::sync::mpsc;
use tracing::{error, info, warn};

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
struct Config {
    provider_api_key: String,
    provider_model: String,
    provider_base_url: String,
    channel_address: String,
    max_history: usize,
}

impl Config {
    fn from_env() -> Result<Self, Box<dyn std::error::Error>> {
        dotenv::dotenv().ok();
        Ok(Self {
            provider_api_key: env::var("{{PROVIDER_API_KEY_ENV}}")
                .unwrap_or_else(|_| "sk-placeholder".into()),
            provider_model: env::var("{{PROVIDER_MODEL_ENV}}")
                .unwrap_or_else(|_| "{{DEFAULT_MODEL}}".into()),
            provider_base_url: env::var("{{PROVIDER_BASE_URL_ENV}}")
                .unwrap_or_else(|_| "{{DEFAULT_PROVIDER_URL}}".into()),
            channel_address: env::var("{{CHANNEL_ADDRESS_ENV}}")
                .unwrap_or_else(|_| "{{DEFAULT_CHANNEL_ADDRESS}}".into()),
            max_history: env::var("MAX_HISTORY")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(20),
        })
    }
}

// ---------------------------------------------------------------------------
// Message types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Message {
    role: String,
    content: String,
}

#[derive(Debug, Clone)]
struct InboundMessage {
    user_id: String,
    text: String,
    reply_tx: mpsc::Sender<String>,
}

// ---------------------------------------------------------------------------
// Provider trait
// ---------------------------------------------------------------------------

#[async_trait::async_trait]
trait Provider: Send + Sync {
    async fn chat(
        &self,
        messages: &[Message],
    ) -> Result<String, Box<dyn std::error::Error + Send + Sync>>;
}

struct HttpProvider {
    client: reqwest::Client,
    api_key: String,
    model: String,
    base_url: String,
}

impl HttpProvider {
    fn new(config: &Config) -> Self {
        Self {
            client: reqwest::Client::new(),
            api_key: config.provider_api_key.clone(),
            model: config.provider_model.clone(),
            base_url: config.provider_base_url.clone(),
        }
    }
}

#[async_trait::async_trait]
impl Provider for HttpProvider {
    async fn chat(
        &self,
        messages: &[Message],
    ) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        let body = serde_json::json!({
            "model": self.model,
            "messages": messages,
        });

        let resp = self
            .client
            .post(format!("{}/chat/completions", self.base_url))
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(format!("Provider returned {}: {}", status, text).into());
        }

        let json: serde_json::Value = resp.json().await?;
        let content = json["choices"][0]["message"]["content"]
            .as_str()
            .unwrap_or("")
            .to_string();
        Ok(content)
    }
}

// ---------------------------------------------------------------------------
// Channel trait
// ---------------------------------------------------------------------------

#[async_trait::async_trait]
trait Channel: Send + Sync {
    async fn listen(
        &self,
        tx: mpsc::Sender<InboundMessage>,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>>;
}

struct StdinChannel;

#[async_trait::async_trait]
impl Channel for StdinChannel {
    async fn listen(
        &self,
        tx: mpsc::Sender<InboundMessage>,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let stdin = tokio::io::BufReader::new(tokio::io::stdin());
        use tokio::io::AsyncBufReadExt;
        let mut lines = stdin.lines();

        while let Some(line) = lines.next_line().await? {
            let line = line.trim().to_string();
            if line.is_empty() {
                continue;
            }
            let (reply_tx, mut reply_rx) = mpsc::channel::<String>(1);
            tx.send(InboundMessage {
                user_id: "local".into(),
                text: line,
                reply_tx,
            })
            .await
            .ok();

            if let Some(reply) = reply_rx.recv().await {
                println!("{}", reply);
            }
        }
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Agent loop
// ---------------------------------------------------------------------------

async fn agent_loop(
    provider: Arc<dyn Provider>,
    mut rx: mpsc::Receiver<InboundMessage>,
    system_prompt: String,
    max_history: usize,
) {
    let mut history: Vec<Message> = vec![Message {
        role: "system".into(),
        content: system_prompt,
    }];

    while let Some(msg) = rx.recv().await {
        info!(user = %msg.user_id, text = %msg.text, "Received message");

        history.push(Message {
            role: "user".into(),
            content: msg.text.clone(),
        });

        // Trim history to stay within bounds (keep system prompt).
        while history.len() > max_history + 1 {
            history.remove(1);
        }

        match provider.chat(&history).await {
            Ok(reply) => {
                history.push(Message {
                    role: "assistant".into(),
                    content: reply.clone(),
                });
                if msg.reply_tx.send(reply).await.is_err() {
                    warn!("Reply channel closed before response could be sent");
                }
            }
            Err(e) => {
                error!(error = %e, "Provider error");
                let _ = msg
                    .reply_tx
                    .send(format!("[error] {}", e))
                    .await;
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Entrypoint
// ---------------------------------------------------------------------------

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt::init();

    let config = Config::from_env()?;
    info!(model = %config.provider_model, "Starting {{PROJECT_NAME}}");

    let provider: Arc<dyn Provider> = Arc::new(HttpProvider::new(&config));
    let channel: Box<dyn Channel> = Box::new(StdinChannel);

    let system_prompt = "{{SYSTEM_PROMPT}}".to_string();

    let (tx, rx) = mpsc::channel::<InboundMessage>(32);

    let agent_handle = tokio::spawn(agent_loop(
        provider.clone(),
        rx,
        system_prompt,
        config.max_history,
    ));

    let channel_handle = tokio::spawn(async move {
        if let Err(e) = channel.listen(tx).await {
            error!(error = %e, "Channel error");
        }
    });

    tokio::select! {
        _ = agent_handle => info!("Agent loop ended"),
        _ = channel_handle => info!("Channel listener ended"),
    }

    Ok(())
}
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{PROJECT_NAME}}` | Crate / binary name (e.g. `my-agent`) |
| `{{PROJECT_DESCRIPTION}}` | One-line description for the module doc comment |
| `{{PROVIDER_API_KEY_ENV}}` | Environment variable name for the LLM API key (e.g. `OPENAI_API_KEY`) |
| `{{PROVIDER_MODEL_ENV}}` | Environment variable name for the model identifier (e.g. `OPENAI_MODEL`) |
| `{{DEFAULT_MODEL}}` | Default model string when the env var is unset (e.g. `gpt-4o`) |
| `{{PROVIDER_BASE_URL_ENV}}` | Environment variable name for the provider base URL |
| `{{DEFAULT_PROVIDER_URL}}` | Default provider API base URL (e.g. `https://api.openai.com/v1`) |
| `{{CHANNEL_ADDRESS_ENV}}` | Environment variable name for the channel bind address |
| `{{DEFAULT_CHANNEL_ADDRESS}}` | Default channel address (e.g. `127.0.0.1:8080`) |
| `{{SYSTEM_PROMPT}}` | System prompt injected as the first message in the conversation history |
