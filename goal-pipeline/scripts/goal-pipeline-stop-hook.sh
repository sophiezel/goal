#!/bin/bash
# goal-pipeline-stop-hook.sh — Cursor stop hook: block early exit when pipeline incomplete
# Uses gate --assert-complete + goal-stage-driver for followup work orders

set -euo pipefail

GOAL_STATE_HOME="${GOAL_STATE_HOME:-$HOME/.goal-state}"
GATE="$GOAL_STATE_HOME/scripts/gate-guazi-flow-stage.sh"
DRIVER="$GOAL_STATE_HOME/scripts/goal-stage-driver.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -x "$GATE" ]] || GATE="$SCRIPT_DIR/gate-guazi-flow-stage.sh"
[[ -x "$DRIVER" ]] || DRIVER="$SCRIPT_DIR/goal-stage-driver.sh"

INPUT=$(cat)
WORKSPACE=$(echo "$INPUT" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    print(''); sys.exit(0)
for k in ('workspace_roots','workspaceRoot','cwd','root'):
    v=d.get(k)
    if isinstance(v,list) and v: print(v[0]); sys.exit(0)
    if isinstance(v,str) and v: print(v); sys.exit(0)
print('')
" 2>/dev/null || echo "")

find_active_states() {
  local ws="$1"
  local states_dir="$GOAL_STATE_HOME/projects"
  [[ -d "$states_dir" ]] || return 0
  find "$states_dir" -name state.json 2>/dev/null | while read -r sf; do
    python3 - "$sf" "$ws" << 'PY'
import json, sys, os
sf, ws = sys.argv[1], sys.argv[2]
try:
    st = json.load(open(sf))
except Exception:
    sys.exit(0)
if st.get("status") not in ("active", "blocked"):
    sys.exit(0)
if st.get("current_stage") in ("complete", "done") or st.get("status") == "complete":
    sys.exit(0)
root = st.get("project_root") or st.get("repo_root") or ""
if ws:
    if not root or os.path.normpath(root) != os.path.normpath(ws):
        sys.exit(0)
task = st.get("guazi_flow_task") or st.get("task_dir") or ""
print(json.dumps({"state_file": sf, "task": task, "objective": st.get("objective","")[:80]}))
PY
  done
}

find_incomplete_tasks() {
  local ws="$1"
  [[ -n "$ws" && -d "$ws" ]] || return 0
  find "$ws/docs/guazi-flow" -maxdepth 2 -name index.md 2>/dev/null | while read -r idx; do
    if grep -qE 'current_stage:\s*complete' "$idx" 2>/dev/null; then
      continue
    fi
    task_dir=$(dirname "$idx")
    rel="${task_dir#"$ws"/}"
    echo "{\"state_file\":\"\",\"task\":\"$rel\",\"objective\":\"incomplete index.md\"}"
  done
}

INCOMPLETE=""
if [[ -n "$WORKSPACE" ]]; then
  INCOMPLETE=$(find_active_states "$WORKSPACE" | head -1 || true)
  [[ -z "$INCOMPLETE" ]] && INCOMPLETE=$(find_incomplete_tasks "$WORKSPACE" | head -1 || true)
fi
[[ -z "$INCOMPLETE" ]] && INCOMPLETE=$(find_active_states "" | head -1 || true)
[[ -z "$INCOMPLETE" ]] && exit 0

STATE_FILE=$(echo "$INCOMPLETE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('state_file',''))")
TASK=$(echo "$INCOMPLETE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('task',''))")
OBJECTIVE=$(echo "$INCOMPLETE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('objective',''))")

PROJECT_ROOT=""
if [[ -n "$STATE_FILE" && -f "$STATE_FILE" ]]; then
  PROJECT_ROOT=$(python3 - "$STATE_FILE" << 'PYROOT'
import json, sys
st = json.load(open(sys.argv[1]))
print(st.get("project_root") or st.get("repo_root") or "")
PYROOT
)
fi
[[ -n "$PROJECT_ROOT" ]] || PROJECT_ROOT="$WORKSPACE"

# assert-complete when we have full context
ASSERT_RC=0
if [[ -n "$STATE_FILE" && -f "$STATE_FILE" && -n "$PROJECT_ROOT" && -n "$TASK" && -x "$GATE" ]]; then
  "$GATE" --assert-complete --state-file "$STATE_FILE" --task-dir "$TASK" --project-root "$PROJECT_ROOT" >/dev/null 2>&1 || ASSERT_RC=$?
  [[ "$ASSERT_RC" == "0" ]] && exit 0
fi

# Build followup via stage driver when possible
WORK_ORDER=""
if [[ -x "$DRIVER" && -n "$STATE_FILE" && -f "$STATE_FILE" && -n "$PROJECT_ROOT" && -n "$TASK" ]]; then
  WORK_ORDER=$("$DRIVER" --state-file "$STATE_FILE" --task-dir "$TASK" --project-root "$PROJECT_ROOT" --format json 2>/dev/null || true)
fi

python3 - "$OBJECTIVE" "$WORK_ORDER" << 'PY'
import json, sys

objective = sys.argv[1]
wo_s = sys.argv[2] if len(sys.argv) > 2 else ""
wo = {}
if wo_s.strip():
    try:
        wo = json.loads(wo_s)
    except json.JSONDecodeError:
        wo = {}

next_stage = wo.get("next_stage", "unknown")
blocked_reason = wo.get("blocked_reason") or ""
cmds = wo.get("mandatory_commands") or []
skill = wo.get("skill_to_load") or ""
never = wo.get("never") or []

lines = [
    f"Pipeline incomplete — MUST continue guazi-flow-goal (next_stage={next_stage}",
]
if blocked_reason:
    lines[0] += f", reason={blocked_reason}"
lines[0] += ")."

if skill:
    lines.append(f"Load skill: {skill}")
for i, c in enumerate(cmds[:3], 1):
    lines.append(f"cmd{i}: {c}")
if never:
    lines.append(f"禁止: {never[0]}")

lines.append(f"Objective: {objective}")
msg = " ".join(lines)
print(json.dumps({"followup_message": msg}))
PY
exit 0
