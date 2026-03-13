#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

must_contain() {
  local needle="$1"
  local file="$2"

  if ! grep -F -q -- "${needle}" "${file}"; then
    echo "Expected to find '${needle}' in ${file}"
    exit 1
  fi
}

must_not_contain() {
  local needle="$1"
  local file="$2"
  local message="$3"

  if grep -F -q -- "${needle}" "${file}"; then
    echo "${message}"
    exit 1
  fi
}

repo_must_not_contain_root_path() {
  while IFS= read -r -d '' file; do
    if grep -F -q -- "${ROOT}" "${file}"; then
      echo "Found machine-specific absolute path in ${file}"
      exit 1
    fi
  done < <(
    find "${ROOT}" \
      -type f \
      ! -path "${ROOT}/reference-skills/*" \
      ! -path "${ROOT}/tests/docs-consistency/run-test.sh" \
      -print0
  )
}

echo "=== Docs Consistency Checks ==="
echo ""

test -f "${ROOT}/docs/release-checklist.md"
test -f "${ROOT}/docs/support-matrix.md"
test -f "${ROOT}/docs/domain-pack-contract.md"
test -f "${ROOT}/docs/assistant-product-composition-model.md"
test -f "${ROOT}/docs/testing.md"
test -f "${ROOT}/docs/examples/golden-path-standard-python-productivity.md"
test -f "${ROOT}/docs/examples/picoclaw-minimal-cli-assistant.md"
test -f "${ROOT}/docs/examples/nanoclaw-customizable-discord-assistant.md"
test -f "${ROOT}/docs/examples/openclaw-multichannel-operations-assistant.md"
test -f "${ROOT}/README.zh-CN.md"
test -f "${ROOT}/CONTRIBUTORS.md"
test -f "${ROOT}/skills/build-assistant/reference-mode-selection.md"

must_contain "Claude Code first" "${ROOT}/README.md"
must_contain "README.zh-CN.md" "${ROOT}/README.md"
must_contain "Reference Product Modes" "${ROOT}/README.md"
must_contain "PicoClaw" "${ROOT}/README.md"
must_contain "OpenClaw" "${ROOT}/README.md"
must_contain "Claude Code Workflow" "${ROOT}/README.md"
must_contain "Golden Path" "${ROOT}/README.md"
must_contain "Support Matrix" "${ROOT}/README.md"
must_contain "Roadmap" "${ROOT}/README.md"
must_contain "CONTRIBUTORS.md" "${ROOT}/README.md"
must_contain "安装后 Claude Code 会怎么工作" "${ROOT}/README.zh-CN.md"
must_contain "参考产品模式" "${ROOT}/README.zh-CN.md"
must_contain "PicoClaw" "${ROOT}/README.zh-CN.md"
must_contain "OpenClaw" "${ROOT}/README.zh-CN.md"
must_contain "Claude Code 工作流" "${ROOT}/README.zh-CN.md"
must_contain "CONTRIBUTORS.md" "${ROOT}/README.zh-CN.md"
must_contain "openclaw-multichannel-operations-assistant.md" "${ROOT}/docs/examples/README.md"
must_contain "assistant product composer" "${ROOT}/skills/build-assistant/SKILL.md"
must_contain "PicoClaw-style" "${ROOT}/skills/build-assistant/SKILL.md"
must_contain "identity, allowlists, pairing, or group isolation" "${ROOT}/skills/build-assistant/SKILL.md"
must_contain "templates/scaffolds/copaw-tier/python" "${ROOT}/skills/build-assistant/SKILL.md"
must_contain "five reference product shapes" "${ROOT}/skills/using-any-claw-skills/SKILL.md"
must_contain "reference mode" "${ROOT}/commands/build-assistant.md"
must_contain "Reference Mode Selection" "${ROOT}/skills/build-assistant/reference-mode-selection.md"
must_contain "PicoClaw Mode" "${ROOT}/skills/build-assistant/reference-mode-selection.md"
must_contain "NanoClaw Mode" "${ROOT}/skills/build-assistant/reference-mode-selection.md"
must_contain "Control Surface" "${ROOT}/skills/build-assistant/reference-mode-selection.md"
must_contain "Reference mode: CoPaw" "${ROOT}/tests/wizard-flow/prompts/golden-standard-python-productivity-flow.txt"
must_contain "Reference mode: NanoClaw" "${ROOT}/tests/wizard-flow/prompts/nano-typescript-productivity-flow.txt"
must_contain "Reference mode: PicoClaw" "${ROOT}/tests/wizard-flow/prompts/pico-go-minimal-flow.txt"
must_contain "Reference mode: CoPaw" "${ROOT}/tests/wizard-flow/prompts/standard-python-health-flow.txt"
must_contain "reference mode or product shape" "${ROOT}/tests/wizard-flow/run-test.sh"
must_not_contain "templates/scaffolds/{{tier}}-tier" "${ROOT}/skills/build-assistant/SKILL.md" "Found stale tier-to-scaffold placeholder mapping in build-assistant skill."
must_contain "out-of-the-box" "${ROOT}/docs/domain-pack-contract.md"
must_contain "routines.md" "${ROOT}/docs/domain-pack-contract.md"
must_contain "ingestion.md" "${ROOT}/docs/domain-pack-contract.md"
must_contain "policy.md" "${ROOT}/docs/domain-pack-contract.md"
must_contain "Reference Product Modes" "${ROOT}/skills/build-assistant/complexity-tiers.md"
must_contain "personal assistant product" "${ROOT}/docs/assistant-product-composition-model.md"
must_contain "identity, pairing, and access control" "${ROOT}/docs/assistant-product-composition-model.md"
must_contain "Safety and Quality Surfaces" "${ROOT}/docs/assistant-product-composition-model.md"
must_contain "Claude Code" "${ROOT}/CONTRIBUTORS.md"
must_contain "Codex" "${ROOT}/CONTRIBUTORS.md"
must_contain "GA" "${ROOT}/STATUS.md"
must_contain "Beta" "${ROOT}/STATUS.md"
must_contain "Preview" "${ROOT}/STATUS.md"
must_contain "Blockers" "${ROOT}/STATUS.md"

repo_must_not_contain_root_path

node -e "const fs=require('fs'); const files=['${ROOT}/.claude-plugin/plugin.json','${ROOT}/.cursor-plugin/plugin.json','${ROOT}/gemini-extension.json']; const versions=files.map(f=>JSON.parse(fs.readFileSync(f,'utf8')).version); const market=JSON.parse(fs.readFileSync('${ROOT}/.claude-plugin/marketplace.json','utf8')).plugins[0].version; if(!versions.every(v=>v===market)) process.exit(1)"

echo "Docs and metadata are consistent."
