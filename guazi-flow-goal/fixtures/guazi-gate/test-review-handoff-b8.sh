#!/bin/bash
# test-review-handoff-b8.sh — review post handoff carries single-track + goal-review (B8)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_SCRIPTS:-${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts}"
GATE="$SCRIPTS/guazi-gate-stage.sh"
FIX="$DIR/review-fix-input-good"
export GOAL_ARTIFACT_MODE=repo_full

rm -f "$FIX/handoff/review.json"
if ! "$GATE" --task-dir "$FIX" --stage review --post --mode guazi; then
  echo "FAIL: review-fix-input-good gate post expected pass"; exit 1
fi

python3 - "$FIX" << 'PY'
import json, sys
task = sys.argv[1]
handoff = json.load(open(f"{task}/handoff/review.json", encoding="utf-8"))
run = json.load(open(f"{task}/evidence/review-run.json", encoding="utf-8"))
assert handoff.get("review_track") == "single", handoff.get("review_track")
assert handoff.get("wrapper_profile") == "goal-review", handoff.get("wrapper_profile")
assert run.get("wrapper_profile") == "goal-review", run.get("wrapper_profile")
assert run.get("review_track") == "single", run.get("review_track")
print("OK review handoff B8 single + goal-review")
PY
