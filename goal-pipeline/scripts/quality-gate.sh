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
  return 0
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

# L0: secret scan on git diff (changed files only; fallback to grep when rg missing)
SECRET_RE='AKIA[0-9A-Z]{16}|api[_-]?key[[:space:]]*=[[:space:]]*["\x27][^"\x27]{8,}|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}'
SECRET_HIT=""
if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  DIFF_FILES=$(git -C "$REPO_ROOT" diff --name-only HEAD 2>/dev/null || true)
  DIFF_STAGED=$(git -C "$REPO_ROOT" diff --cached --name-only 2>/dev/null || true)
  DIFF_UNTRACKED=$(git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null || true)
  SCAN_LIST=$(printf '%s\n%s\n%s\n' "$DIFF_FILES" "$DIFF_STAGED" "$DIFF_UNTRACKED" | sed '/^$/d' | sort -u || true)
  if [[ -n "$SCAN_LIST" ]]; then
    while IFS= read -r f; do
      [[ -z "$f" || ! -f "$REPO_ROOT/$f" ]] && continue
      case "$f" in
        node_modules/*|.git/*|*.lock|package-lock.json|yarn.lock) continue ;;
      esac
      if command -v rg >/dev/null 2>&1; then
        if rg -l -e "$SECRET_RE" "$REPO_ROOT/$f" >/dev/null 2>&1; then
          SECRET_HIT="$f"; break
        fi
      elif grep -EIq "$SECRET_RE" "$REPO_ROOT/$f" 2>/dev/null; then
        SECRET_HIT="$f"; break
      fi
    done <<< "$SCAN_LIST"
  else
    # No working-tree diff: scan staged+HEAD patch text only (avoid full-repo false positives)
    if git -C "$REPO_ROOT" diff HEAD 2>/dev/null | grep -EIq "^\+.*($SECRET_RE)" 2>/dev/null; then
      SECRET_HIT="git-diff"
    fi
  fi
fi
[[ -n "$SECRET_HIT" ]] && add_issue "BLOCK" "QG-L0-secret" "possible secret pattern in changed files: $SECRET_HIT"

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
# Resolve profile (h5 vs others) for Phase A2 e2e BLOCK gating
PROFILE=""
PLAN_HOFF="${HANDOFF_DIR:-$TASK_DIR/handoff}/plan.json"
if [[ -f "$PLAN_HOFF" ]]; then
  PROFILE=$(python3 -c "import json; print(json.load(open('$PLAN_HOFF')).get('profile',''))" 2>/dev/null || echo "")
fi
if [[ -z "$PROFILE" && -f "$INDEX" ]]; then
  PROFILE=$(python3 -c "
import re,sys
t=open('$INDEX').read()
m=re.match(r'^---\s*\n(.*?)\n---', t, re.DOTALL)
if m:
    for line in m.group(1).splitlines():
        if line.strip().startswith('profile:'):
            print(line.split(':',1)[1].strip().strip('\"')); break
" 2>/dev/null || echo "")
fi

if [[ "$TIER" == "strict" ]]; then
  [[ -d "$TASK_DIR/evidence" || -d "$GOAL_EVIDENCE_DIR" ]] || add_issue "BLOCK" "QG-L1-evidence" "strict tier requires evidence/"
  POLICY_JSON=""
  if [[ -f "$SCRIPT_DIR/goal_quality_e2e_policy.py" ]]; then
    POLICY_JSON=$(GOAL_EVIDENCE_DIR="$GOAL_EVIDENCE_DIR" python3 "$SCRIPT_DIR/goal_quality_e2e_policy.py" \
      --task-dir "$TASK_DIR" --tier "$TIER" --json 2>/dev/null || echo "")
  fi
  if [[ -n "$POLICY_JSON" ]]; then
    read -r VAL_SEV E2E_SEV E2E_OK <<< "$(python3 -c "
import json,sys
d=json.loads(sys.argv[1])
g=d.get('gate',{})
ev=d.get('evidence',{})
print(g.get('validate_index_ref','none'), g.get('e2e_evidence','none'), '1' if ev.get('e2e_present') else '0')
" "$POLICY_JSON")"
  else
    VAL_SEV="warn"
    E2E_SEV="WARN"
    [[ "$PROFILE" == "h5" ]] && E2E_SEV="BLOCK"
    E2E_OK=0
    if [[ -d "$GOAL_EVIDENCE_DIR/e2e" || -d "$TASK_DIR/evidence/e2e" ]]; then
      E2E_OK=1
    elif grep -qi 'playwright' "$INDEX" 2>/dev/null; then
      E2E_OK=1
    fi
  fi
  if [[ "$SKIP_VALIDATE" -eq 0 && "$VAL_SEV" == "warn" ]]; then
    if [[ -n "$POLICY_JSON" ]]; then
      VAL_OK=$(python3 -c "import json,sys; print('1' if json.loads(sys.argv[1])['evidence'].get('validate_mentioned') else '0')" "$POLICY_JSON")
    else
      VAL_OK=0
      grep -qi 'validate' "$INDEX" 2>/dev/null && VAL_OK=1
    fi
    [[ "$VAL_OK" == "1" ]] || add_issue "WARN" "QG-L1-validate" "strict tier: no validate evidence referenced"
  fi
  if [[ "$SKIP_E2E" -eq 0 && "$E2E_SEV" != "none" ]]; then
    if [[ "$E2E_OK" != "1" ]]; then
      if [[ "$E2E_SEV" == "block" ]]; then
        add_issue "BLOCK" "QG-L1-e2e" "Phase A2: strict+h5 requires e2e evidence (evidence/e2e/ or index playwright ref)"
      else
        add_issue "WARN" "QG-L1-e2e" "strict tier: no e2e evidence referenced"
      fi
    fi
  fi
fi

for i in "${ISSUES[@]:-}"; do echo "$i"; done

if [[ "$BLOCKED" -eq 1 ]]; then
  echo "quality-gate: FAILED"
  exit 1
fi
echo "quality-gate: PASSED (tier=$TIER)"
exit 0
