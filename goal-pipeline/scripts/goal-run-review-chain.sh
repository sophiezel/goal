#!/bin/bash
# goal-run-review-chain.sh — Atomic review script chain (unified review)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOAL_STATE_HOME="${GOAL_STATE_HOME:-$HOME/.goal-state}"

TASK_DIR=""
STATE_FILE=""
PROJECT_ROOT=""
MODE="${GOAL_REVIEW_MODE:-unified}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --task-dir <path> [--state-file PATH] [--project-root PATH] [--mode unified|goal]"
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$TASK_DIR" ]] || { echo "review-chain: --task-dir required" >&2; exit 2; }
[[ "$TASK_DIR" != /* ]] && TASK_DIR="$(pwd)/$TASK_DIR"
TASK_DIR="$(cd "$TASK_DIR" && pwd)"

resolve_script() {
  local name="$1"
  local p="$GOAL_STATE_HOME/scripts/$name"
  [[ -f "$p" ]] || p="$SCRIPT_DIR/$name"
  echo "$p"
}

RESOLVER=$(resolve_script resolve-artifact-paths.py)
_RESOLVE_ARGS=(--task-dir "$TASK_DIR" --format shell --ensure-state)
[[ -n "$STATE_FILE" ]] && _RESOLVE_ARGS+=(--state-file "$STATE_FILE")
[[ -n "$PROJECT_ROOT" ]] && _RESOLVE_ARGS+=(--project-root "$PROJECT_ROOT")
eval "$(python3 "$RESOLVER" "${_RESOLVE_ARGS[@]}")"

COMMON_ARGS=(--task-dir "$REPO_TASK_DIR")
[[ -n "$STATE_FILE" ]] && COMMON_ARGS+=(--state-file "$STATE_FILE")
[[ -n "$PROJECT_ROOT" ]] && COMMON_ARGS+=(--project-root "$PROJECT_ROOT")
[[ -n "$GOAL_STATE_FILE" && -z "$STATE_FILE" ]] && COMMON_ARGS+=(--state-file "$GOAL_STATE_FILE")

ASSEMBLE=$(resolve_script assemble-review-packet.sh)
REVIEW=$(resolve_script run-independent-review.sh)
GUARD=$(resolve_script review-channel-guard.py)
MERGE=$(resolve_script merge-review-issues.sh)

[[ -f "$ASSEMBLE" ]] || { echo "review-chain: assemble-review-packet.sh missing" >&2; exit 1; }
[[ -f "$REVIEW" ]] || { echo "review-chain: run-independent-review.sh missing" >&2; exit 1; }
[[ -f "$MERGE" ]] || { echo "review-chain: merge-review-issues.sh missing" >&2; exit 1; }

echo "review-chain [1/4] assemble-review-packet (artifact_mode=$ARTIFACT_MODE)"
bash "$ASSEMBLE" "${COMMON_ARGS[@]}"

echo "review-chain [2/4] run-independent-review --mode $MODE"
[[ -f "$GUARD" ]] || { echo "review-chain: review-channel-guard.py missing" >&2; exit 1; }

# Fail-fast: 0 usable review channels OR configured-but-unreachable → skip L2 timeout storm.
CHANNEL_JSON=$(python3 "$GUARD" --resolve --provider "" --model "" --force-det 0 --mode "$MODE" --format json 2>/dev/null || echo '{"has_candidates":false}')
HAS_CH=$(echo "$CHANNEL_JSON" | python3 -c "import json,sys; print('1' if json.load(sys.stdin).get('has_candidates') else '0')" 2>/dev/null || echo 0)
UNREACH=$(echo "$CHANNEL_JSON" | python3 -c "import json,sys; print('1' if json.load(sys.stdin).get('configured_but_unreachable') else '0')" 2>/dev/null || echo 0)

if [[ "${GOAL_REVIEW_FORCE_DETERMINISTIC:-}" == "1" ]]; then
  python3 "$GUARD" --check --force-det 1 --provider deterministic
  bash "$REVIEW" "${COMMON_ARGS[@]}" --mode goal --provider deterministic
elif [[ "$UNREACH" == "1" ]]; then
  echo "review-chain: WARN — review APIs configured but unreachable (short probe); skipping cascade" >&2
  echo "review-chain: use GOAL_REVIEW_CURSOR_TASK=1 / Cursor Task — do NOT treat as business not_pass" >&2
  mkdir -p "$GOAL_EVIDENCE_DIR"
  python3 - "$GOAL_EVIDENCE_DIR/review-channel-degraded.json" <<'PY'
import json, sys
from datetime import datetime, timezone
path = sys.argv[1]
open(path, "w", encoding="utf-8").write(json.dumps({
    "separation": "blocked",
    "review_mode": "channel_unreachable",
    "reason": "review_channel_unreachable",
    "suggested_action": "switch_to_cursor_task",
    "checked_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}, ensure_ascii=False, indent=2) + "\n")
PY
  export REVIEW_CHANNEL_UNREACHABLE=1
  export GOAL_REVIEW_CURSOR_TASK_HINT=1
  # Resolve shell exports so run-independent-review sees UNREACHABLE (json resolve doesn't export).
  eval "$(python3 "$GUARD" --resolve --provider "" --model "" --force-det 0 --mode "$MODE" 2>/dev/null || true)"
  export REVIEW_CHANNEL_UNREACHABLE=1
  bash "$REVIEW" "${COMMON_ARGS[@]}" --mode "$MODE"
elif [[ "$HAS_CH" != "1" ]]; then
  echo "review-chain: WARN — 0 usable review channels; skipping L2 API cascade (separation=degraded)" >&2
  echo "review-chain: using deterministic_scope_only — confidence lowered; not a full independent review" >&2
  mkdir -p "$GOAL_EVIDENCE_DIR"
  python3 - "$GOAL_EVIDENCE_DIR/review-channel-degraded.json" <<'PY'
import json, sys
from datetime import datetime, timezone
path = sys.argv[1]
open(path, "w", encoding="utf-8").write(json.dumps({
    "separation": "degraded",
    "review_mode": "deterministic_scope_only",
    "reason": "zero_usable_review_channels",
    "checked_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}, ensure_ascii=False, indent=2) + "\n")
PY
  export GOAL_REVIEW_FORCE_DETERMINISTIC=1
  bash "$REVIEW" "${COMMON_ARGS[@]}" --mode goal --provider deterministic
else
  bash "$REVIEW" "${COMMON_ARGS[@]}" --mode "$MODE"
fi

UNIFIED_JSON="$GOAL_EVIDENCE_DIR/review-unified.json"
echo "review-chain [3/4] merge-review-issues -> $UNIFIED_JSON"
bash "$MERGE" "${COMMON_ARGS[@]}" --unified-json "$UNIFIED_JSON"

echo "review-chain [4/4] done — run gate --post review next"
exit 0
