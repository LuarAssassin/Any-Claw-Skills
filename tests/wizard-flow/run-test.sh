#!/usr/bin/env bash
# Test full wizard flow scenarios.
# These are manual/semi-automated tests — walk through each flow
# in a Claude Code session and verify the expected output.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPTS_DIR="${SCRIPT_DIR}/prompts"

echo "=== Wizard Flow Tests ==="
echo ""
echo "These tests verify the full build-assistant wizard flow."
echo "Each test describes a complete scenario with choices and expected files."
echo "The golden path scenario should be treated as the primary release check."
echo ""

for prompt_file in "${PROMPTS_DIR}"/*.txt; do
    name=$(basename "$prompt_file" .txt)
    echo "--- Test: ${name} ---"
    echo "Description file: ${prompt_file}"
    echo ""

    # Extract verification checklist
    if grep -q "Verification" "$prompt_file"; then
        echo "Verification checklist:"
        sed -n '/^## Verification/,/^##/p' "$prompt_file" | grep '^\- \[' || true
        echo ""
    fi
done

echo "=== How to Run ==="
echo "1. Create a fresh temporary directory: mkdir /tmp/test-wizard && cd /tmp/test-wizard"
echo "2. Start Claude Code with any-claw-skills installed"
echo "3. Say: 'I want to build a personal assistant'"
echo "4. Follow the wizard, making choices as described in the test file"
echo "5. After generation, verify all checklist items"
echo "6. Clean up: rm -rf /tmp/test-wizard"
