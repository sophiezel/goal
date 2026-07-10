#!/usr/bin/env bash
# verification-oracle.sh — Unified Verification Oracle (UVO): single L1 test+lint+build gate
# Usage: verification-oracle.sh --task-dir <path> [--repo-root <path>] [--state-file <path>] [--tier standard|strict] [--check-freshness]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR=""
REPO_ROOT=""
STATE_FILE=""
PROJECT_ROOT=""
TIER="standard"
ORACLE_MODE=""
CHECK_FRESHNESS=0
SKIP_BUILD=0

usage() {
  echo "Usage: $0 --task-dir <path> [--repo-root <path>] [--state-file <path>] [--tier standard|strict] [--oracle-mode related_union|full_suite] [--check-freshness]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --repo-root) REPO_ROOT="$2"; shift 2 ;;
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --tier) TIER="$2"; shift 2 ;;
    --oracle-mode) ORACLE_MODE="$2"; shift 2 ;;
    --check-freshness) CHECK_FRESHNESS=1; shift ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$TASK_DIR" ]] || usage

if [[ "$TASK_DIR" != /* ]]; then
  TASK_DIR="$(pwd)/$TASK_DIR"
fi
TASK_DIR="$(cd "$TASK_DIR" && pwd)"

RESOLVER="$SCRIPT_DIR/resolve-artifact-paths.py"
_RESOLVE_ARGS=(--task-dir "$TASK_DIR" --format shell --ensure-state)
[[ -n "$STATE_FILE" ]] && _RESOLVE_ARGS+=(--state-file "$STATE_FILE")
[[ -n "$PROJECT_ROOT" ]] && _RESOLVE_ARGS+=(--project-root "$PROJECT_ROOT")
eval "$(python3 "$RESOLVER" "${_RESOLVE_ARGS[@]}")"

export GOAL_HANDOFF_DIR="$HANDOFF_DIR"
export GOAL_EVIDENCE_DIR="$GOAL_EVIDENCE_DIR"

REPO_ROOT="${REPO_ROOT:-${GIT_ROOT:-$PROJECT_ROOT}}"
REPO_ROOT="${REPO_ROOT:-$(pwd)}"

ARGS=(--task-dir "$TASK_DIR" --repo-root "$REPO_ROOT" --tier "$TIER" --json)
[[ -n "$ORACLE_MODE" ]] && ARGS+=(--oracle-mode "$ORACLE_MODE")
[[ "$SKIP_BUILD" -eq 1 ]] && ARGS+=(--skip-build)
[[ -n "$GOAL_EVIDENCE_DIR" ]] && ARGS+=(--evidence-dir "$GOAL_EVIDENCE_DIR")
[[ "$CHECK_FRESHNESS" -eq 1 ]] && ARGS+=(--check-freshness)

python3 "$SCRIPT_DIR/verification_oracle_core.py" "${ARGS[@]}"
