#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "=== Install Smoke Checks ==="
echo ""

test -f "${ROOT}/.claude-plugin/plugin.json"
test -f "${ROOT}/.claude-plugin/marketplace.json"
test -f "${ROOT}/README.md"
test -f "${ROOT}/.codex/INSTALL.md"
test -f "${ROOT}/.opencode/INSTALL.md"

echo "Metadata and install docs are present."
echo ""
echo "Manual follow-up:"
echo "1. Register the repository in a Claude Code marketplace."
echo "2. Install any-claw-skills."
echo "3. Start a new session and verify /build-assistant is available."
