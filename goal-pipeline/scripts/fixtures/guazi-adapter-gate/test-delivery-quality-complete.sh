#!/bin/bash
# test-delivery-quality-complete.sh — complete post must write delivery-quality v2
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPLETE_SH="$ROOT/gate-lib/complete.sh"
grep -q 'write-delivery-quality' "$COMPLETE_SH" || { echo "FAIL complete.sh missing delivery hook"; exit 1; }
grep -q 'delivery-quality.json' "$COMPLETE_SH" || { echo "FAIL complete.sh missing delivery output path"; exit 1; }
echo "OK complete gate wired for delivery-quality.json"
