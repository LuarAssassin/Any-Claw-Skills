#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "=== Template Integrity Checks ==="
echo ""

for scaffold in \
  "${ROOT}/templates/scaffolds/picoclaw-tier/go" \
  "${ROOT}/templates/scaffolds/nanoclaw-tier/typescript" \
  "${ROOT}/templates/scaffolds/copaw-tier/python" \
  "${ROOT}/templates/scaffolds/openclaw-tier/typescript" \
  "${ROOT}/templates/scaffolds/ironclaw-tier/rust"
do
  test -d "${scaffold}"
done

for domain in health productivity social education finance smart-home; do
  test -f "${ROOT}/templates/domains/${domain}/system-prompt.md"
  test -f "${ROOT}/templates/domains/${domain}/knowledge.md"
  test -f "${ROOT}/templates/domains/${domain}/tools.go.md"
  test -f "${ROOT}/templates/domains/${domain}/tools.python.md"
  test -f "${ROOT}/templates/domains/${domain}/tools.typescript.md"
  test -f "${ROOT}/templates/domains/${domain}/mcp-server.python.md"
  test -f "${ROOT}/templates/domains/${domain}/mcp-server.typescript.md"
done

for provider in openai anthropic ollama provider-router; do
  test -f "${ROOT}/templates/providers/${provider}.go.md"
  test -f "${ROOT}/templates/providers/${provider}.python.md"
  test -f "${ROOT}/templates/providers/${provider}.typescript.md"
done

for channel in cli dingtalk discord feishu slack telegram whatsapp; do
  test -f "${ROOT}/templates/channels/${channel}.go.md"
  test -f "${ROOT}/templates/channels/${channel}.python.md"
  test -f "${ROOT}/templates/channels/${channel}.typescript.md"
done

test -f "${ROOT}/templates/channels/web-ui.typescript.md"

echo "Scaffold, provider, channel, and domain templates are present."
