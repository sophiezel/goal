#!/bin/bash
# goal-advance-stage.sh — Pipeline stage state machine for guazi-flow-goal
# Usage: goal-advance-stage.sh --state-file <path> [--task-dir <path>] [--project-root <path>] [--format json|text]
# Exit 0 = next stage available (stdout JSON)
# Exit 1 = pipeline complete (done)
# Exit 2 = blocked

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOAL_STATE_HOME="${GOAL_STATE_HOME:-$HOME/.goal-state}"

STATE_FILE=""
TASK_DIR=""
PROJECT_ROOT=""
FORMAT="json"

usage() {
  echo "Usage: $0 --state-file <path> [--task-dir <path>] [--project-root <path>] [--format json|text]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

resolve_abs() {
  local p="$1"
  local base="${2:-$(pwd)}"
  if [[ "$p" != /* ]]; then
    p="$base/$p"
  fi
  local dir base_name
  dir="$(cd "$(dirname "$p")" && pwd)"
  base_name="$(basename "$p")"
  echo "${dir}/${base_name}"
}

if [[ -n "$STATE_FILE" && "$STATE_FILE" != /* ]]; then
  STATE_FILE="$(resolve_abs "$STATE_FILE")"
fi

if [[ -n "$TASK_DIR" && "$TASK_DIR" != /* ]]; then
  local_root="${PROJECT_ROOT:-$(pwd)}"
  TASK_DIR="$(resolve_abs "$TASK_DIR" "$local_root")"
fi

if [[ -z "$PROJECT_ROOT" && -n "$STATE_FILE" && -f "$STATE_FILE" ]]; then
  PROJECT_ROOT="$(python3 - "$STATE_FILE" << 'PY'
import json, sys, os
state = json.load(open(sys.argv[1]))
root = state.get("project_root") or state.get("repo_root") or ""
if root:
    print(os.path.abspath(root))
PY
)"
fi

[[ -n "$PROJECT_ROOT" ]] || PROJECT_ROOT="$(pwd)"
if [[ "$PROJECT_ROOT" != /* ]]; then
  PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
fi

emit_json() {
  python3 - "$@" << 'PY'
import json, sys
next_stage, reason, blocked, required = sys.argv[1:5]
try:
    req = json.loads(required)
except Exception:
    req = []
print(json.dumps({
    "next_stage": next_stage,
    "blocked_reason": reason if reason else None,
    "blocked": blocked == "true",
    "required_commands": req,
}, ensure_ascii=False))
PY
}

emit() {
  local next="$1"
  local reason="${2:-}"
  local blocked="${3:-false}"
  local required="${4:-[]}"
  if [[ "$FORMAT" == "text" ]]; then
    echo "next_stage=$next"
    [[ -n "$reason" ]] && echo "blocked_reason=$reason"
    exit 0
  fi
  emit_json "$next" "$reason" "$blocked" "$required"
}

done_exit() {
  if [[ "$FORMAT" == "text" ]]; then
    echo "next_stage=done"
    exit 1
  fi
  echo '{"next_stage":"done","blocked_reason":null,"blocked":false,"required_commands":[]}'
  exit 1
}

blocked_exit() {
  local reason="$1"
  local next="${2:-blocked}"
  emit "$next" "$reason" "true" "[]"
  exit 2
}

handoff_ok() {
  local handoff="$1"
  [[ -f "$handoff" ]] || return 1
  python3 - "$handoff" << 'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    gate = d.get("gate") or {}
    sys.exit(0 if gate.get("passed_at") else 1)
except Exception:
    sys.exit(1)
PY
}

gate_passed_in_state() {
  local stage="$1"
  [[ -n "$STATE_FILE" && -f "$STATE_FILE" ]] || return 1
  python3 - "$STATE_FILE" "$stage" << 'PY'
import json, sys
state = json.load(open(sys.argv[1]))
stage = sys.argv[2]
stages = state.get("guazi_flow_stages") or {}
entry = stages.get(stage) or {}
gate = entry.get("gate") or {}
sys.exit(0 if gate.get("passed_at") else 1)
PY
}

if [[ -z "$STATE_FILE" || ! -f "$STATE_FILE" ]]; then
  emit "goal_engineering" "" "false" '["guazi-flow-goal Phase 1: create state.json"]'
  exit 0
fi

STATE_STATUS=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('status','active'))" 2>/dev/null || echo "active")

if [[ "$STATE_STATUS" == "complete" ]]; then
  done_exit
fi

if [[ "$STATE_STATUS" == "blocked" ]]; then
  REASON=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('failure_code','goal_blocked'))" 2>/dev/null || echo "goal_blocked")
  blocked_exit "$REASON" "blocked"
fi

if [[ "$STATE_STATUS" == "paused" ]]; then
  blocked_exit "goal_paused" "paused"
fi

if [[ -z "$TASK_DIR" ]]; then
  REL_TASK=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('guazi_flow_task',''))" 2>/dev/null || echo "")
  if [[ -n "$REL_TASK" ]]; then
    TASK_DIR="$(resolve_abs "$REL_TASK" "$PROJECT_ROOT")"
  fi
fi

INDEX=""
HANDOFF=""
EVIDENCE=""
if [[ -n "$TASK_DIR" && -d "$TASK_DIR" ]]; then
  INDEX="$TASK_DIR/index.md"
  HANDOFF="$TASK_DIR/handoff"
  EVIDENCE="$TASK_DIR/evidence"
fi

# plan
if [[ -z "$INDEX" || ! -f "$INDEX" ]]; then
  emit "plan" "" "false" '["gate-guazi-flow-stage.sh --stage plan --pre","guazi-flow-plan","gate --post plan"]'
  exit 0
fi

if ! handoff_ok "$HANDOFF/plan.json" && ! gate_passed_in_state "plan"; then
  emit "plan" "" "false" '["gate-guazi-flow-stage.sh --stage plan --post --mode guazi"]'
  exit 0
fi

# implement
if ! handoff_ok "$HANDOFF/implement.json" && ! gate_passed_in_state "implement"; then
  emit "implement" "" "false" '["guazi-flow-implement","gate-guazi-flow-stage.sh --stage implement --post --mode guazi"]'
  exit 0
fi

# runtime_smoke — gate required when script available
SMOKE_SCRIPT="$GOAL_STATE_HOME/scripts/runtime-smoke.sh"
[[ -x "$SMOKE_SCRIPT" ]] || SMOKE_SCRIPT="$SCRIPT_DIR/runtime-smoke.sh"
GATE_SCRIPT="$GOAL_STATE_HOME/scripts/gate-guazi-flow-stage.sh"
[[ -x "$GATE_SCRIPT" ]] || GATE_SCRIPT="$SCRIPT_DIR/gate-guazi-flow-stage.sh"
if [[ -x "$SMOKE_SCRIPT" ]]; then
  if [[ ! -f "$EVIDENCE/runtime-smoke.md" ]]; then
    emit "runtime_smoke" "" "false" '["runtime-smoke.sh --repo-root PROJECT --task-dir TASK","gate-guazi-flow-stage.sh --stage smoke --post"]'
    exit 0
  fi
  SMOKE_RESULT=$(python3 - "$EVIDENCE/runtime-smoke.md" << 'PYSR'
import re, sys
t = open(sys.argv[1]).read()
m = re.match(r"^---\s*
(.*?)
---", t, re.DOTALL)
if not m:
    print("unknown"); sys.exit(0)
for line in m.group(1).splitlines():
    if line.strip().startswith("result:"):
        print(line.split(":",1)[1].strip().strip(chr(34))); sys.exit(0)
print("unknown")
PYSR
)
  if [[ "$SMOKE_RESULT" == "skipped" ]]; then
    : # allow skip when no dev command
  elif ! handoff_ok "$HANDOFF/smoke.json" && ! gate_passed_in_state "smoke"; then
    emit "runtime_smoke" "smoke_gate_pending" "false" '["gate-guazi-flow-stage.sh --stage smoke --post --mode guazi"]'
    exit 0
  fi
fi

# review
REVIEW_MD="$EVIDENCE/review.md"
if [[ ! -f "$REVIEW_MD" ]] || ! handoff_ok "$HANDOFF/review.json"; then
  emit "review" "" "false" '["gate --pre review","guazi-flow-review","assemble-review-packet.sh","gate --post review"]'
  exit 0
fi

REVIEW_RESULT=$(python3 - "$REVIEW_MD" << 'PY' 2>/dev/null || echo "unknown"
import re, sys
text = open(sys.argv[1]).read()
m = re.match(r'^---\s*\n(.*?)\n---', text, re.DOTALL)
if not m:
    print("unknown"); sys.exit(0)
for line in m.group(1).splitlines():
    if line.strip().startswith("result:"):
        print(line.split(":", 1)[1].strip().strip('"').strip("'")); sys.exit(0)
print("unknown")
PY
)
if [[ "$REVIEW_RESULT" != "pass" ]]; then
  FIX_INPUT="$EVIDENCE/review-fix-input.json"
  if [[ -f "$FIX_INPUT" ]]; then
    NEXT=$(python3 -c "import json; print(json.dumps(json.load(open('$FIX_INPUT')).get('next_steps',[])))" 2>/dev/null || echo '[]')
    ACTION=$(python3 -c "import json; print(json.load(open('$FIX_INPUT')).get('action',''))" 2>/dev/null || echo "")
    emit "review" "review_not_pass" "false" "$NEXT"
  else
    emit "review" "review_not_pass" "false" '["read evidence/review-fix-input.json after merge-review-issues.sh","fix within write_set","run-independent-review.sh","merge-review-issues.sh","gate --post review"]'
  fi
  exit 0
fi

# complete
if ! grep -qE 'current_stage:\s*complete' "$INDEX" 2>/dev/null || ! handoff_ok "$HANDOFF/complete.json"; then
  emit "complete" "" "false" '["guazi-flow-complete","gate-guazi-flow-stage.sh --stage complete --post --mode guazi"]'
  exit 0
fi

VERIFY_BIN="$GOAL_STATE_HOME/scripts/verify.sh"
[[ -x "$VERIFY_BIN" ]] || VERIFY_BIN="$SCRIPT_DIR/verify.sh"
if [[ -x "$VERIFY_BIN" && -n "$TASK_DIR" ]]; then
  if "$VERIFY_BIN" "$TASK_DIR" json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('completion_condition_met') else 1)" 2>/dev/null; then
    done_exit
  fi
fi

if handoff_ok "$HANDOFF/complete.json"; then
  done_exit
fi

emit "complete" "verify_incomplete" "false" "[\"verify.sh $TASK_DIR\"]"
exit 0
