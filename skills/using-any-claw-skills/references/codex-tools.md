# Codex Tool Mapping

When any-claw-skills reference Claude Code tools, use these Codex equivalents:

| Claude Code Tool | Codex Equivalent |
|------------------|------------------|
| `Read` | `read_file` |
| `Write` | `write_file` |
| `Edit` | `patch` |
| `Bash` | `shell` |
| `Glob` | `shell` with `find` |
| `Grep` | `shell` with `grep` |
| `TodoWrite` | `todowrite` |
| `TaskCreate` / `TaskUpdate` | `todowrite` |
| `Skill` | Load skill manually via `read_file` on SKILL.md |
| `Agent` | Not available — execute inline |
| `AskUserQuestion` | Direct text question to user |
