# Gemini CLI Tool Mapping

When any-claw-skills reference Claude Code tools, use these Gemini equivalents:

| Claude Code Tool | Gemini Equivalent |
|------------------|-------------------|
| `Read` | `read_file` |
| `Write` | `write_file` |
| `Edit` | `edit_file` |
| `Bash` | `run_shell_command` |
| `Glob` | `list_directory` or `run_shell_command` with `find` |
| `Grep` | `run_shell_command` with `grep` |
| `TodoWrite` | Track in conversation (no equivalent) |
| `TaskCreate` / `TaskUpdate` | Track in conversation |
| `Skill` | `activate_skill` |
| `Agent` | Not available — execute inline |
| `AskUserQuestion` | Direct text question to user |
