#!/bin/bash
# goal-pipeline-recover.sh — Diagnose broken pipeline state and suggest fixes
# Usage: goal-pipeline-recover.sh --state-file <path> --task-dir <path> --project-root <path>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOAL_STATE_HOME="${GOAL_STATE_HOME:-${GOAL_HOME:-$HOME/.goal-pipeline}/state}"
GATE="$GOAL_STATE_HOME/scripts/gate-goal-stage.sh"
[[ -x "$GATE" ]] || GATE="$SCRIPT_DIR/gate-goal-stage.sh"
CHAIN="$GOAL_STATE_HOME/scripts/validate-pipeline-chain.sh"
[[ -x "$CHAIN" ]] || CHAIN="$SCRIPT_DIR/validate-pipeline-chain.sh"
CHECK="$GOAL_STATE_HOME/scripts/check-consistency"
[[ -x "$CHECK" ]] || CHECK="$SCRIPT_DIR/check-consistency"
DRIVER="$GOAL_STATE_HOME/scripts/goal-stage-driver.sh"
[[ -x "$DRIVER" ]] || DRIVER="$SCRIPT_DIR/goal-stage-driver.sh"

STATE_FILE=""
TASK_DIR=""
PROJECT_ROOT=""
FORMAT="json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --state-file <path> --task-dir <path> --project-root <path>"
      exit 0 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$STATE_FILE" && -n "$TASK_DIR" && -n "$PROJECT_ROOT" ]] || {
  echo '{"error":"--state-file --task-dir --project-root required"}' >&2; exit 2
}

if [[ "$TASK_DIR" != /* ]]; then TASK_DIR="$PROJECT_ROOT/$TASK_DIR"; fi
TASK_DIR="$(cd "$TASK_DIR" && pwd)"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
HANDOFF="$TASK_DIR/handoff"
GOAL_EVIDENCE="$TASK_DIR/evidence"
ARTIFACT_MODE="repo_full"

RESOLVER="$SCRIPT_DIR/resolve-artifact-paths.py"
if [[ -f "$RESOLVER" ]]; then
  _RESOLVE_ARGS=(--task-dir "$TASK_DIR" --format shell)
  [[ -n "$STATE_FILE" ]] && _RESOLVE_ARGS+=(--state-file "$STATE_FILE")
  [[ -n "$PROJECT_ROOT" ]] && _RESOLVE_ARGS+=(--project-root "$PROJECT_ROOT")
  eval "$(python3 "$RESOLVER" "${_RESOLVE_ARGS[@]}")"
  HANDOFF="$HANDOFF_DIR"
  GOAL_EVIDENCE="$GOAL_EVIDENCE_DIR"
  ARTIFACT_MODE="$ARTIFACT_MODE"
fi

export STATE_FILE TASK_DIR PROJECT_ROOT HANDOFF GOAL_EVIDENCE ARTIFACT_MODE GATE CHAIN CHECK DRIVER FORMAT
python3 << 'PY'
import json, os, re, subprocess, sys
from pathlib import Path

state_file = os.environ["STATE_FILE"]
task_dir = Path(os.environ["TASK_DIR"])
handoff = Path(os.environ["HANDOFF"])
project_root = os.environ["PROJECT_ROOT"]
gate = os.environ["GATE"]
chain = os.environ["CHAIN"]
driver = os.environ["DRIVER"]
fmt = os.environ.get("FORMAT", "json")

issues = []
fixes = []

def has_handoff(name):
    return (handoff / name).is_file()

idx = task_dir / "index.md"
index_text = idx.read_text(encoding="utf-8") if idx.is_file() else ""

st = {}
if Path(state_file).is_file():
    st = json.loads(Path(state_file).read_text(encoding="utf-8"))

# Missing plan.json but index looks complete
if not has_handoff("plan.json") and "goal-plan" in index_text:
    issues.append("plan_handoff_missing")
    fixes.append({
        "action": "gate_post_plan",
        "command": f"{gate} --task-dir {task_dir} --stage plan --post --state-file {state_file} --project-root {project_root}",
        "note": "Retrofit plan handoff from index.md artifacts (do not hand-write plan.json)",
    })

# Plan handoff stale (contract or execution) — prefer refresh-handoffs-after-index.sh
refresh = os.path.join(os.path.dirname(gate), "refresh-handoffs-after-index.sh")
hash_py = os.path.join(os.path.dirname(gate), "index_contract_hash.py")
if has_handoff("plan.json") and idx.is_file() and os.path.isfile(hash_py):
    try:
        r = subprocess.run(
            [sys.executable, hash_py, "--json", str(idx), str(handoff / "plan.json")],
            capture_output=True, text=True, timeout=15,
        )
        if r.returncode == 0 and r.stdout.strip():
            fresh = json.loads(r.stdout)
            if fresh.get("contract_changed"):
                issues.append("plan_handoff_stale_contract")
                fixes.insert(0, {
                    "action": "refresh_handoffs_plan",
                    "command": f"{refresh} --task-dir {task_dir} --state-file {state_file} --project-root {project_root} --cascade plan",
                    "note": "index contract sections changed — mini-replan via refresh script (do not hand-edit handoff)",
                })
            elif fresh.get("execution_changed") or (
                not fresh.get("fresh", True) and not fresh.get("contract_changed")
            ):
                issues.append("plan_handoff_stale_execution")
                fixes.insert(0, {
                    "action": "refresh_handoffs_implement",
                    "command": f"{refresh} --task-dir {task_dir} --state-file {state_file} --project-root {project_root} --cascade implement",
                    "note": "execution record only — NOT mini-replan; refresh implement handoff + packet",
                })
            elif not (handoff / "review-packet.json").is_file() and (st.get("current_stage") in ("review", "complete") or "review" in (st.get("current_stage") or "")):
                issues.append("review_packet_missing")
                fixes.append({
                    "action": "refresh_handoffs_packet",
                    "command": f"{refresh} --task-dir {task_dir} --state-file {state_file} --project-root {project_root} --cascade packet",
                })
    except Exception as e:
        issues.append("plan_freshness_check_error")
        fixes.append({"action": "manual", "note": str(e)[:200]})

# implement without plan
if has_handoff("implement.json") and not has_handoff("plan.json"):
    issues.append("implement_without_plan")
    fixes.insert(0, fixes[-1] if fixes else {
        "action": "gate_post_plan",
        "command": f"{gate} --task-dir {task_dir} --stage plan --post --state-file {state_file} --project-root {project_root}",
    })

# index current_stage ahead of handoff
m = re.search(r"current_stage:\s*(\S+)", index_text)
idx_stage = m.group(1) if m else None
handoff_stages = [p.stem for p in handoff.glob("*.json") if p.name != "review-packet.json"]
if idx_stage and idx_stage not in ("complete", "done"):
    expected = {"plan": "plan", "implement": "implement", "runtime_smoke": "smoke", "smoke": "smoke", "review": "review"}
    need = expected.get(idx_stage)
    if need and f"{need}.json" not in [f"{s}.json" for s in handoff_stages] and need != "smoke":
        issues.append("index_stage_ahead_of_handoff")
        fixes.append({
            "action": "check_consistency",
            "command": f"{os.environ.get('CHECK','')} {task_dir} 2>/dev/null || true",
            "note": "Run check-consistency and sync index current_stage from handoff truth",
        })

# implement gate pending
impl_gate = (st.get("pipeline_stages") or {}).get("implement", {}).get("gate", {})
if has_handoff("implement.json") and not impl_gate.get("passed_at"):
    issues.append("implement_gate_pending")
    fixes.append({
        "action": "implement_post_chain",
        "commands": [
            f"{gate} --task-dir {task_dir} --stage implement --post --state-file {state_file} --project-root {project_root}",
            f"{chain} --task-dir {task_dir} --state-file {state_file}",
            f"{os.path.dirname(gate)}/goal-advance-stage.sh --state-file {state_file} --task-dir {task_dir} --project-root {project_root}",
        ],
    })

# Chain validation
chain_ok = True
chain_errors = []
if Path(chain).is_file():
    try:
        r = subprocess.run([chain, "--task-dir", str(task_dir), "--state-file", state_file],
                           capture_output=True, text=True, timeout=30)
        if r.returncode != 0:
            chain_ok = False
            try:
                d = json.loads(r.stdout or r.stderr or "{}")
                chain_errors = d.get("errors", [])[:5]
            except json.JSONDecodeError:
                chain_errors = [(r.stderr or r.stdout or "chain failed")[:200]]
    except Exception as e:
        chain_ok = False
        chain_errors = [str(e)]

if not chain_ok:
    issues.append("pipeline_chain_invalid")
    fixes.append({"action": "fix_chain", "errors": chain_errors})

# Standard resume path
resume_path = []
if not has_handoff("plan.json"):
    resume_path.append("gate --post plan")
if has_handoff("plan.json") and not has_handoff("implement.json"):
    resume_path.append("implement phase")
elif has_handoff("implement.json") and not Path(os.environ.get("GOAL_EVIDENCE", str(task_dir / "evidence")) + "/runtime-smoke.md").is_file():
    resume_path.append("runtime-smoke.sh + gate --post smoke")
elif Path(os.environ.get("GOAL_EVIDENCE", str(task_dir / "evidence")) + "/runtime-smoke.md").is_file() and not has_handoff("review.json"):
    resume_path.append("goal-run-review-chain.sh + gate --post review")
elif has_handoff("review.json") and not has_handoff("complete.json"):
    resume_path.append("goal-complete + gate --post complete")

work_order = None
if Path(driver).is_file():
    try:
        r = subprocess.run([
            driver, "--state-file", state_file, "--task-dir", str(task_dir),
            "--project-root", project_root, "--format", "json"
        ], capture_output=True, text=True, timeout=30)
        if r.returncode == 0 and r.stdout.strip():
            work_order = json.loads(r.stdout)
    except Exception:
        pass

report = {
    "schema_version": 1,
    "task_dir": str(task_dir),
    "state_file": state_file,
    "issues": issues,
    "fixes": fixes,
    "chain_ok": chain_ok,
    "chain_errors": chain_errors,
    "handoff_present": sorted(p.name for p in handoff.glob("*.json")),
    "resume_path": resume_path,
    "work_order": work_order,
}

if fmt == "text":
    print("issues:", ", ".join(issues) or "none")
    for f in fixes:
        print("fix:", f.get("action"), f.get("command") or f.get("commands"))
    if work_order:
        print("next_stage:", work_order.get("next_stage"))
else:
    print(json.dumps(report, ensure_ascii=False, indent=2))
PY
