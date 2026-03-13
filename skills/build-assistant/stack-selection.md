# Stack Selection

## Release Note

For v0.1.0, only `Python` in the `Standard` tier is `GA`. Other stacks remain available as `Preview`.

## Compatibility Matrix

| Stack | Tier | Support | Why It Exists |
|-------|------|---------|---------------|
| Go | Pico | Preview | Minimal deployment and low-dependency experiments |
| TypeScript | Nano | Preview | Fast iteration for smaller assistants |
| Python | Standard | GA | Best-supported assistant builder path |
| TypeScript | Full | Preview | Advanced multi-package systems |
| Rust | Enterprise | Preview | High-performance reference architecture |

## Recommendation

Prefer `Python` when the user wants:

- the most complete docs
- the strongest golden path coverage
- the best fit for domain tools and MCP surfaces

## Stack Profiles

### Python (`GA`)

- strongest support for the v0.1.0 golden path
- best fit for domain packs and MCP examples
- best fit for the repository's release examples

### Go (`Preview`)

- good for minimal assistants
- intentionally lean and low-ceremony
- not part of the main release story

### TypeScript (`Preview`)

- useful for lightweight or larger assistant shapes
- strong ecosystem, but outside the primary release path

### Rust (`Preview`)

- useful as an architecture reference
- not deep enough for GA claims in v0.1.0
