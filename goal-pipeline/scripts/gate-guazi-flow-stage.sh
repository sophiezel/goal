#!/bin/bash
# gate-guazi-flow-stage.sh — DEPRECATED compat wrapper (v1.3)
# Prefer gate-goal-stage.sh. This entry forces --mode guazi when not explicitly set.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOAL_GATE="${SCRIPT_DIR}/gate-goal-stage.sh"
[[ -x "$GOAL_GATE" ]] || { echo "gate-guazi-flow-stage: gate-goal-stage.sh missing" >&2; exit 2; }
if [[ "${GOAL_GATE_COMPAT_WARN:-1}" != "0" ]]; then
  echo "DEPRECATED: gate-guazi-flow-stage.sh — use gate-goal-stage.sh (GOAL_GATE_COMPAT_WARN=0 to silence)" >&2
fi
has_mode=false
for a in "$@"; do
  [[ "$a" == "--mode" ]] && has_mode=true
done
if $has_mode; then
  exec "$GOAL_GATE" "$@"
fi
exec "$GOAL_GATE" --mode guazi "$@"
