#!/bin/bash
# test-integration-manifest.sh — integration-contract-check smoke
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_SCRIPTS:-${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts}"
CHECK="$SCRIPTS/integration-contract-check.sh"
MANIFEST="$DIR/integration-manifest-good.json"
[[ -x "$CHECK" ]] || chmod +x "$CHECK"
# Expect fail on missing fixture roots (paths not on disk) — script should run without crash
if "$CHECK" "$MANIFEST"; then
  echo "FAIL: expected missing roots to block" >&2
  exit 1
fi
echo "OK integration-contract-check rejects missing fixture roots"
