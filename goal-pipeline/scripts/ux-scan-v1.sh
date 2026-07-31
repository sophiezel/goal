#!/usr/bin/env bash
# ux-scan-v1.sh — Implement post hook: UX-D1/D2/D5 heuristics on write_set (warn-only)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR=""
REPO_ROOT=""
STATE_FILE=""
PROJECT_ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --repo-root) REPO_ROOT="$2"; shift 2 ;;
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --task-dir PATH [--repo-root PATH] [--state-file PATH] [--project-root PATH]"
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$TASK_DIR" ]] || { echo "ux-scan-v1: --task-dir required" >&2; exit 2; }
[[ "$TASK_DIR" != /* ]] && TASK_DIR="$(pwd)/$TASK_DIR"
TASK_DIR="$(cd "$TASK_DIR" && pwd)"
ARGS=(--task-dir "$TASK_DIR")
[[ -n "$REPO_ROOT" ]] && ARGS+=(--repo-root "$REPO_ROOT")
[[ -n "$STATE_FILE" ]] && ARGS+=(--state-file "$STATE_FILE")
[[ -n "$PROJECT_ROOT" ]] && ARGS+=(--project-root "$PROJECT_ROOT")
python3 "$SCRIPT_DIR/ux_scan_v1.py" "${ARGS[@]}" --format text
