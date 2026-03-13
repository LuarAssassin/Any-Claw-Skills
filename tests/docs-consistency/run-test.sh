#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "=== Docs Consistency Checks ==="
echo ""

test -f "${ROOT}/docs/release-checklist.md"
test -f "${ROOT}/docs/support-matrix.md"
test -f "${ROOT}/docs/domain-pack-contract.md"
test -f "${ROOT}/docs/assistant-product-composition-model.md"
test -f "${ROOT}/docs/testing.md"
test -f "${ROOT}/docs/examples/golden-path-standard-python-productivity.md"
test -f "${ROOT}/README.zh-CN.md"

rg -q "Claude Code first" "${ROOT}/README.md"
rg -q "README.zh-CN.md" "${ROOT}/README.md"
rg -q "Reference Product Modes" "${ROOT}/README.md"
rg -q "PicoClaw" "${ROOT}/README.md"
rg -q "OpenClaw" "${ROOT}/README.md"
rg -q "Claude Code Workflow" "${ROOT}/README.md"
rg -q "Golden Path" "${ROOT}/README.md"
rg -q "Support Matrix" "${ROOT}/README.md"
rg -q "Roadmap" "${ROOT}/README.md"
rg -q "安装后 Claude Code 会怎么工作" "${ROOT}/README.zh-CN.md"
rg -q "参考产品模式" "${ROOT}/README.zh-CN.md"
rg -q "PicoClaw" "${ROOT}/README.zh-CN.md"
rg -q "OpenClaw" "${ROOT}/README.zh-CN.md"
rg -q "Claude Code 工作流" "${ROOT}/README.zh-CN.md"
rg -q "assistant product composer" "${ROOT}/skills/build-assistant/SKILL.md"
rg -q "PicoClaw-style" "${ROOT}/skills/build-assistant/SKILL.md"
rg -q "out-of-the-box" "${ROOT}/docs/domain-pack-contract.md"
rg -q "Reference Product Modes" "${ROOT}/skills/build-assistant/complexity-tiers.md"
rg -q "personal assistant product" "${ROOT}/docs/assistant-product-composition-model.md"
rg -q "GA" "${ROOT}/STATUS.md"
rg -q "Beta" "${ROOT}/STATUS.md"
rg -q "Preview" "${ROOT}/STATUS.md"
rg -q "Blockers" "${ROOT}/STATUS.md"

if rg -q "${ROOT}" "${ROOT}" -g '!reference-skills/**' -g '!tests/docs-consistency/run-test.sh'; then
  echo "Found machine-specific absolute paths in repository content."
  exit 1
fi

node -e "const fs=require('fs'); const files=['${ROOT}/.claude-plugin/plugin.json','${ROOT}/.cursor-plugin/plugin.json','${ROOT}/gemini-extension.json']; const versions=files.map(f=>JSON.parse(fs.readFileSync(f,'utf8')).version); const market=JSON.parse(fs.readFileSync('${ROOT}/.claude-plugin/marketplace.json','utf8')).plugins[0].version; if(!versions.every(v=>v===market)) process.exit(1)"

echo "Docs and metadata are consistent."
