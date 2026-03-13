#!/usr/bin/env bash
# Run all test suites

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "  any-claw-skills Test Suite"
echo "=========================================="
echo ""

echo "[1/5] Docs Consistency Checks"
echo "---"
bash "${SCRIPT_DIR}/docs-consistency/run-test.sh"
echo ""

echo "[2/5] Install Smoke Checks"
echo "---"
bash "${SCRIPT_DIR}/install-smoke/run-test.sh"
echo ""

echo "[3/5] Skill Triggering Tests"
echo "---"
bash "${SCRIPT_DIR}/skill-triggering/run-test.sh"
echo ""

echo "[4/5] Wizard Flow Tests"
echo "---"
bash "${SCRIPT_DIR}/wizard-flow/run-test.sh"
echo ""

echo "[5/5] Expansion Flow Tests"
echo "---"
bash "${SCRIPT_DIR}/expansion-flow/run-test.sh"
echo ""

echo "=========================================="
echo "  Scripted checks have passed."
echo "  Follow the manual instructions printed"
echo "  above for the prompt-driven suites."
echo "=========================================="
