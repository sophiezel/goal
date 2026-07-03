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

resolve() {
  local name="$1"
  local p="$GOAL_STATE_HOME/scripts/$name"
  [[ -x "$p" ]] || p="$SCRIPT_DIR/$name"
  echo "$p"
}

ASSEMBLE=$(resolve assemble-review-packet.sh)
REVIEW=$(resolve run-independent-review.sh)
MERGE=$(resolve merge-review-issues.sh)

[[ -x "$ASSEMBLE" ]] || { echo "review-chain: assemble-review-packet.sh missing" >&2; exit 1; }
[[ -x "$REVIEW" ]] || { echo "review-chain: run-independent-review.sh missing" >&2; exit 1; }
[[ -x "$MERGE" ]] || { echo "review-chain: merge-review-issues.sh missing" >&2; exit 1; }

echo "review-chain [1/4] assemble-review-packet"
"$ASSEMBLE" --task-dir "$TASK_DIR"

echo "review-chain [2/4] run-independent-review --mode $MODE"
if [[ "${GOAL_REVIEW_FORCE_DETERMINISTIC:-}" == "1" ]]; then
  "$REVIEW" --task-dir "$TASK_DIR" --mode goal --provider deterministic
else
  "$REVIEW" --task-dir "$TASK_DIR" --mode "$MODE"
fi

echo "review-chain [3/4] merge-review-issues"
"$MERGE" --task-dir "$TASK_DIR" --goal-json "$TASK_DIR/evidence/review-goal.json"

echo "review-chain [4/4] done — run gate --post review next"
exit 0
