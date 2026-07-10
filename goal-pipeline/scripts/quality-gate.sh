#!/usr/bin/env bash
# quality-gate.sh — L0 chain + read smoke evidence (no rerun smoke/IQ test)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR=""
REPO_ROOT="${GOAL_REPO_ROOT:-}"
TIER="standard"
SKIP_SMOKE=0
SKIP_VALIDATE=0
SKIP_E2E=0
SKIP_IQ=0
STATE_FILE=""
PROJECT_ROOT=""

usage() {
  echo "Usage: quality-gate.sh --task-dir <path> [--repo-root <path>] [--tier standard|strict] [--skip-smoke] [--skip-validate] [--skip-e2e] [--skip-iq]"
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
    --skip-iq) SKIP_IQ=1; shift ;;
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

[[ -n "$TASK_DIR" ]] || usage
[[ -d "$TASK_DIR" ]] || { echo "task-dir not found: $TASK_DIR"; exit 1; }
REPO_ROOT="${REPO_ROOT:-$(pwd)}"

GOAL_EVIDENCE_DIR="${GOAL_EVIDENCE_DIR:-$TASK_DIR/evidence}"
if [[ -f "$SCRIPT_DIR/resolve-artifact-paths.py" ]]; then
  _ARGS=(--task-dir "$TASK_DIR" --format shell)
  [[ -n "$STATE_FILE" ]] && _ARGS+=(--state-file "$STATE_FILE")
  [[ -n "$PROJECT_ROOT" ]] && _ARGS+=(--project-root "$PROJECT_ROOT")
  eval "$(python3 "$SCRIPT_DIR/resolve-artifact-paths.py" "${_ARGS[@]}" 2>/dev/null || true)"
  GOAL_EVIDENCE_DIR="${GOAL_EVIDENCE_DIR:-$TASK_DIR/evidence}"
fi

ISSUES=()
BLOCKED=0

add_issue() {
  local sev="$1" id="$2" msg="$3"
  ISSUES+=("[$sev] $id: $msg")
  [[ "$sev" == "BLOCK" ]] && BLOCKED=1
}

# L0: UVO evidence must exist and pass
UVO_JSON="$GOAL_EVIDENCE_DIR/verification-oracle.json"
if [[ ! -f "$UVO_JSON" ]]; then
  add_issue "BLOCK" "QG-L0-uvo" "verification-oracle.json missing"
else
  UVO_OVERALL=$(python3 -c "import json; print(json.load(open('$UVO_JSON')).get('overall',''))" 2>/dev/null || echo "")
  [[ "$UVO_OVERALL" == "pass" ]] || add_issue "BLOCK" "QG-L0-uvo" "verification-oracle overall not pass"
fi

# L0: pipeline chain
if [[ -x "$SCRIPT_DIR/validate-pipeline-chain.sh" ]]; then
  if ! "$SCRIPT_DIR/validate-pipeline-chain.sh" --task-dir "$TASK_DIR" ${STATE_FILE:+--state-file "$STATE_FILE"} 2>/dev/null; then
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

# L1: read smoke evidence (do NOT rerun runtime-smoke.sh)
if [[ "$SKIP_SMOKE" -eq 0 ]]; then
  SMOKE_MD="$GOAL_EVIDENCE_DIR/runtime-smoke.md"
  if [[ ! -f "$SMOKE_MD" ]]; then
    add_issue "BLOCK" "QG-L1-smoke" "runtime-smoke.md missing"
  else
    SRESULT=$(python3 - "$SMOKE_MD" << 'PYSR'
import re, sys
t = open(sys.argv[1]).read()
m = re.match(r"^---\s*\n(.*?)\n---", t, re.DOTALL)
if m:
    for line in m.group(1).splitlines():
        if line.strip().startswith("result:"):
            print(line.split(":",1)[1].strip().strip('"')); break
else:
    print("unknown")
PYSR
)
    if [[ "$SRESULT" == "not_pass" ]]; then
      add_issue "BLOCK" "QG-L1-smoke" "runtime-smoke result=not_pass"
    elif [[ "$SRESULT" != "pass" && "$SRESULT" != "skipped" ]]; then
      add_issue "BLOCK" "QG-L1-smoke" "runtime-smoke invalid result: $SRESULT"
    fi
  fi
fi

# L1: IQ structural only when not skipped (UVO already ran test+build)
if [[ "$SKIP_IQ" -eq 0 ]]; then
  if ! python3 "$SCRIPT_DIR/implement-qc-gate.py" --task-dir "$TASK_DIR" --repo-root "$REPO_ROOT" --tier "$TIER" --skip-test-lint 2>/dev/null; then
    add_issue "BLOCK" "QG-L1-iq" "implement-qc structural check failed"
  fi
fi

INDEX="$TASK_DIR/index.md"
if [[ "$TIER" == "strict" ]]; then
  [[ -d "$TASK_DIR/evidence" || -d "$GOAL_EVIDENCE_DIR" ]] || add_issue "BLOCK" "QG-L1-evidence" "strict tier requires evidence/"
  if [[ "$SKIP_VALIDATE" -eq 0 ]]; then
    grep -qi 'validate' "$INDEX" 2>/dev/null || add_issue "WARN" "QG-L1-validate" "strict tier: no validate evidence referenced"
  fi
  if [[ "$SKIP_E2E" -eq 0 ]]; then
    grep -qi 'e2e\|playwright' "$INDEX" 2>/dev/null || add_issue "WARN" "QG-L1-e2e" "strict tier: no e2e evidence referenced"
  fi
fi

for i in "${ISSUES[@]:-}"; do echo "$i"; done

if [[ "$BLOCKED" -eq 1 ]]; then
  echo "quality-gate: FAILED"
  exit 1
fi
echo "quality-gate: PASSED (tier=$TIER)"
exit 0
