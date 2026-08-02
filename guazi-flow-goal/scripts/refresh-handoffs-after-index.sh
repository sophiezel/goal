#!/bin/bash
# refresh-handoffs-after-index.sh — Guazi runtime fork (v1.4): uses guazi-gate-stage.sh
# Usage: refresh-handoffs-after-index.sh --task-dir PATH --state-file PATH --project-root PATH
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_HOME="${GUAZI_STATE_HOME:-${GOAL_STATE_HOME:-${GUAZI_HOME:-$HOME/.guazi-flow}/state}}"
GOAL_STATE_HOME="${GOAL_STATE_HOME:-$STATE_HOME}"
GATE="$STATE_HOME/scripts/guazi-gate-stage.sh"
GATE_MODE_FLAG=(--mode guazi)
[[ -x "$GATE" ]] || { GATE="$STATE_HOME/scripts/gate-goal-stage.sh"; GATE_MODE_FLAG=(); }
[[ -x "$GATE" ]] || { GATE="$SCRIPT_DIR/guazi-gate-stage.sh"; GATE_MODE_FLAG=(--mode guazi); }
[[ -x "$GATE" ]] || { GATE="$SCRIPT_DIR/gate-goal-stage.sh"; GATE_MODE_FLAG=(); }
ASSEMBLE="$STATE_HOME/scripts/assemble-review-packet.sh"
[[ -x "$ASSEMBLE" ]] || ASSEMBLE="$SCRIPT_DIR/assemble-review-packet.sh"
HASH_PY="$SCRIPT_DIR/index_contract_hash.py"
[[ -f "$HASH_PY" ]] || HASH_PY="$STATE_HOME/scripts/index_contract_hash.py"

TASK_DIR=""
STATE_FILE=""
PROJECT_ROOT=""
FORCE_CASCADE=""
FORMAT="json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --cascade) FORCE_CASCADE="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --task-dir PATH --state-file PATH --project-root PATH [--cascade plan|implement|auto]"
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$TASK_DIR" && -n "$PROJECT_ROOT" ]] || {
  echo '{"error":"--task-dir and --project-root required"}' >&2
  exit 2
}
[[ "$TASK_DIR" != /* ]] && TASK_DIR="$PROJECT_ROOT/$TASK_DIR"
TASK_DIR="$(cd "$TASK_DIR" && pwd)"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

RESOLVER="$SCRIPT_DIR/resolve-artifact-paths.py"
_RESOLVE_ARGS=(--task-dir "$TASK_DIR" --format shell --ensure-state)
[[ -n "$STATE_FILE" ]] && _RESOLVE_ARGS+=(--state-file "$STATE_FILE")
[[ -n "$PROJECT_ROOT" ]] && _RESOLVE_ARGS+=(--project-root "$PROJECT_ROOT")
eval "$(python3 "$RESOLVER" "${_RESOLVE_ARGS[@]}")"

INDEX="$REPO_TASK_DIR/index.md"
PLAN_JSON="$HANDOFF_DIR/plan.json"
[[ -f "$INDEX" ]] || { echo '{"error":"index.md missing"}' >&2; exit 1; }
[[ -f "$PLAN_JSON" ]] || { echo '{"error":"plan.json missing — run gate --post plan first"}' >&2; exit 1; }
[[ -f "$HASH_PY" ]] || { echo '{"error":"index_contract_hash.py missing"}' >&2; exit 1; }

FRESH=$(python3 "$HASH_PY" --json "$INDEX" "$PLAN_JSON")
CONTRACT_CHANGED=$(echo "$FRESH" | python3 -c "import json,sys; print(json.load(sys.stdin).get('contract_changed', False))")
EXEC_CHANGED=$(echo "$FRESH" | python3 -c "import json,sys; print(json.load(sys.stdin).get('execution_changed', False))")
FRESH_OK=$(echo "$FRESH" | python3 -c "import json,sys; print(json.load(sys.stdin).get('fresh', True))")
SHRINK_ONLY=$(echo "$FRESH" | python3 -c "import json,sys; print(json.load(sys.stdin).get('write_set_shrink_only', False))")

CASCADE="none"
SKIP_ASSEMBLE_IF_HASH_SAME=0
if [[ -n "$FORCE_CASCADE" && "$FORCE_CASCADE" != "auto" ]]; then
  CASCADE="$FORCE_CASCADE"
  if [[ "$CASCADE" == "plan" && "$CONTRACT_CHANGED" != "True" && "$EXEC_CHANGED" == "True" ]]; then
    echo "refresh-handoffs: REJECT cascade=plan when only execution record changed — demote to implement" >&2
    CASCADE="implement"
  fi
  if [[ "$CASCADE" == "plan" && "$SHRINK_ONLY" == "True" ]]; then
    echo "refresh-handoffs: REJECT cascade=plan for write_set shrink-only — demote to implement" >&2
    CASCADE="implement"
    SKIP_ASSEMBLE_IF_HASH_SAME=1
  fi
elif [[ "$CONTRACT_CHANGED" == "True" ]]; then
  CASCADE="plan"
elif [[ "$SHRINK_ONLY" == "True" ]]; then
  echo "refresh-handoffs: write_set shrink-only → implement (keep review if code hash unchanged)" >&2
  CASCADE="implement"
  SKIP_ASSEMBLE_IF_HASH_SAME=1
elif [[ "$EXEC_CHANGED" == "True" || "$FRESH_OK" != "True" ]]; then
  CASCADE="implement"
else
  if [[ ! -f "$HANDOFF_DIR/review-packet.json" ]]; then
    CASCADE="packet"
  fi
fi

COMMON_GATE=(--task-dir "$REPO_TASK_DIR" --project-root "$PROJECT_ROOT")
[[ -n "$STATE_FILE" ]] && COMMON_GATE+=(--state-file "$STATE_FILE")
COMMON_ASM=(--task-dir "$REPO_TASK_DIR" --project-root "$PROJECT_ROOT")
[[ -n "$STATE_FILE" ]] && COMMON_ASM+=(--state-file "$STATE_FILE")

ACTIONS=()
case "$CASCADE" in
  plan)
    echo "refresh-handoffs: contract changed → gate --post plan + implement + assemble" >&2
    "$GATE" "${GATE_MODE_FLAG[@]}" "${COMMON_GATE[@]}" --stage plan --post
    ACTIONS+=("gate_post_plan")
    "$GATE" "${GATE_MODE_FLAG[@]}" "${COMMON_GATE[@]}" --stage implement --post
    ACTIONS+=("gate_post_implement")
    "$ASSEMBLE" "${COMMON_ASM[@]}" >/dev/null
    ACTIONS+=("assemble_review_packet")
    ;;
  implement)
    echo "refresh-handoffs: execution record only → gate --post implement + assemble" >&2
    HAS_CONTRACT=$(python3 -c "import json; print('1' if json.load(open('$PLAN_JSON')).get('index_contract_hash') else '0')" 2>/dev/null || echo 0)
    if [[ "$HAS_CONTRACT" != "1" ]]; then
      echo "refresh-handoffs: migrating legacy plan.json to index_contract_hash" >&2
      "$GATE" "${GATE_MODE_FLAG[@]}" "${COMMON_GATE[@]}" --stage plan --post
      ACTIONS+=("gate_post_plan_migrate")
    fi
    if [[ "$SHRINK_ONLY" == "True" ]]; then
      python3 - "$INDEX" "$PLAN_JSON" "$HASH_PY" << 'PYSYNC'
import json, sys, importlib.util
index_path, plan_path, helper = sys.argv[1], sys.argv[2], sys.argv[3]
spec = importlib.util.spec_from_file_location("ich", helper)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
text = open(index_path, encoding="utf-8").read()
new_ws = mod._extract_write_set_paths_from_index(text)
plan = json.load(open(plan_path, encoding="utf-8"))
if new_ws:
    plan["write_set"] = new_ws
    plan["write_set_shrink_synced"] = True
    plan["index_contract_hash"] = mod.index_contract_hash(index_path)
    plan["index_execution_tail_hash"] = mod.index_execution_tail_hash(index_path)
    with open(plan_path, "w", encoding="utf-8") as f:
        json.dump(plan, f, indent=2, ensure_ascii=False)
        f.write("\n")
PYSYNC
      ACTIONS+=("sync_write_set_shrink")
    fi
    "$GATE" "${GATE_MODE_FLAG[@]}" "${COMMON_GATE[@]}" --stage implement --post
    ACTIONS+=("gate_post_implement")
    DO_ASSEMBLE=1
    if [[ "$SKIP_ASSEMBLE_IF_HASH_SAME" == "1" && -f "$HANDOFF_DIR/review-packet.json" && -f "$GOAL_EVIDENCE_DIR/review-run.json" ]]; then
      SAME=$(python3 - "$HANDOFF_DIR/review-packet.json" "$GOAL_EVIDENCE_DIR/verification-oracle.json" << 'PYH' 2>/dev/null || echo 0
import json, sys
pkt = json.load(open(sys.argv[1], encoding="utf-8"))
uvo = {}
try:
    uvo = json.load(open(sys.argv[2], encoding="utf-8"))
except Exception:
    pass
old = pkt.get("code_subject_hash") or pkt.get("candidate_diff_hash") or ""
new = uvo.get("code_subject_hash") or uvo.get("candidate_diff_hash") or ""
print("1" if old and new and old == new else "0")
PYH
)
      if [[ "$SAME" == "1" ]]; then
        echo "refresh-handoffs: skip assemble — code_subject_hash unchanged (preserve review)" >&2
        DO_ASSEMBLE=0
        ACTIONS+=("skip_assemble_preserve_review")
      fi
    fi
    if [[ "$DO_ASSEMBLE" == "1" ]]; then
      "$ASSEMBLE" "${COMMON_ASM[@]}" >/dev/null
      ACTIONS+=("assemble_review_packet")
    fi
    ;;
  packet)
    echo "refresh-handoffs: assemble review packet only" >&2
    "$ASSEMBLE" "${COMMON_ASM[@]}" >/dev/null
    ACTIONS+=("assemble_review_packet")
    ;;
  none)
    echo "refresh-handoffs: already fresh — no cascade needed" >&2
    ;;
  *)
    echo "refresh-handoffs: unknown cascade=$CASCADE" >&2
    exit 2
    ;;
esac

OUT=$(python3 - "$FRESH" "$CASCADE" << 'PY'
import json, sys
fresh = json.loads(sys.argv[1])
cascade = sys.argv[2]
print(json.dumps({
    "ok": True,
    "cascade": cascade,
    "freshness": fresh,
    "note": {
        "plan": "contract changed — mini-replan via gate --post plan",
        "implement": "execution record only — do NOT mini-replan",
        "packet": "packet missing — assembled",
        "none": "already fresh",
    }.get(cascade, ""),
}, ensure_ascii=False))
PY
)

mkdir -p "$GOAL_EVIDENCE_DIR"
python3 - "$GOAL_EVIDENCE_DIR/refresh-handoffs-result.json" "$OUT" << 'PYW'
import json, sys
path, payload = sys.argv[1], sys.argv[2]
open(path, "w", encoding="utf-8").write(payload if payload.endswith("\n") else payload + "\n")
PYW

if [[ "$FORMAT" == "json" ]]; then
  echo "$OUT"
else
  echo "cascade=$CASCADE"
  echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print('fresh=', d['freshness'].get('fresh')); print(d.get('note',''))"
fi
exit 0
