#!/usr/bin/env bash
# Test that skill trigger prompts activate the correct skills.
# This is a manual/semi-automated test — run each prompt through Claude Code
# and verify the correct skill was invoked.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPTS_DIR="${SCRIPT_DIR}/prompts"

echo "=== Skill Triggering Tests ==="
echo ""
echo "These tests verify that user prompts trigger the correct any-claw-skills."
echo "Run each prompt in a Claude Code session with any-claw-skills installed."
echo "Prefer verifying the Claude Code first path before trying Preview clients."
echo ""

for prompt_file in "${PROMPTS_DIR}"/*.txt; do
    name=$(basename "$prompt_file" .txt)
    content=$(cat "$prompt_file")
    echo "--- Test: ${name} ---"
    echo "Prompt: ${content}"
    echo "Expected: Should trigger the corresponding skill"
    echo ""
done

echo "=== Manual Verification ==="
echo "1. Start a new Claude Code session in a directory with any-claw-skills installed"
echo "2. Enter each prompt above"
echo "3. Verify the correct skill is invoked"
echo "4. Verify the response frames support tiers when relevant"
echo "5. Mark PASS/FAIL for each"
