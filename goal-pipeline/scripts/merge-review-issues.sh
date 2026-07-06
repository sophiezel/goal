#!/bin/bash
# merge-review-issues.sh — Merge issues and emit review-fix-input.json
# Usage: merge-review-issues.sh --task-dir <path> --goal-json <review-goal.json> [--gf-json PATH] [--root-cause-json PATH]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR=""
GOAL_JSON=""
GF_JSON=""
ROOT_CAUSE=""
STATE_FILE=""
PROJECT_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --goal-json) GOAL_JSON="$2"; shift 2 ;;
    --gf-json) GF_JSON="$2"; shift 2 ;;
    --root-cause-json) ROOT_CAUSE="$2"; shift 2 ;;
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$TASK_DIR" && -n "$GOAL_JSON" ]] || { echo "Usage: $0 --task-dir <path> --goal-json <file>" >&2; exit 2; }
[[ "$TASK_DIR" != /* ]] && TASK_DIR="$(pwd)/$TASK_DIR"

RESOLVER="$SCRIPT_DIR/resolve-artifact-paths.py"
_RESOLVE_ARGS=(--task-dir "$TASK_DIR" --format shell --ensure-state)
[[ -n "$STATE_FILE" ]] && _RESOLVE_ARGS+=(--state-file "$STATE_FILE")
[[ -n "$PROJECT_ROOT" ]] && _RESOLVE_ARGS+=(--project-root "$PROJECT_ROOT")
eval "$(python3 "$RESOLVER" "${_RESOLVE_ARGS[@]}")"

GF_JSON="${GF_JSON:-$GOAL_EVIDENCE_DIR/review-gf.json}"
export GOAL_STATE_FILE="$STATE_FILE"
export GOAL_PROJECT_ROOT="$PROJECT_ROOT"
exec python3 "$SCRIPT_DIR/merge_review_core.py" "$REPO_TASK_DIR" "$GOAL_JSON" "${ROOT_CAUSE:-}"
