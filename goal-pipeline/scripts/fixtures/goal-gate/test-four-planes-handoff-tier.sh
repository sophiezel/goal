#!/bin/bash
# test-four-planes-handoff-tier.sh — four_planes_doctor live split handoff tier (#17)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
FOUR="$SCRIPTS/four_planes_doctor.py"
GOOD="$DIR/contract-iq10-good"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GOAL_STATE_HOME="$tmp/goal-state"
mkdir -p "$GOAL_STATE_HOME"

repo="$tmp/repo"
mkdir -p "$repo"
cp -a "$GOOD" "$repo/task"
TASK="$repo/task"
cd "$repo"
git init -q
git config user.email "test@example.com"
git config user.name "test"
echo base > README.md
git add README.md && git commit -qm "init"
git add task && git commit -qm "add task fixture"

PID=$(python3 -c "import hashlib; from pathlib import Path; print(hashlib.sha256(str(Path('$repo').resolve()).encode()).hexdigest()[:12])")
BRANCH=$(git rev-parse --abbrev-ref HEAD)
RUNTIME="$GOAL_STATE_HOME/projects/$PID/$BRANCH/demo-split/artifacts"
STATE_FILE="$GOAL_STATE_HOME/projects/$PID/$BRANCH/demo-split/state.json"
mkdir -p "$RUNTIME/handoff"
cp "$TASK/handoff/plan.json" "$RUNTIME/handoff/plan.json"
rm -rf "$TASK/handoff"

mkdir -p "$(dirname "$STATE_FILE")"
python3 - <<PY
import json
from pathlib import Path
state = {
    "project_id": "$PID",
    "branch": "$BRANCH",
    "guazi_flow_task": "task",
    "artifact_layout": {
        "mode": "split",
        "runtime_root": "$RUNTIME",
        "repo_task_dir": "$TASK",
    },
}
Path("$STATE_FILE").write_text(json.dumps(state, indent=2) + "\\n", encoding="utf-8")
PY

echo "four-planes-handoff-tier: doctor live checks (no GOAL_HANDOFF_DIR)"
unset GOAL_HANDOFF_DIR
unset HANDOFF_DIR
unset GOAL_STATE_FILE

OUT=$(mktemp)
python3 "$FOUR" \
  --task-dir "$TASK" \
  --project-root "$repo" \
  --state-file "$STATE_FILE" \
  --format json > "$OUT" || true

python3 - <<PY
import json, sys
d = json.load(open("$OUT", encoding="utf-8"))
checks = {c["check"]: c for c in d.get("checks", [])}
required = (
    "data.handoff_tier_rap_resolver",
    "data.handoff_tier_plan_json",
    "data.handoff_ssot_drift",
    "data.qg_shell_handoff_ssot",
)
missing = [k for k in required if k not in checks]
if missing:
    print("FAIL missing checks", missing)
    sys.exit(1)
for k in required:
    c = checks[k]
    if c.get("status") != "ok":
        print("FAIL", k, c)
        sys.exit(1)
if not d.get("ok"):
    print("FAIL doctor ok=false", d.get("failed"))
    sys.exit(1)
print("OK handoff tier checks", list(required))
PY
rm -f "$OUT"

echo "four-planes-handoff-tier: GOAL_RUN_FOUR_PLANES_DOCTOR without state fails signal"
export GOAL_RUN_FOUR_PLANES_DOCTOR=1
FAIL_OUT=$(mktemp)
python3 "$FOUR" --format json > "$FAIL_OUT" 2>/dev/null || true
python3 - <<PY
import json, sys
d = json.load(open("$FAIL_OUT", encoding="utf-8"))
c = next((x for x in d.get("checks", []) if x.get("check") == "data.handoff_tier_live"), None)
if not c or c.get("status") != "fail":
    print("FAIL expected data.handoff_tier_live fail", c)
    sys.exit(1)
if d.get("ok"):
    print("FAIL doctor should not be ok without task/state", d.get("failed"))
    sys.exit(1)
print("OK tier_live guard")
PY
rm -f "$FAIL_OUT"
unset GOAL_RUN_FOUR_PLANES_DOCTOR

echo "test-four-planes-handoff-tier passed"
