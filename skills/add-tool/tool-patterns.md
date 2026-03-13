# Tool Implementation Patterns

Choose a tool pattern that fits the current generated project contract.

## Project Contract Rule

Before choosing a pattern, inspect:

- registry format
- naming conventions
- async vs sync style
- domain-scoped vs flat tool layout
- existing test style

## Patterns

### Pure Computation

Use when the tool transforms inputs without side effects.

### API Integration

Use when the tool calls an external service and needs env vars, retries, and error handling.

### File Operation

Use when the tool reads or writes local project data.

### Database Query

Use when the project already has persistence and the tool should use the existing storage layer.

### Composite Tool

Use when the tool orchestrates multiple project-native operations.

## Verification Rule

Every new tool should include:

- one valid-input test
- one edge or failure-path test
- registry wiring that matches the existing project
