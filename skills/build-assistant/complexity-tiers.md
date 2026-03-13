# Complexity Tiers

## Release Note

For v0.1.0, `Standard` is the only `GA` tier. The other tiers remain valuable, but they are `Preview` until deeper verification exists.

## Tier Matrix

| Tier | Support | Target LOC | Stack | Best For |
|------|---------|------------|-------|----------|
| Pico | Preview | <500 | Go | Experiments and minimal demos |
| Nano | Preview | <2K | TypeScript | Side projects and lightweight assistants |
| Standard | GA | 2-10K | Python | Daily-use personal assistants |
| Full | Preview | 10-30K | TypeScript | Multi-channel or team-oriented assistants |
| Enterprise | Preview | 30K+ | Rust | Advanced organizational deployments |

## Recommendation

If the user does not have a strong preference, recommend:

- `Standard`
- because it is the golden path tier
- because it aligns with the best-supported templates, docs, and examples

## Reference Projects

| Tier | Reference | Repository | Why It Matters |
|------|-----------|------------|----------------|
| Pico | PicoClaw | `picoclaw/` | Minimal single-binary mindset |
| Nano | NanoClaw | `nanoclaw/` | Lightweight modular TypeScript |
| Standard | CoPaw | `CoPaw/` | Full Python assistant structure |
| Full | OpenClaw | `openclaw/` | Broader TypeScript system design |
| Enterprise | IronClaw | `ironclaw/` | Advanced Rust architecture reference |
