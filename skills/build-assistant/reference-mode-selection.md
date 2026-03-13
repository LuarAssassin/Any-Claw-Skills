# Reference Mode Selection

Use this guide before asking the user for low-level implementation choices.

The first question is not "Python or TypeScript?" The first question is:

**What kind of personal assistant product are we reproducing?**

## Reference Modes

### PicoClaw Mode

Choose this when the user wants:

- the smallest useful assistant possible
- low-resource deployment
- minimal files and dependencies
- one main provider and one main channel

Typical shape:

- Go
- CLI or Telegram
- one or zero domain packs
- no heavy runtime extras

### NanoClaw Mode

Choose this when the user wants:

- a small but highly customizable codebase
- easy Claude Code iteration
- a fork-friendly assistant they can keep changing
- lightweight channel expansion over time

Typical shape:

- TypeScript
- one or two channels
- lean modular structure
- selective domain packs

### CoPaw Mode

Choose this when the user wants:

- a standard extensible assistant project
- clearer provider/channel/tool abstractions
- richer domain tooling
- MCP-ready structure

Typical shape:

- Python
- multiple modules
- domain packs are first-class
- stronger config and integration surfaces

### OpenClaw Mode

Choose this when the user wants:

- a true personal assistant product
- many channels or a richer control-plane model
- more automation, routing, and session behavior
- an "always on" assistant feeling

Typical shape:

- TypeScript
- multi-channel routing
- more product surfaces than a simple bot

### IronClaw Mode

Choose this when the user wants:

- stronger security boundaries
- sandboxing or policy-aware execution
- more serious persistence, routines, or tool boundaries
- a hardened long-term assistant platform

Typical shape:

- Rust
- security-first runtime model
- stronger platform-level constraints

## Capability Bundles

After the user chooses a reference mode, frame the next questions in bundles:

- `Communication`: which channels must work on day one?
- `Reasoning`: which model providers are needed?
- `Domain`: which vertical pack makes the assistant immediately useful?
- `Operations`: does the user need memory, scheduling, observability, Docker, or MCP now?
- `Growth`: should the output stay tiny, or be ready to grow into a larger assistant product?

## Rule

Always bias the build toward the smallest product shape that still solves the user's actual problem. The user can grow later with `add-channel`, `add-domain`, `add-provider`, and `add-tool`.
