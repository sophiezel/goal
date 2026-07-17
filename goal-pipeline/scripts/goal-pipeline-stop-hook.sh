#!/bin/bash
# goal-pipeline-stop-hook.sh — Cursor stop hook: block early exit when pipeline incomplete
# Uses gate --assert-complete + goal-stage-driver for followup work orders

set -euo pipefail

GOAL_STATE_HOME="${GOAL_STATE_HOME:-$HOME/.goal-state}"
GATE="$GOAL_STATE_HOME/scripts/gate-guazi-flow-stage.sh"
KERNEL="$GOAL_STATE_HOME/scripts/goal-pipeline-kernel.sh"
DRIVER="$GOAL_STATE_HOME/scripts/goal-stage-driver.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -x "$GATE" ]] || GATE="$SCRIPT_DIR/gate-guazi-flow-stage.sh"
[[ -x "$KERNEL" ]] || KERNEL="$SCRIPT_DIR/goal-pipeline-kernel.sh"
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

find_workspace_goal_states() {
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
root = st.get("project_root") or st.get("repo_root") or ""
if ws:
    if not root or os.path.normpath(root) != os.path.normpath(ws):
        sys.exit(0)
task = st.get("guazi_flow_task") or st.get("task_dir") or ""
print(json.dumps({
    "state_file": sf,
    "task": task,
    "objective": (st.get("objective") or "")[:80],
    "current_stage": st.get("current_stage") or "",
}))
PY
  done
}

mark_state_complete() {
  local sf="$1"
  [[ -f "$sf" ]] || return 0
  python3 - "$sf" "$SCRIPT_DIR" << 'PY'
import json, sys
from datetime import datetime, timezone
path = sys.argv[1]
sys.path.insert(0, sys.argv[2])
from atomic_json import write_state_atomic
with open(path, encoding="utf-8") as f:
    state = json.load(f)
if state.get("status") == "complete":
    sys.exit(0)
state["status"] = "complete"
state["current_stage"] = "complete"
state["updated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
pipe = state.setdefault("pipeline", {})
for stage in ("plan", "implement", "quality", "review", "complete"):
    entry = pipe.setdefault(stage, {})
    entry["status"] = "passed"
    entry["evidence_fresh"] = True
write_state_atomic(path, state)
PY
}

find_orphan_incomplete_tasks() {
  local ws="$1"
  [[ -n "$ws" && -d "$ws" ]] || return 0
  find "$ws/docs/guazi-flow" -maxdepth 2 -name index.md 2>/dev/null | while read -r idx; do
    if grep -qE 'current_stage:\s*complete' "$idx" 2>/dev/null; then
      continue
    fi
    task_dir=$(dirname "$idx")
    rel="${task_dir#"$ws"/}"
    # Only flag orphan plans (no goal-state binding for this task)
    if find "$GOAL_STATE_HOME/projects" -name state.json 2>/dev/null | while read -r sf; do
      python3 - "$sf" "$rel" << 'PY'
import json, sys, os
sf, rel = sys.argv[1], sys.argv[2]
try:
    st = json.load(open(sf))
except Exception:
    sys.exit(1)
task = (st.get("guazi_flow_task") or st.get("task_dir") or "").strip("/")
if task == rel.strip("/") or task.endswith(rel):
    sys.exit(0)
sys.exit(1)
PY
    done; then
      continue
    fi
    echo "{\"state_file\":\"\",\"task\":\"$rel\",\"objective\":\"incomplete index.md (orphan plan)\"}"
  done
}

pick_incomplete_goal() {
  local ws="$1"
  local states
  states=$(find_workspace_goal_states "$ws" || true)
  [[ -n "$states" ]] || return 0
  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    local sf task objective project_root assert_rc
    sf=$(echo "$row" | python3 -c "import json,sys; print(json.load(sys.stdin).get('state_file',''))")
    task=$(echo "$row" | python3 -c "import json,sys; print(json.load(sys.stdin).get('task',''))")
    objective=$(echo "$row" | python3 -c "import json,sys; print(json.load(sys.stdin).get('objective',''))")
    [[ -n "$sf" && -f "$sf" && -n "$task" && -x "$GATE" ]] || {
      echo "$row"
      return 0
    }
    project_root=$(python3 - "$sf" << 'PYROOT'
import json, sys
st = json.load(open(sys.argv[1]))
print(st.get("project_root") or st.get("repo_root") or "")
PYROOT
)
    [[ -n "$project_root" ]] || project_root="$ws"
    assert_rc=0
    "$GATE" --assert-complete --state-file "$sf" --task-dir "$task" --project-root "$project_root" >/dev/null 2>&1 || assert_rc=$?
    if [[ "$assert_rc" == "0" ]]; then
      mark_state_complete "$sf"
      continue
    fi
    echo "$row"
    return 0
  done <<< "$states"
}

INCOMPLETE=""
if [[ -n "$WORKSPACE" ]]; then
  GOAL_COUNT=$(find_workspace_goal_states "$WORKSPACE" 2>/dev/null | grep -c . || true)
  INCOMPLETE=$(pick_incomplete_goal "$WORKSPACE" || true)
  # Orphan index.md scan only when this workspace has no bound goal-state at all
  if [[ -z "$INCOMPLETE" && "${GOAL_COUNT:-0}" -eq 0 && "${GOAL_STOP_HOOK_ORPHAN:-0}" == "1" ]]; then
    INCOMPLETE=$(find_orphan_incomplete_tasks "$WORKSPACE" | head -1 || true)
  fi
elif [[ -z "$WORKSPACE" ]]; then
  INCOMPLETE=$(pick_incomplete_goal "" || true)
fi
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

# Build followup via Kernel (preferred) or legacy driver
WORK_ORDER=""
if [[ -n "$STATE_FILE" && -f "$STATE_FILE" && -n "$PROJECT_ROOT" && -n "$TASK" ]]; then
  if [[ -x "$KERNEL" ]]; then
    WORK_ORDER=$("$KERNEL" next --state-file "$STATE_FILE" --task-dir "$TASK" --project-root "$PROJECT_ROOT" --format json 2>/dev/null || true)
  elif [[ -x "$DRIVER" ]]; then
    WORK_ORDER=$("$DRIVER" --state-file "$STATE_FILE" --task-dir "$TASK" --project-root "$PROJECT_ROOT" --format json 2>/dev/null || true)
  fi
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
