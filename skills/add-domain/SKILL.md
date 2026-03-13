---
name: add-domain
description: "Use when the user wants to add a vertical domain (tools, MCP server, system prompt) to an existing assistant project. Triggers on: 'add domain', 'add health tools', 'add productivity', '/add-domain'"
---

# Add Domain

Add a vertical domain pack to an existing assistant project, preferably one generated from the `any-claw-skills` project contract.

## Support-Tier Rule

Before recommending a domain, tell the user whether it is:

- `GA` - `Productivity`
- `Beta` - `Health`, `Finance`
- `Preview` - `Education`, `Social`, `Smart Home`

## Checklist

1. **Inspect the current project contract** — detect stack, existing domains, system prompt location, and tool registry shape
2. **Read domain guidance** — use `domain-catalog.md` and `docs/domain-pack-contract.md`
3. **Filter domain choices** — only show domains not already present
4. **Explain support tier and safety posture** — especially for higher-risk domains
5. **Ask about MCP** — offer it when the chosen stack and domain support it
6. **Generate tools, prompt, knowledge, and optional MCP** — from `templates/domains/{{domain}}/`
7. **Integrate into the generated project** — tool registry, prompt composition, `.env.example`, README
8. **Verify** — imports, registration, config updates, and prompt integration

## Project Inspection

Inspect:

- existing `tools/` structure
- any domain directories already present
- system prompt composition or prompt registry
- whether the project has room for an MCP surface

If the target project does not match the generated project contract, say so before applying changes.
