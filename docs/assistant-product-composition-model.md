# Assistant Product Composition Model

`any-claw-skills` is not just a template pack. Its job is to help Claude Code reproduce a **personal assistant product** with the right size, architecture, channels, domain packs, and runtime capabilities for a specific user.

This model is derived from the reference projects in this repository:

- `picoclaw/`
- `nanoclaw/`
- `CoPaw/`
- `openclaw/`
- `ironclaw/`

## Core Idea

The builder should behave like an **assistant product composer**:

1. choose a target product shape
2. choose the user's vertical domain
3. choose channels, models, and runtime features
4. compose a scaffold and domain packs that feel like one coherent assistant product

The goal is not "generate some code." The goal is:

- vibe code a working assistant quickly
- keep it professional and domain-specific
- allow it to stay small like PicoClaw or grow into a larger system like OpenClaw
- keep the generated project iterative and maintainable

## Reference Product Modes

### PicoClaw Mode

Reference: `picoclaw/`

Use when the user wants:

- a very small assistant
- low-resource deployment
- single-binary or near-single-binary simplicity
- just enough channels and tools to be useful

Product shape:

- one process
- minimal dependencies
- direct provider + channel wiring
- small tool surface
- domain pack trimmed to essentials

### NanoClaw Mode

Reference: `nanoclaw/`

Use when the user wants:

- a lightweight but understandable codebase
- strong customization through Claude Code
- isolated execution or secure group/task separation
- "small enough to understand, large enough to customize"

Product shape:

- compact modular project
- customization through skills and code changes
- channels added incrementally
- project remains forkable and hackable

### CoPaw Mode

Reference: `CoPaw/`

Use when the user wants:

- a standard, extensible assistant project
- richer toolkits and service structure
- MCP support
- more formal plugin, prompt, and config organization

Product shape:

- standard Python project layout
- clear provider and channel abstractions
- domain packs as first-class modules
- stronger configuration, tooling, and integration surfaces

### OpenClaw Mode

Reference: `openclaw/`

Use when the user wants:

- a full personal assistant product
- multiple communication apps
- routing and control plane concepts
- richer automation, presence, and session behavior

Product shape:

- multi-channel control plane
- richer session and routing model
- stronger automation and client surfaces
- assistant feels always-on, not just request/response

### IronClaw Mode

Reference: `ironclaw/`

Use when the user wants:

- strong security and sandboxing
- dynamic tools or plugin-like expansion
- more serious routines, policies, and persistence
- hardened personal-assistant infrastructure

Product shape:

- security boundaries are explicit
- tools and integrations are policy-aware
- memory, routines, and MCP are treated as long-lived product features

## Composition Axes

The builder should compose an assistant across these axes.

### 1. Product Size

- ultra-small
- lightweight modular
- standard extensible
- full multi-channel
- hardened / advanced

### 2. Domain Pack

Each chosen vertical domain should contribute out-of-the-box assets:

- functions/tools
- system prompt
- domain knowledge
- optional MCP server
- required environment variables
- domain safety and escalation rules

This is the main vertical differentiation of `any-claw-skills`.

### 3. Channel Surface

The user can select one or more communication surfaces:

- CLI
- Telegram
- Discord
- Slack
- WhatsApp
- DingTalk
- Feishu
- Web UI

The generated project should feel native to the selected surface, not bolted on afterward.

### 4. Model Topology

The user can choose:

- a single primary provider
- multiple providers with routing or fallback
- local/private inference options

### 5. Product Capabilities

Beyond channels and providers, the builder should treat these as composable product capabilities:

- memory
- automation / scheduling
- browser or web access
- observability
- security guards
- MCP connectivity
- domain-specific routines

## Domain Packs Are Not Optional Flavor

The domain pack is the key product feature.

When a user chooses a vertical like health, finance, productivity, or education, Claude Code should not just add a folder. It should install a ready-to-use domain slice:

- domain-specific tools
- domain-specific prompts
- domain-specific MCP surface where useful
- domain-specific env/config
- domain-specific professional behavior

That is what makes the assistant feel specialized instead of generic.

## Growth Path

The generated assistant should be able to grow along a path like this:

`PicoClaw-style minimal helper -> NanoClaw-style customizable assistant -> CoPaw-style extensible product -> OpenClaw-style full assistant -> IronClaw-style hardened platform`

The repository should therefore keep a stable conceptual contract across tiers:

- assistant core
- providers
- channels
- domain packs
- configuration
- extension points

## What the Builder Should Actually Do

`build-assistant` should help Claude Code make decisions in this order:

1. What kind of assistant product is the user trying to create?
2. Which reference mode is closest?
3. Which domain packs make it useful on day one?
4. Which channels and models does the user need immediately?
5. Which capabilities are required now, and which should be left for later extension?

Then it should compose a scaffold that matches that answer.

## Repository Consequence

This means `any-claw-skills` should be treated as:

- a Claude Code workflow
- a reference-architecture mapper
- a domain-pack platform
- a project-composition system

not merely a collection of templates.
