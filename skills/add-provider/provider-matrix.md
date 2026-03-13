# Provider Matrix

## Support Levels

| Provider | Support | Notes |
|----------|---------|-------|
| OpenAI | GA | Primary provider for the golden path |
| Anthropic | Beta | Supported alternative for reasoning-heavy flows |
| Ollama | Beta | Local/private option with lower release coverage |

## Provider Comparison

| Provider | Type | Tool Use | Streaming | Local |
|----------|------|----------|-----------|-------|
| OpenAI | Cloud | Yes | Yes | No |
| Anthropic | Cloud | Yes | Yes | No |
| Ollama | Local | Limited | Yes | Yes |

## Extension Rule

When extending a generated project:

1. inspect existing provider wiring first
2. explain support tier before adding a new provider
3. only add a provider router when the resulting project shape stays coherent
