---
name: build-assistant
description: "Use when the user wants to build, create, or scaffold a new personal AI assistant project. Triggers on: 'build assistant', 'create assistant', 'scaffold', 'build chatbot', 'personal AI', '/build-assistant'"
---

# Build Assistant Wizard

Interactive wizard for reproducing a **personal assistant product** from this repository's templates and reference architectures.

This is a **Claude Code first** flow. For v0.1.0, the primary supported path is:

- `Standard`
- `Python`
- `OpenAI`
- `CLI + Telegram`
- `Productivity`
- `.env.example + Docker + MCP server`

<HARD-GATE>
Do NOT generate files until the user has explicitly approved the final configuration summary. Follow the steps in order and ask one question per message.
</HARD-GATE>

## What This Skill Really Does

Treat this skill as an **assistant product composer**.

You are not merely picking files. You are helping Claude Code reproduce an assistant that can feel:

- PicoClaw-small
- NanoClaw-customizable
- CoPaw-extensible
- OpenClaw-like as a multi-channel product
- IronClaw-like in security and hardening

Read `docs/assistant-product-composition-model.md` before composing larger or more specialized builds.

## Support-Tier Rule

Always tell the user whether a choice is:

- `GA` - preferred and release-verified
- `Beta` - available but validated less deeply
- `Preview` - available mainly as a reference or starter

If the user does not care, steer them toward the GA golden path.

## Checklist

1. **Inspect the current directory** — detect whether it is empty, contains an unrelated project, or contains an existing assistant scaffold
2. **Decide whether this is a new build or an extension** — if it is already a generated assistant, recommend `add-channel`, `add-domain`, `add-provider`, or `add-tool`
3. **Understand the target assistant product** — determine whether the user wants a tiny helper, lightweight custom assistant, standard extensible project, full multi-channel product, or hardened platform
4. **Choose project name** — suggest a default from the directory name
5. **Choose complexity tier / reference mode** — read `complexity-tiers.md`; map the requested size to PicoClaw, NanoClaw, CoPaw, OpenClaw, or IronClaw style
6. **Choose stack** — read `stack-selection.md`; respect tier constraints and explain support level
7. **Choose provider(s)** — recommend `OpenAI` first, explain Beta alternatives
8. **Choose channel(s)** — recommend `CLI + Telegram`, explain Beta or Preview channels
9. **Choose domain pack(s)** — recommend `Productivity`, explain Beta or Preview domains
10. **Choose product capabilities** — memory, automation, MCP server, Docker, CI, observability, and security expectations
11. **Confirm the full product composition** — include reference mode and support-tier notes for any non-GA choices
12. **Generate scaffold files** — read templates from `templates/scaffolds/`
13. **Generate providers, channels, and domain packs** — read templates from `templates/providers/`, `templates/channels/`, and `templates/domains/`
14. **Integrate the generated pieces** — follow `project-structure.md` and `config-templates.md`, then hand off with next-step expansion commands

## Step Guidance

### Step 1: Inspect the Current Directory

Check:

- project markers such as `pyproject.toml`, `package.json`, `go.mod`, `Cargo.toml`
- assistant-specific directories such as `src/<package>/providers`, `src/<package>/channels`, `src/<package>/tools`
- any existing `README`, `CLAUDE.md`, or config files

Report whether the directory is:

- empty and ready for a new build
- an existing assistant scaffold that should be extended
- an unrelated project where generation should be done carefully

### Step 2: New Build vs Extension

If the directory already looks like an `any-claw-skills`-generated assistant or a close variant:

- stop the rebuild flow
- explain that extension skills are a better fit
- route to `add-channel`, `add-domain`, `add-provider`, or `add-tool`

### Step 3: Target Assistant Product

Before asking about raw implementation choices, understand what kind of assistant the user wants to vibe code:

- tiny, low-resource helper
- small but highly customizable personal assistant
- standard extensible assistant with MCP and domain tooling
- multi-channel always-on assistant product
- security-hardened personal assistant platform

This determines which reference mode is appropriate.

### Step 5: Tier Selection

Read `skills/build-assistant/complexity-tiers.md`.

Recommendations:

- `Standard` is the `GA` tier and should be recommended first
- `Pico`, `Nano`, `Full`, and `Enterprise` are `Preview` in v0.1.0

Reference mapping:

- `Pico` -> PicoClaw-style ultra-small assistant
- `Nano` -> NanoClaw-style customizable assistant
- `Standard` -> CoPaw-style extensible assistant
- `Full` -> OpenClaw-style multi-channel assistant product
- `Enterprise` -> IronClaw-style hardened assistant platform

### Step 6: Stack Selection

Read `skills/build-assistant/stack-selection.md`.

Tier constraints still apply:

- `Pico` -> `Go`
- `Nano` -> `TypeScript`
- `Standard` -> `Python`
- `Full` -> `TypeScript`
- `Enterprise` -> `Rust`

Only `Standard -> Python` is `GA`.

### Step 7: Provider Selection

Support guidance:

- `OpenAI` -> `GA`
- `Anthropic` -> `Beta`
- `Ollama` -> `Beta`

If the user chooses multiple providers, generate the router only if the selected tier and stack support it cleanly.

### Step 8: Channel Selection

Support guidance:

- `CLI` -> `GA`
- `Telegram` -> `GA`
- `Discord`, `Slack` -> `Beta`
- `WhatsApp`, `DingTalk`, `Feishu`, `Web UI` -> `Preview`

If the user does not care, prefer `CLI + Telegram`.

### Step 9: Domain Selection

Support guidance:

- `Productivity` -> `GA`
- `Health`, `Finance` -> `Beta`
- `Education`, `Social`, `Smart Home` -> `Preview`
- `None` -> valid, but outside the main v0.1.0 story

If the user does not care, prefer `Productivity`.

When a domain is selected, treat it as an **out-of-the-box domain pack**, not just a label. The generated result should include:

- ready-to-use functions/tools
- domain-specific system prompt
- domain knowledge
- optional MCP server
- required env vars
- domain-specific safety or escalation behavior

### Step 10: Product Capabilities

Ask about product-level capabilities, not just file toggles:

- memory or persistence
- automation / scheduling
- Docker
- MCP server
- observability
- security or hardening expectations

Keep the chosen tier honest. Do not force advanced capabilities into a tiny build just because they exist.

### Step 11: Confirmation

Present a summary like this:

```text
Project: {{name}}
Reference mode: {{reference_mode}}
Tier: {{tier}} ({{tier_support}})
Stack: {{stack}} ({{stack_support}})
Providers: {{providers}}
Channels: {{channels}}
Domain packs: {{domains}}
Capabilities: {{capabilities}}
```

Ask for explicit approval before generating.

### Step 12-14: Generation

Generation is template-driven:

1. Read the selected scaffold under `templates/scaffolds/{{tier}}-tier/{{stack}}/`
2. Read selected channel templates under `templates/channels/`
3. Read selected provider templates under `templates/providers/`
4. Read selected domain templates under `templates/domains/{{domain}}/`
5. Use `skills/build-assistant/project-structure.md` and `skills/build-assistant/config-templates.md` to integrate everything cleanly

Do not improvise a new scaffold format if a template exists.

The generated project should feel like a coherent personal assistant product in the chosen size class, not a pile of unrelated adapters.

### Review and Handoff

Summarize:

- what was generated
- which reference project mode it resembles
- which choices were `GA`, `Beta`, or `Preview`
- what environment variables need to be filled
- how to run the result
- which extension commands are now available

## Key Principles

- one question per message
- compose an assistant product, not just a file tree
- map tiers to real reference project shapes
- recommend the golden path by default
- keep support-tier language explicit
- prefer extension skills over rebuilding existing assistant projects
- keep generation template-driven
