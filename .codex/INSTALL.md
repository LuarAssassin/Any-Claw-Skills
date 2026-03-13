# Installing any-claw-skills for Codex

Enable any-claw-skills in Codex via native skill discovery.

## Prerequisites

- Git

## Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/any-claw/any-claw-skills.git ~/.codex/any-claw-skills
   ```

2. **Create the skills symlink:**
   ```bash
   mkdir -p ~/.agents/skills
   ln -s ~/.codex/any-claw-skills/skills ~/.agents/skills/any-claw-skills
   ```

   **Windows (PowerShell):**
   ```powershell
   New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.agents\skills"
   cmd /c mklink /J "$env:USERPROFILE\.agents\skills\any-claw-skills" "$env:USERPROFILE\.codex\any-claw-skills\skills"
   ```

3. **Restart Codex** to discover the skills.

## Verify

```bash
ls -la ~/.agents/skills/any-claw-skills
```

You should see a symlink pointing to your any-claw-skills skills directory.

## Updating

```bash
cd ~/.codex/any-claw-skills && git pull
```

Skills update instantly through the symlink.

## Uninstalling

```bash
rm ~/.agents/skills/any-claw-skills
```

Optionally delete the clone: `rm -rf ~/.codex/any-claw-skills`.
