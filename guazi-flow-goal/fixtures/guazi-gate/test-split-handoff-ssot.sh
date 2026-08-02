#!/bin/bash
# test-split-handoff-ssot.sh — split layout: Tier-R plan.json without repo handoff or GOAL_HANDOFF_DIR
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_SCRIPTS:-${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts}"
GOOD="$DIR/contract-iq10-good"
IQ="$SCRIPTS/contract-conformance-check.py"
RESOLVER="$SCRIPTS/handoff_path_resolver.py"

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

export GOAL_STATE_FILE="$STATE_FILE"
unset GOAL_HANDOFF_DIR
unset HANDOFF_DIR
unset GOAL_REPO_ROOT

echo "split-handoff: resolver points at Tier-R"
python3 - <<PY
import os, sys
from pathlib import Path
sys.path.insert(0, "$SCRIPTS")
from handoff_path_resolver import resolve_handoff_dir, resolve_plan_json_path
ho = resolve_handoff_dir("$TASK", state_file="$STATE_FILE", project_root="$repo")
plan = resolve_plan_json_path("$TASK", state_file="$STATE_FILE", project_root="$repo")
assert Path(ho).resolve() == Path("$RUNTIME/handoff").resolve(), ho
assert os.path.isfile(plan), plan
print("OK handoff_dir", ho)
PY

echo "split-handoff: IQ-10 without GOAL_HANDOFF_DIR"
HASH=$(python3 -c "
import sys
sys.path.insert(0, '$SCRIPTS')
from contract_parser import api_mapping_table_hash
print(api_mapping_table_hash(open('$TASK/index.md', encoding='utf-8').read()))
")
python3 -c "import json; p=json.load(open('$RUNTIME/handoff/plan.json')); p['api_mapping_table_hash']='$HASH'; json.dump(p, open('$RUNTIME/handoff/plan.json','w'), indent=2)"
IQ_OUT=$(mktemp)
python3 "$IQ" --task-dir "$TASK" --repo-root "$TASK" --json > "$IQ_OUT"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('passed') else 1)" "$IQ_OUT"
rm -f "$IQ_OUT"

echo "split-handoff: AM ratchet reads Tier-R plan (write_set non-empty)"
python3 - <<PY
import json, os, sys
sys.path.insert(0, "$SCRIPTS")
from handoff_path_resolver import resolve_plan_json_path
p = resolve_plan_json_path("$TASK", state_file="$STATE_FILE", project_root="$repo")
ws = json.load(open(p, encoding="utf-8")).get("write_set") or []
assert ws, "Tier-R plan.json missing write_set"
print("OK write_set", len(ws))
PY

echo "split-handoff: ux_scan loads write_set from Tier-R"
python3 "$SCRIPTS/ux_scan_v1.py" \
  --task-dir "$TASK" --repo-root "$TASK" --project-root "$repo" \
  --state-file "$STATE_FILE" --format text
EV="$RUNTIME/evidence/ux-scan.json"
test -f "$EV" || { echo "FAIL missing $EV"; exit 1; }

unset GOAL_STATE_FILE

echo "test-split-handoff-ssot passed"
