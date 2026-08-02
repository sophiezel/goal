#!/bin/bash
# test-verify-completion.sh — nested flow.current_stage + state.json align with completion_condition_met
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOAL_ROOT="$(cd "$DIR/../../../.." && pwd)"
VERIFY="$GOAL_ROOT/goal-pipeline/scripts/verify.sh"
FIX="$DIR/verify-nested-complete"
GH=$(git -C "$GOAL_ROOT" rev-parse HEAD 2>/dev/null | cut -c1-16 || echo "fixture0000000001")

for s in plan implement review complete; do
  mkdir -p "$FIX/evidence"
  cat > "$FIX/evidence/${s}.md" << EOF
---
result: pass
git_head: $GH
---
EOF
done

REL="goal-pipeline/scripts/fixtures/goal-gate/verify-nested-complete"
OUT=$(GIT_ROOT="$GOAL_ROOT" GOAL_STATE_FILE="$FIX/state.json" bash "$VERIFY" "$REL" json)
python3 - "$OUT" << 'PY'
import json, sys
d = json.loads(sys.argv[1])
assert d.get("stage_status") == "complete", d
assert d.get("completion_condition_met") is True, d
print("OK verify completion nested flow + state")
PY

echo "test-verify-completion passed"
