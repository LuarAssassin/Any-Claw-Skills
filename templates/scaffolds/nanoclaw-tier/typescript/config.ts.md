# config.ts.md

Template for the Nano/TypeScript tier scaffold.

## Generated File: `src/config.ts`

```typescript
import { config as dotenvConfig } from "dotenv";

// ---------------------------------------------------------------------------
// Load .env
// ---------------------------------------------------------------------------

dotenvConfig();

// ---------------------------------------------------------------------------
// Provider configuration
// ---------------------------------------------------------------------------

export type ProviderType = "{{PROVIDER_TYPE_A}}" | "{{PROVIDER_TYPE_B}}";

export interface ProviderConfig {
  type: ProviderType;
  apiKey: string;
  model: string;
  maxTokens: number;
  temperature: number;
  baseUrl?: string;
}

// ---------------------------------------------------------------------------
// Channel configuration
// ---------------------------------------------------------------------------

export type ChannelType = "{{CHANNEL_TYPE_A}}" | "{{CHANNEL_TYPE_B}}";

export interface ChannelConfig {
  type: ChannelType;
  port: number;
  webhookPath: string;
  secret?: string;
}

// ---------------------------------------------------------------------------
// Top-level app configuration
// ---------------------------------------------------------------------------

export interface AppConfig {
  projectName: string;
  systemPrompt: string;
  provider: ProviderConfig;
  channel: ChannelConfig;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function requireEnv(key: string): string {
  const value = process.env[key];
  if (!value) {
    throw new Error(`Missing required environment variable: ${key}`);
  }
  return value;
}

function optionalEnv(key: string, fallback: string): string {
  return process.env[key] ?? fallback;
}

function intEnv(key: string, fallback: number): number {
  const raw = process.env[key];
  if (!raw) return fallback;
  const parsed = parseInt(raw, 10);
  if (Number.isNaN(parsed)) {
    throw new Error(`Environment variable ${key} must be an integer, got: ${raw}`);
  }
  return parsed;
}

function floatEnv(key: string, fallback: number): number {
  const raw = process.env[key];
  if (!raw) return fallback;
  const parsed = parseFloat(raw);
  if (Number.isNaN(parsed)) {
    throw new Error(`Environment variable ${key} must be a number, got: ${raw}`);
  }
  return parsed;
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

function validateProviderType(value: string): ProviderType {
  const allowed: ProviderType[] = ["{{PROVIDER_TYPE_A}}", "{{PROVIDER_TYPE_B}}"];
  if (!allowed.includes(value as ProviderType)) {
    throw new Error(
      `Invalid PROVIDER_TYPE "${value}". Allowed: ${allowed.join(", ")}`,
    );
  }
  return value as ProviderType;
}

function validateChannelType(value: string): ChannelType {
  const allowed: ChannelType[] = ["{{CHANNEL_TYPE_A}}", "{{CHANNEL_TYPE_B}}"];
  if (!allowed.includes(value as ChannelType)) {
    throw new Error(
      `Invalid CHANNEL_TYPE "${value}". Allowed: ${allowed.join(", ")}`,
    );
  }
  return value as ChannelType;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export function loadConfig(): AppConfig {
  const providerType = validateProviderType(
    optionalEnv("PROVIDER_TYPE", "{{PROVIDER_TYPE_A}}"),
  );

  const channelType = validateChannelType(
    optionalEnv("CHANNEL_TYPE", "{{CHANNEL_TYPE_A}}"),
  );

  return {
    projectName: optionalEnv("PROJECT_NAME", "{{PROJECT_NAME}}"),

    systemPrompt: optionalEnv(
      "SYSTEM_PROMPT",
      "{{DEFAULT_SYSTEM_PROMPT}}",
    ),

    provider: {
      type: providerType,
      apiKey: requireEnv("{{PROVIDER_API_KEY_ENV}}"),
      model: optionalEnv("PROVIDER_MODEL", "{{DEFAULT_MODEL}}"),
      maxTokens: intEnv("PROVIDER_MAX_TOKENS", {{DEFAULT_MAX_TOKENS}}),
      temperature: floatEnv("PROVIDER_TEMPERATURE", {{DEFAULT_TEMPERATURE}}),
      baseUrl: process.env["PROVIDER_BASE_URL"],
    },

    channel: {
      type: channelType,
      port: intEnv("PORT", {{DEFAULT_PORT}}),
      webhookPath: optionalEnv("WEBHOOK_PATH", "{{DEFAULT_WEBHOOK_PATH}}"),
      secret: process.env["CHANNEL_SECRET"],
    },
  };
}
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{PROVIDER_TYPE_A}}` | Primary provider identifier (e.g. `"openai"`, `"anthropic"`) |
| `{{PROVIDER_TYPE_B}}` | Secondary/fallback provider identifier |
| `{{CHANNEL_TYPE_A}}` | Primary channel identifier (e.g. `"webhook"`, `"discord"`) |
| `{{CHANNEL_TYPE_B}}` | Secondary channel identifier |
| `{{PROJECT_NAME}}` | Default project display name |
| `{{DEFAULT_SYSTEM_PROMPT}}` | Default system prompt string for the LLM |
| `{{PROVIDER_API_KEY_ENV}}` | Name of the env var holding the provider API key (e.g. `OPENAI_API_KEY`) |
| `{{DEFAULT_MODEL}}` | Default model identifier (e.g. `"gpt-4o"`, `"claude-sonnet-4-20250514"`) |
| `{{DEFAULT_MAX_TOKENS}}` | Default max tokens as an integer literal (e.g. `1024`) |
| `{{DEFAULT_TEMPERATURE}}` | Default temperature as a float literal (e.g. `0.7`) |
| `{{DEFAULT_PORT}}` | Default HTTP port as an integer literal (e.g. `3000`) |
| `{{DEFAULT_WEBHOOK_PATH}}` | Default webhook endpoint path (e.g. `/webhook`) |
