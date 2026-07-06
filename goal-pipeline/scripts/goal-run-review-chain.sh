#!/bin/bash
# goal-run-review-chain.sh — Atomic review script chain (dual-channel)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOAL_STATE_HOME="${GOAL_STATE_HOME:-$HOME/.goal-state}"

TASK_DIR=""
STATE_FILE=""
PROJECT_ROOT=""
MODE="${GOAL_REVIEW_MODE:-dual}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --task-dir <path> [--state-file PATH] [--project-root PATH] [--mode dual|goal]"
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
MERGE=$(resolve_script merge-review-issues.sh)

[[ -f "$ASSEMBLE" ]] || { echo "review-chain: assemble-review-packet.sh missing" >&2; exit 1; }
[[ -f "$REVIEW" ]] || { echo "review-chain: run-independent-review.sh missing" >&2; exit 1; }
[[ -f "$MERGE" ]] || { echo "review-chain: merge-review-issues.sh missing" >&2; exit 1; }

echo "review-chain [1/4] assemble-review-packet (artifact_mode=$ARTIFACT_MODE)"
bash "$ASSEMBLE" "${COMMON_ARGS[@]}"

echo "review-chain [2/4] run-independent-review --mode $MODE"
if [[ "${GOAL_REVIEW_FORCE_DETERMINISTIC:-}" == "1" ]]; then
  bash "$REVIEW" "${COMMON_ARGS[@]}" --mode goal --provider deterministic
else
  bash "$REVIEW" "${COMMON_ARGS[@]}" --mode "$MODE"
fi

GOAL_JSON="$GOAL_EVIDENCE_DIR/review-goal.json"
echo "review-chain [3/4] merge-review-issues -> $GOAL_JSON"
bash "$MERGE" "${COMMON_ARGS[@]}" --goal-json "$GOAL_JSON"

echo "review-chain [4/4] done — run gate --post review next"
exit 0
