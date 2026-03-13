# Installing any-claw-skills for OpenCode

## Prerequisites

- [OpenCode.ai](https://opencode.ai) installed
- Git installed

## Installation Steps

### 1. Clone the repository

```bash
git clone https://github.com/any-claw/any-claw-skills.git ~/.config/opencode/any-claw-skills
```

### 2. Register the Plugin

```bash
mkdir -p ~/.config/opencode/plugins
rm -f ~/.config/opencode/plugins/any-claw-skills.js
ln -s ~/.config/opencode/any-claw-skills/.opencode/plugins/any-claw-skills.js ~/.config/opencode/plugins/any-claw-skills.js
```

### 3. Symlink Skills

```bash
mkdir -p ~/.config/opencode/skills
rm -rf ~/.config/opencode/skills/any-claw-skills
ln -s ~/.config/opencode/any-claw-skills/skills ~/.config/opencode/skills/any-claw-skills
```

### 4. Restart OpenCode

Restart OpenCode. The plugin will automatically inject context.

Verify by asking: "I want to build a personal assistant"

## Usage

### Finding Skills

Use OpenCode's native `skill` tool:

```
use skill tool to list skills
```

### Loading a Skill

```
use skill tool to load any-claw-skills/build-assistant
```

## Updating

```bash
cd ~/.config/opencode/any-claw-skills && git pull
```

## Troubleshooting

### Plugin not loading

1. Check plugin symlink: `ls -l ~/.config/opencode/plugins/any-claw-skills.js`
2. Check source exists: `ls ~/.config/opencode/any-claw-skills/.opencode/plugins/any-claw-skills.js`

### Tool mapping

When skills reference Claude Code tools:
- `TodoWrite` -> `todowrite`
- `Task` with subagents -> `@mention` syntax
- `Skill` tool -> OpenCode's native `skill` tool
- File operations -> your native tools

## Getting Help

- Report issues: https://github.com/any-claw/any-claw-skills/issues
