---
name: add-provider
description: "Use when the user wants to add an LLM provider to an existing assistant project. Triggers on: 'add provider', 'add openai', 'add anthropic', 'add ollama', 'switch model', '/add-provider'"
---

# Add Provider

Add a provider to an existing assistant project, preferably one generated from the `any-claw-skills` project contract.

## Support-Tier Rule

Before recommending a provider, tell the user whether it is:

- `GA` - `OpenAI`
- `Beta` - `Anthropic`, `Ollama`

## Checklist

1. **Inspect the current project contract** — detect stack, existing providers, and any provider router
2. **Read compatibility guidance** — use `provider-matrix.md`
3. **Filter provider choices** — only show providers not already present
4. **Explain support tier** — call out GA or Beta before the user chooses
5. **Generate provider code from templates** — read `templates/providers/{{provider}}.{{stack}}.md`
6. **Generate or update router** — only when multiple providers are present and the stack supports it cleanly
7. **Integrate and verify** — registry, config, `.env.example`, README, imports

## Project Inspection

Look for:

- `providers/` directory
- existing provider registry or index
- current environment variable conventions

If the project does not resemble the generated project contract, state the mismatch first.
