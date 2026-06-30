#!/bin/bash
# validate-pipeline-chain.sh — Validate handoff chain, artifact freshness, stage order
# Usage: validate-pipeline-chain.sh --task-dir <path> [--state-file PATH]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR=""
STATE_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --state-file) STATE_FILE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

[[ -n "$TASK_DIR" ]] || { echo '{"ok":false,"errors":["--task-dir required"]}' >&2; exit 2; }
[[ "$TASK_DIR" != /* ]] && TASK_DIR="$(pwd)/$TASK_DIR"
TASK_DIR="$(cd "$TASK_DIR" && pwd)"

exec python3 "$SCRIPT_DIR/validate-pipeline-chain.py" --task-dir "$TASK_DIR" ${STATE_FILE:+--state-file "$STATE_FILE"}
