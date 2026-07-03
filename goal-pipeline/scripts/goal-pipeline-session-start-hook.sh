#!/bin/bash
# goal-pipeline-session-start-hook.sh — Lightweight active-goal reminder (read-only)
set -euo pipefail
GOAL_STATE_HOME="${GOAL_STATE_HOME:-$HOME/.goal-state}"
INPUT=$(cat)
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
