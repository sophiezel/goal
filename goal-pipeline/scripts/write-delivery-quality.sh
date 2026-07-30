#!/usr/bin/env bash
# write-delivery-quality.sh — complete 阶段产出 delivery-quality.json（Port Spec v2）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASK_DIR=""
STATE_FILE=""
PROJECT_ROOT=""
OUTPUT=""
PIPELINE_ID="${GOAL_PIPELINE_ID:-guazi-flow-goal}"

usage() { echo "Usage: $0 --task-dir <path> [--state-file <path>] [--project-root <path>] [--output <path>] [--pipeline-id goal-pipeline|guazi-flow-goal]"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --pipeline-id) PIPELINE_ID="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done
[[ -n "$TASK_DIR" ]] || usage

_RESOLVE=(python3 "$SCRIPT_DIR/resolve-artifact-paths.py" --task-dir "$TASK_DIR" --format json --ensure-state)
[[ -n "$STATE_FILE" ]] && _RESOLVE+=(--state-file "$STATE_FILE")
[[ -n "$PROJECT_ROOT" ]] && _RESOLVE+=(--project-root "$PROJECT_ROOT")
PATHS_JSON=$("${_RESOLVE[@]}")
HANDOFF=$(echo "$PATHS_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['handoff_dir'])")
GOAL_EVIDENCE=$(echo "$PATHS_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['goal_evidence_dir'])")
REPO_TASK=$(echo "$PATHS_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['repo_task_dir'])")

OUTPUT="${OUTPUT:-$HANDOFF/delivery-quality.json}"

PYTHONPATH="$KERNEL_ROOT" python3 "$KERNEL_ROOT/kernel/metrics/delivery_report.py" \
  --handoff "$HANDOFF" \
  --goal-evidence "$GOAL_EVIDENCE" \
  --repo-task "$REPO_TASK" \
  --output "$OUTPUT" \
  --pipeline-id "$PIPELINE_ID" \
  ${STATE_FILE:+--state-file "$STATE_FILE"}
