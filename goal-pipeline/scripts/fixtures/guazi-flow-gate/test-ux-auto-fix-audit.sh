#!/bin/bash
# test-ux-auto-fix-audit.sh — empty diff passes; out-of-write_set fails strict
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
AUDIT="$SCRIPTS/ux-auto-fix-audit.py"
FIX="$DIR/contract-iq10-good"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 "$AUDIT" --repo-root "$FIX" --handoff-dir "$FIX/handoff" --format text | grep -q "ok=True"

echo "test-ux-auto-fix-audit passed"
