#!/usr/bin/env bash
# argus-enrich-plan.sh — Plan post hook: rule-based L10 manifest (v1, no fe-argus LLM)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR=""
HANDOFF_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --handoff-dir) HANDOFF_DIR="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --task-dir PATH [--handoff-dir PATH]"
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$TASK_DIR" ]] || { echo "argus-enrich-plan: --task-dir required" >&2; exit 2; }
[[ "$TASK_DIR" != /* ]] && TASK_DIR="$(pwd)/$TASK_DIR"
TASK_DIR="$(cd "$TASK_DIR" && pwd)"
ARGS=(--task-dir "$TASK_DIR")
[[ -n "$HANDOFF_DIR" ]] && ARGS+=(--handoff-dir "$HANDOFF_DIR")
python3 "$SCRIPT_DIR/argus_enrich_plan.py" "${ARGS[@]}" --format text
