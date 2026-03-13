#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_BIN="$(mktemp -d)"
trap 'rm -rf "${TMP_BIN}"' EXIT

cat > "${TMP_BIN}/rg" <<'EOF'
#!/usr/bin/env bash
echo "rg intentionally unavailable in this portability test" >&2
exit 127
EOF

chmod +x "${TMP_BIN}/rg"

NODE_DIR="$(dirname "$(command -v node)")"

echo "=== No-rg Portability Check ==="
echo ""

PATH="${TMP_BIN}:${NODE_DIR}:/usr/bin:/bin:/opt/homebrew/bin" \
  bash "${ROOT}/tests/docs-consistency/run-test.sh"

echo "Docs consistency checks do not depend on rg."
