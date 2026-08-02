#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_SCRIPTS:-${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts}"
PORT="$SCRIPTS/validate-stage-port.py"
PLAN_GOOD="$SCRIPT_DIR/plan-good"
"$PORT" --task-dir "$PLAN_GOOD" --stage plan
echo "OK validate-stage-port plan-good"

CHAIN="$SCRIPT_DIR/chain-good"
"$PORT" --task-dir "$CHAIN" --only-present
echo "OK validate-stage-port chain-good (only-present)"
