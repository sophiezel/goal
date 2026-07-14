#!/usr/bin/env bash
# assert-plan-before-code.sh — shell wrapper for assert_plan_before_code.py
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/assert_plan_before_code.py" "$@"
