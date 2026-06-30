#!/bin/bash
# merge-review-issues.sh — Merge issues and emit review-fix-input.json
# Usage: merge-review-issues.sh --task-dir <path> --goal-json <review-goal.json> [--gf-json PATH] [--root-cause-json PATH]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR=""
GOAL_JSON=""
GF_JSON=""
ROOT_CAUSE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --goal-json) GOAL_JSON="$2"; shift 2 ;;
    --gf-json) GF_JSON="$2"; shift 2 ;;
    --root-cause-json) ROOT_CAUSE="$2"; shift 2 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$TASK_DIR" && -n "$GOAL_JSON" ]] || { echo "Usage: $0 --task-dir <path> --goal-json <file>" >&2; exit 2; }
[[ "$TASK_DIR" != /* ]] && TASK_DIR="$(pwd)/$TASK_DIR"
GF_JSON="${GF_JSON:-$TASK_DIR/evidence/review-gf.json}"

exec python3 "$SCRIPT_DIR/merge_review_core.py" "$TASK_DIR" "$GOAL_JSON" "${ROOT_CAUSE:-}"
