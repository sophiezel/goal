#!/bin/bash
# test-kernel-no-guazi-doc-paths.sh — kernel core must not reference docs/guazi-flow
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
KERNEL="$REPO_ROOT/kernel"
if rg -n 'docs/guazi-flow' "$KERNEL" --glob '*.py' 2>/dev/null; then
  echo "FAIL kernel contains docs/guazi-flow hardcode"
  exit 1
fi
echo "OK kernel has no docs/guazi-flow paths"
