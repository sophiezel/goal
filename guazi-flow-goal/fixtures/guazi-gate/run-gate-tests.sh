#!/bin/bash
# guazi-flow-goal gate fixture CI entry
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUAZI_ROOT="$(cd "$DIR/../.." && pwd)"
GATE="${GUAZI_SCRIPTS:-${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts}/guazi-gate-stage.sh"

echo "=== guazi-gate plan-good ==="
"$GATE" --task-dir "$DIR/plan-good" --stage plan --post --mode guazi || {
  echo "FAIL plan-good"; exit 1
}
echo "guazi gate smoke passed"
