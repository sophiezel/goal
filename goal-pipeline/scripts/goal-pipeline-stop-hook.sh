#!/bin/bash
# goal-pipeline-stop-hook.sh — Cursor stop hook: block early exit when pipeline incomplete
# Installed to ~/.cursor/hooks/ and ~/.goal-state/scripts/
# Exit 0 always; outputs followup_message JSON on stdout when pipeline incomplete

set -euo pipefail

GOAL_STATE_HOME="${GOAL_STATE_HOME:-$HOME/.goal-state}"
GATE="$GOAL_STATE_HOME/scripts/gate-guazi-flow-stage.sh"
ADVANCE="$GOAL_STATE_HOME/scripts/goal-advance-stage.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -x "$GATE" ]] || GATE="$SCRIPT_DIR/gate-guazi-flow-stage.sh"
[[ -x "$ADVANCE" ]] || ADVANCE="$SCRIPT_DIR/goal-advance-stage.sh"

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
root = st.get("project_root") or st.get("repo_root") or ""
if ws and root and os.path.normpath(root) != os.path.normpath(ws):
    sys.exit(0)
task = st.get("guazi_flow_task") or ""
print(json.dumps({"state_file": sf, "task": task, "objective": st.get("objective","")[:80]}))
PY
  done
}

# Also detect incomplete guazi-flow index in workspace without state
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
  INCOMPLETE=$( { find_active_states "$WORKSPACE"; find_incomplete_tasks "$WORKSPACE"; } | head -1 )
fi

if [[ -z "$INCOMPLETE" ]]; then
  INCOMPLETE=$(find_active_states "" | head -1)
fi

if [[ -z "$INCOMPLETE" ]]; then
  exit 0
fi

STATE_FILE=$(echo "$INCOMPLETE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('state_file',''))")
TASK=$(echo "$INCOMPLETE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('task',''))")
OBJECTIVE=$(echo "$INCOMPLETE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('objective',''))")

NEXT="unknown"
if [[ -x "$ADVANCE" && -n "$STATE_FILE" && -f "$STATE_FILE" ]]; then
  ARGS=(--state-file "$STATE_FILE" --format json)
  [[ -n "$TASK" && -n "$WORKSPACE" ]] && ARGS+=(--task-dir "$TASK" --project-root "$WORKSPACE")
  OUT=$("$ADVANCE" "${ARGS[@]}" 2>/dev/null) || true
  NEXT=$(echo "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('next_stage','unknown'))" 2>/dev/null || echo "unknown")
elif [[ -n "$TASK" ]]; then
  NEXT="review"
fi

if [[ "$NEXT" == "done" ]]; then
  exit 0
fi

MSG="Pipeline incomplete (next_stage=$NEXT). Continue guazi-flow-goal: load guazi-flow-$NEXT SKILL.md and run gate --pre/$NEXT. Objective: $OBJECTIVE"
python3 - "$MSG" << 'PY'
import json, sys
print(json.dumps({"followup_message": sys.argv[1]}))
PY
exit 0
