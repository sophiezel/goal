#!/usr/bin/env bash
# Fixture: plan gate not passed + dirty src → assert-plan-before-code exits 2
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSERT="$SCRIPT_DIR/../../assert_plan_before_code.py"
GATE="$SCRIPT_DIR/../../gate-guazi-flow-stage.sh"
RESOLVE="$SCRIPT_DIR/../../resolve-artifact-paths.py"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GOAL_STATE_HOME="$tmp/goal-state"
export GOAL_ARTIFACT_MODE=repo_full
mkdir -p "$GOAL_STATE_HOME"

# Minimal git repo with dirty src and guazi-flow task dir
repo="$tmp/repo"
mkdir -p "$repo/src" "$repo/docs/guazi-flow/demo-task/handoff" "$repo/docs/guazi-flow/demo-task/evidence"
cd "$repo"
git init -q
git config user.email "test@example.com"
git config user.name "test"
echo "base" > README.md
git add README.md && git commit -qm "init"
mkdir -p src
echo "console.log('dirty')" > src/app.js
# untracked dirty src

TASK="$repo/docs/guazi-flow/demo-task"
# index stub (not needed for assert alone)
cat > "$TASK/index.md" <<'MD'
# demo

## 核心事实
x

## 完整伪代码
y

## 验收矩阵
z

## 执行记录
-
MD

echo "=== assert-plan-before-code blocks dirty src without plan gate ==="
OUT=$(python3 "$ASSERT" --task-dir "$TASK" --project-root "$repo" --mode json) || RC=$?
RC=${RC:-0}
if [[ "$RC" -ne 2 ]]; then
  echo "FAIL expected exit 2 got $RC"; echo "$OUT"; exit 1
fi
CODE=$(echo "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('failure_code'))")
if [[ "$CODE" != "plan_code_order" ]]; then
  echo "FAIL expected plan_code_order got $CODE"; exit 1
fi
echo "OK blocked plan_code_order"

echo "=== assert OK when plan gate passed ==="
cat > "$TASK/handoff/plan.json" <<'JSON'
{
  "write_set": ["src/app.js"],
  "gate": {"passed_at": "2026-07-14T00:00:00Z", "post_exit_code": 0}
}
JSON
RC=0
OUT=$(python3 "$ASSERT" --task-dir "$TASK" --project-root "$repo" --mode json) || RC=$?
if [[ "$RC" -ne 0 ]]; then
  echo "FAIL expected exit 0 when plan passed"; echo "$OUT"; exit 1
fi
echo "OK plan passed allows dirty src"

echo "=== find_state_file ignores wrong branch ==="
PID=$(python3 -c "import hashlib; from pathlib import Path; print(hashlib.sha256(str(Path('$repo').resolve()).encode()).hexdigest()[:12])")
BRANCH=$(git -C "$repo" rev-parse --abbrev-ref HEAD)
mkdir -p "$GOAL_STATE_HOME/projects/$PID/other-branch/demo-task"
mkdir -p "$GOAL_STATE_HOME/projects/$PID/$BRANCH/demo-task"
echo "{\"project_id\":\"$PID\",\"branch\":\"other-branch\",\"guazi_flow_task\":\"docs/guazi-flow/demo-task\"}" \
  > "$GOAL_STATE_HOME/projects/$PID/other-branch/demo-task/state.json"
echo "{\"project_id\":\"$PID\",\"branch\":\"$BRANCH\",\"guazi_flow_task\":\"docs/guazi-flow/demo-task\"}" \
  > "$GOAL_STATE_HOME/projects/$PID/$BRANCH/demo-task/state.json"
FOUND=$(python3 "$RESOLVE" --task-dir "$TASK" --project-root "$repo" --format json \
  | python3 -c "import json,sys; print(json.load(sys.stdin).get('state_file') or '')")
# resolve may not always expose state_file — check via find helper
FOUND=$(python3 - <<PY
import importlib.util, os, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("rap", "$RESOLVE")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
os.environ["GOAL_STATE_HOME"] = "$GOAL_STATE_HOME"
sf = m.find_state_file(Path("$TASK"), Path("$repo"))
print(str(sf) if sf else "")
PY
)
if [[ "$FOUND" != *"$BRANCH/demo-task/state.json" ]]; then
  echo "FAIL expected current-branch state got: $FOUND"; exit 1
fi
echo "OK branch-scoped state discovery"

echo "=== gate plan --pre fails on dirty src ==="
# Remove plan handoff for pre guard
rm -f "$TASK/handoff/plan.json"
set +e
bash "$GATE" --task-dir "$TASK" --stage plan --pre --mode guazi --project-root "$repo" >/tmp/gate-pbc.out 2>&1
GRC=$?
set -e
if [[ "$GRC" -eq 0 ]]; then
  echo "FAIL gate plan --pre should fail"; cat /tmp/gate-pbc.out; exit 1
fi
grep -q plan_code_order /tmp/gate-pbc.out || { echo "FAIL missing plan_code_order in gate output"; cat /tmp/gate-pbc.out; exit 1; }
echo "OK gate plan --pre hard-blocks"

echo "OK plan-before-code fixture"
