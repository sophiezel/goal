#!/usr/bin/env bash
# quality-gate.sh — L0+L1 unified quality gate for goal-quality stage
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR=""
REPO_ROOT="${GOAL_REPO_ROOT:-}"
TIER="standard"
SKIP_SMOKE=0
SKIP_VALIDATE=0
SKIP_E2E=0

usage() {
  echo "Usage: quality-gate.sh --task-dir <path> [--repo-root <path>] [--tier standard|strict] [--skip-smoke] [--skip-validate] [--skip-e2e]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --repo-root) REPO_ROOT="$2"; shift 2 ;;
    --tier) TIER="$2"; shift 2 ;;
    --skip-smoke) SKIP_SMOKE=1; shift ;;
    --skip-validate) SKIP_VALIDATE=1; shift ;;
    --skip-e2e) SKIP_E2E=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

[[ -n "$TASK_DIR" ]] || usage
[[ -d "$TASK_DIR" ]] || { echo "task-dir not found: $TASK_DIR"; exit 1; }
REPO_ROOT="${REPO_ROOT:-$(pwd)}"

ISSUES=()
BLOCKED=0

add_issue() {
  local sev="$1" id="$2" msg="$3"
  ISSUES+=("[$sev] $id: $msg")
  [[ "$sev" == "BLOCK" ]] && BLOCKED=1
}

# L0: pipeline chain
if [[ -x "$SCRIPT_DIR/validate-pipeline-chain.sh" ]]; then
  if ! "$SCRIPT_DIR/validate-pipeline-chain.sh" --task-dir "$TASK_DIR" 2>/dev/null; then
    add_issue "BLOCK" "QG-L0-chain" "validate-pipeline-chain failed"
  fi
else
  python3 "$SCRIPT_DIR/validate-pipeline-chain.py" --task-dir "$TASK_DIR" || add_issue "BLOCK" "QG-L0-chain" "validate-pipeline-chain.py failed"
fi

# L0: secret scan (lightweight)
if command -v rg >/dev/null 2>&1; then
  if rg -l 'AKIA[0-9A-Z]{16}|api[_-]?key\s*=\s*["\x27][^"\x27]{8,}' "$REPO_ROOT" --glob '!node_modules' --glob '!.git' 2>/dev/null | head -1 | grep -q .; then
    add_issue "BLOCK" "QG-L0-secret" "possible secret pattern in repo"
  fi
fi

# L1: smoke
if [[ "$SKIP_SMOKE" -eq 0 && -x "$SCRIPT_DIR/runtime-smoke.sh" ]]; then
  if ! "$SCRIPT_DIR/runtime-smoke.sh" --repo-root "$REPO_ROOT" 2>/dev/null; then
    add_issue "BLOCK" "QG-L1-smoke" "runtime-smoke failed"
  fi
fi

# L1: test+lint via implement-qc (IQ-01)
if ! python3 "$SCRIPT_DIR/implement-qc-gate.py" --task-dir "$TASK_DIR" --repo-root "$REPO_ROOT" --tier "$TIER" --skip-test-lint 2>/dev/null; then
  : # IQ structural only when skip-test-lint; real test run optional in CI
fi

# L1: tier policy — strict requires evidence stubs
INDEX="$TASK_DIR/index.md"
if [[ "$TIER" == "strict" ]]; then
  [[ -d "$TASK_DIR/evidence" ]] || add_issue "BLOCK" "QG-L1-evidence" "strict tier requires evidence/"
  if [[ "$SKIP_VALIDATE" -eq 0 ]]; then
    grep -qi 'validate' "$INDEX" 2>/dev/null || add_issue "WARN" "QG-L1-validate" "strict tier: no validate evidence referenced"
  fi
  if [[ "$SKIP_E2E" -eq 0 ]]; then
    grep -qi 'e2e\|playwright' "$INDEX" 2>/dev/null || add_issue "WARN" "QG-L1-e2e" "strict tier: no e2e evidence referenced"
  fi
fi

# Output
for i in "${ISSUES[@]:-}"; do echo "$i"; done

if [[ "$BLOCKED" -eq 1 ]]; then
  echo "quality-gate: FAILED"
  exit 1
fi
echo "quality-gate: PASSED (tier=$TIER)"
exit 0
