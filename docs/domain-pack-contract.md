# Domain Pack Contract

Every vertical domain pack in `any-claw-skills` should follow the same contract so the builder and extension skills can treat domains consistently.

The point of a domain pack is to make the resulting assistant feel **professional and out-of-the-box specialized**, not merely to add example code.

## Required Files

Each domain directory under `templates/domains/<domain>/` must include:

- `system-prompt.md`
- `knowledge.md`
- `tools.<stack>.md` for every supported stack in scope

## Optional Files

A domain may also include:

- `mcp-server.python.md`
- `mcp-server.typescript.md`
- `routines.md`
- `ingestion.md`
- `policy.md`

MCP support is optional at the repository level, but if it exists, the domain docs must explain when it should be offered.

## Required Content

### `system-prompt.md`

Must define:

- assistant role in that domain
- core capabilities
- tone or behavioral guardrails
- domain-specific caution or escalation language

### `knowledge.md`

Must define:

- domain vocabulary
- important workflows or heuristics
- constraints that influence tool or prompt behavior
- references or assumptions that maintainers should keep current

### `tools.<stack>.md`

Must define:

- exported tools or functions
- input and output shape
- likely environment variables
- error cases and fallback behavior
- integration assumptions for the scaffolded project

## Out-of-the-Box Requirement

Every domain pack should feel useful on day one. That means the selected domain should contribute:

- ready-to-use functions or tools
- a domain-specific system prompt
- domain-specific knowledge and language
- optional MCP server where it materially improves the assistant
- optional routines or recurring workflows when the domain naturally needs them
- optional ingestion guidance for documents, exports, or media
- environment/config guidance
- professional caution, escalation, or boundary language where needed

### `mcp-server.<stack>.md`

If present, it should define:

- exposed MCP operations
- mapping from tool-level capabilities to server endpoints or actions
- configuration expectations
- when the builder should recommend MCP for that domain

### `routines.md`

If present, it should define:

- scheduled or event-driven routines that make the domain useful
- required channels or triggers
- expected outputs, summaries, or notifications
- whether the routines are safe to enable by default

### `ingestion.md`

If present, it should define:

- inbound artifacts such as files, docs, exports, voice notes, or media
- how those artifacts should be parsed or indexed
- whether the domain expects import flows on day one or only later
- any privacy or retention concerns tied to ingestion

### `policy.md`

If present, it should define:

- access-control or approval requirements
- escalation thresholds
- risky actions that require extra confirmation
- domain-specific constraints that should affect tools, routines, or MCP

## Required Metadata

Each domain should be documentable with:

- domain purpose
- default use cases
- env vars required by tools or MCP
- external accounts, inbound artifacts, or import sources
- routine or automation hooks if relevant
- preferred channels or operator surfaces if relevant
- safety notes
- support tier

## Safety Notes

Every domain must state whether it is:

- low-risk general productivity support
- medium-risk operational support
- higher-risk advisory support

For higher-risk domains such as `Health` or `Finance`, the pack must include user-facing caution language and should remain below GA until verification depth is stronger.

## Support Tier Criteria

### GA

A domain can be GA when it has:

- complete prompt, knowledge, and primary-stack tool coverage
- clear environment variable documentation
- integration guidance for the golden path
- repeatable verification and example coverage
- no major safety-documentation gaps

### Beta

A domain can be Beta when it has:

- usable templates
- documented assumptions
- at least one extension or validation path
- known gaps that are stated openly

### Preview

A domain remains Preview when it is:

- template-only
- lightly validated
- missing example or release verification evidence

## Current Recommendation

- `Productivity`: target GA domain
- `Health`, `Finance`: Beta domains
- `Education`, `Social`, `Smart Home`: Preview domains unless stronger evidence is added
