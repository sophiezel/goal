#!/bin/bash
# test-implement-ux-autofix-wired.sh — implement post runs ux-auto-fix-audit + S+ strict
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPL="$DIR/../../gate-lib/implement.sh"
grep -q 'ux-auto-fix-audit.py' "$IMPL" || { echo "FAIL implement.sh missing ux-auto-fix-audit.py"; exit 1; }
grep -q 'ux-autofix.json' "$IMPL" || { echo "FAIL implement.sh missing ux-autofix evidence path"; exit 1; }
grep -q 'write_set_violation' "$IMPL" || { echo "FAIL implement.sh missing write_set_violation root_cause"; exit 1; }
grep -q 'AF_STRICT' "$IMPL" || { echo "FAIL implement.sh missing S+ strict tier"; exit 1; }
grep -q 'WARN ux-auto-fix-audit' "$IMPL" || { echo "FAIL implement.sh missing non-strict warn"; exit 1; }
echo "OK implement ux-auto-fix wired"
