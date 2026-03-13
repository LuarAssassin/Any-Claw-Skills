# Channel Compatibility Matrix

## Support Levels

| Channel | Support | Notes |
|---------|---------|-------|
| CLI | GA | Lowest-friction validation path |
| Telegram | GA | Main real-world messaging path |
| Discord | Beta | Supported, but outside the golden path |
| Slack | Beta | Supported, but outside the golden path |
| WhatsApp | Preview | Template available, low verification depth |
| DingTalk | Preview | Template available, low verification depth |
| Feishu | Preview | Template available, low verification depth |
| Web UI | Preview | Template available, low verification depth |

## Stack Availability

| Channel | Python | TypeScript | Go |
|---------|--------|------------|----|
| CLI | Yes | Yes | Yes |
| Telegram | Yes | Yes | Yes |
| Discord | Yes | Yes | Yes |
| Slack | Yes | Yes | Yes |
| WhatsApp | Yes | Yes | Yes |
| DingTalk | Yes | Yes | Yes |
| Feishu | Yes | Yes | Yes |
| Web UI | No | Yes | No |

## Extension Rule

When extending a generated project:

1. prefer channels that match the current support tier expectations
2. explain any downgrade in support level before generation
3. update `.env.example`, channel registry, and README together
