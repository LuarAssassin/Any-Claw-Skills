#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPTS_DIR="${SCRIPT_DIR}/prompts"

echo "=== Expansion Flow Tests ==="
echo ""
echo "These tests verify add-channel, add-domain, add-provider, and add-tool flows."
echo ""

for prompt_file in "${PROMPTS_DIR}"/*.txt; do
    name=$(basename "$prompt_file" .txt)
    echo "--- Test: ${name} ---"
    sed -n '1,220p' "$prompt_file"
    echo ""
done
