#!/bin/bash
# goal-pipeline-session-start-hook.sh — Lightweight active-goal reminder (read-only)
set -euo pipefail
GOAL_STATE_HOME="${GOAL_STATE_HOME:-$HOME/.goal-state}"
INPUT=$(cat)

# Auto-sync install repo + runtime scripts (non-blocking), throttled by HEAD/mtime.
# Skip when last sync < 10min AND install-repo HEAD unchanged (GOAL_SYNC_THROTTLE_SEC).
SYNC="${GOAL_STATE_HOME}/scripts/sync-install-repo.sh"
STAMP="${GOAL_STATE_HOME}/.last-session-sync"
REPO_DIR="${GOAL_PIPELINE_REPO:-$HOME/.goal-pipeline-repo}"
THROTTLE_SEC="${GOAL_SYNC_THROTTLE_SEC:-600}"
if [[ -x "$SYNC" ]]; then
  NEED_SYNC=1
  NOW=$(date +%s)
  CUR_HEAD=""
  [[ -d "$REPO_DIR/.git" ]] && CUR_HEAD=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo "")
  if [[ -f "$STAMP" ]]; then
    LAST_TS=$(awk 'NR==1{print $1}' "$STAMP" 2>/dev/null || echo 0)
    LAST_HEAD=$(awk 'NR==1{print $2}' "$STAMP" 2>/dev/null || echo "")
    if [[ -n "$LAST_TS" && "$LAST_TS" =~ ^[0-9]+$ ]]; then
      AGE=$((NOW - LAST_TS))
      if [[ "$AGE" -lt "$THROTTLE_SEC" && -n "$CUR_HEAD" && "$CUR_HEAD" == "$LAST_HEAD" ]]; then
        NEED_SYNC=0
      fi
    fi
  fi
  if [[ "$NEED_SYNC" == "1" ]]; then
    (
      bash "$SYNC" --quiet >/dev/null 2>&1 || true
      HEAD_AFTER=""
      [[ -d "$REPO_DIR/.git" ]] && HEAD_AFTER=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo "")
      printf '%s %s\n' "$(date +%s)" "${HEAD_AFTER:-$CUR_HEAD}" > "$STAMP" 2>/dev/null || true
    ) &
  fi
fi

WORKSPACE=$(echo "$INPUT" | python3 -c "
import json,sys
try: d=json.load(sys.stdin)
except: print(''); sys.exit(0)
for k in ('workspace_roots','cwd'):
    v=d.get(k)
    if isinstance(v,list) and v: print(v[0]); sys.exit(0)
    if isinstance(v,str) and v: print(v); sys.exit(0)
print('')
" 2>/dev/null || echo "")

[[ -d "$GOAL_STATE_HOME/projects" ]] || exit 0
FOUND=""
if [[ -n "$WORKSPACE" ]]; then
  FOUND=$(find "$GOAL_STATE_HOME/projects" -name state.json 2>/dev/null | while read -r sf; do
    python3 - "$sf" "$WORKSPACE" << 'PY'
import json,sys,os
sf,ws=sys.argv[1],sys.argv[2]
try: st=json.load(open(sf))
except: sys.exit(0)
if st.get("status") not in ("active","blocked"): sys.exit(0)
root=st.get("project_root") or ""
if root and os.path.normpath(root)==os.path.normpath(ws):
    print(sf); sys.exit(0)
PY
  done | head -1)
fi
[[ -z "$FOUND" ]] && exit 0
python3 -c 'import json; print(json.dumps({"message":"Active goal detected — run goal-stage-driver.sh first (see guazi-flow-goal Turn Protocol)"}))'
exit 0
