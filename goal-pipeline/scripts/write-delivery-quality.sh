#!/usr/bin/env bash
# write-delivery-quality.sh — complete 阶段产出 delivery-quality.json（Port Spec v2）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

export HANDOFF GOAL_EVIDENCE REPO_TASK OUTPUT STATE_FILE PIPELINE_ID
python3 << 'PY'
import json, os, sys
from datetime import datetime, timezone

handoff = os.environ["HANDOFF"]
goal_evidence = os.environ["GOAL_EVIDENCE"]
repo_task = os.environ["REPO_TASK"]
output = os.environ["OUTPUT"]
state_file = os.environ.get("STATE_FILE", "")
pipeline_id = os.environ.get("PIPELINE_ID", "guazi-flow-goal")

stages = ["plan", "implement", "quality", "review", "complete"]
chain = {}
stages_summary = {}
for s in stages:
    p = os.path.join(handoff, f"{s}.json")
    if s == "quality" and not os.path.isfile(p):
        p = os.path.join(handoff, "smoke.json")
    exists = os.path.isfile(p)
    chain[s] = exists
    if exists:
        try:
            d = json.load(open(p, encoding="utf-8"))
            stages_summary[s] = {
                "gate_passed_at": (d.get("gate") or {}).get("passed_at", ""),
                "post_exit_code": (d.get("gate") or {}).get("post_exit_code", ""),
            }
        except (OSError, json.JSONDecodeError):
            stages_summary[s] = {}

all_complete = all(chain.values())
leak = 0.0
escape_path = os.path.join(goal_evidence, "escape-register.json")
if not os.path.isfile(escape_path):
    escape_path = os.path.join(repo_task, "evidence", "escape-register.json")
if os.path.isfile(escape_path):
    try:
        er = json.load(open(escape_path, encoding="utf-8"))
        for e in er.get("escapes", []):
            if os.path.abspath(e.get("task_dir", "")) == os.path.abspath(repo_task):
                leak = 1.0
                break
    except (OSError, json.JSONDecodeError):
        pass

task_tier = plan_profile = review_track = ""
plan_path = os.path.join(handoff, "plan.json")
if os.path.isfile(plan_path):
    try:
        plan = json.load(open(plan_path, encoding="utf-8"))
        task_tier = plan.get("task_tier", "") or plan.get("tier", "")
        plan_profile = plan.get("plan_profile", "full")
    except (OSError, json.JSONDecodeError):
        pass

state = {}
if state_file and os.path.isfile(state_file):
    try:
        state = json.load(open(state_file, encoding="utf-8"))
        task_tier = task_tier or state.get("task_tier", "")
        review_track = (state.get("review_policy") or {}).get("track", "")
        if not review_track:
            review_track = (state.get("review_track") or "")
    except (OSError, json.JSONDecodeError):
        pass

timing = {"source": "evidence/pipeline-timing.json"}
timing_path = os.path.join(goal_evidence, "pipeline-timing.json")
if not os.path.isfile(timing_path):
    timing_path = os.path.join(repo_task, "evidence", "pipeline-timing.json")
if os.path.isfile(timing_path):
    try:
        pt = json.load(open(timing_path, encoding="utf-8"))
        stages_t = pt.get("stages") or pt.get("by_stage") or {}
        def ms_for(name):
            ent = stages_t.get(name) or {}
            if isinstance(ent, dict):
                return int(ent.get("wall_ms") or ent.get("ms") or 0)
            return 0
        timing.update({
            "plan_ms": ms_for("plan"),
            "implement_ms": ms_for("implement"),
            "quality_ms": ms_for("quality") or ms_for("smoke"),
            "review_ms": ms_for("review"),
            "total_ms": int(pt.get("total_ms") or pt.get("wall_ms_total") or 0),
        })
    except (OSError, json.JSONDecodeError):
        pass

review_prov = {
    "model_invocations": 0,
    "latency_ms": 0,
    "provider": "",
    "model": "",
    "channels_used": [],
    "issues_goal": 0,
    "issues_gf": 0,
}
run_path = os.path.join(goal_evidence, "review-run.json")
if os.path.isfile(run_path):
    try:
        run = json.load(open(run_path, encoding="utf-8"))
        review_prov["model_invocations"] = int(run.get("invocation_count") or 1)
        review_prov["latency_ms"] = int(run.get("latency_ms") or 0)
        review_prov["provider"] = run.get("provider", "")
        review_prov["model"] = run.get("model", "")
        review_prov["channels_used"] = run.get("channels") or []
    except (OSError, json.JSONDecodeError):
        pass

fix_path = os.path.join(goal_evidence, "review-fix-input.json")
loops = {
    "review_rounds": 0,
    "replan_count": int(state.get("replan_count") or 0),
    "stagnant_blocked": False,
    "final_action": "",
    "first_pass": False,
}
if os.path.isfile(fix_path):
    try:
        fix = json.load(open(fix_path, encoding="utf-8"))
        loops["review_rounds"] = int(fix.get("round") or 0)
        loops["stagnant_blocked"] = bool(fix.get("stagnant_blocked"))
        loops["final_action"] = fix.get("action", "")
        loops["first_pass"] = loops["review_rounds"] <= 1 and fix.get("merged_result") == "pass"
        review_prov["issues_goal"] = sum(1 for i in fix.get("issues", []) if i.get("channel") != "guazi-flow-review")
        review_prov["issues_gf"] = sum(1 for i in fix.get("issues", []) if i.get("channel") == "guazi-flow-review")
    except (OSError, json.JSONDecodeError):
        pass

handoff_cov = sum(1 for v in chain.values() if v) / max(len(chain), 1)
blocker_final = 0
if os.path.isfile(fix_path):
    try:
        blocker_final = int(json.load(open(fix_path, encoding="utf-8")).get("blocker_count") or 0)
    except (OSError, json.JSONDecodeError):
        pass

gate_status = "OK" if (all_complete and leak == 0.0) else "BLOCK"

report = {
    "schema_version": 2,
    "pipeline_id": pipeline_id,
    "task_dir": repo_task,
    "computed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "chain_complete": chain,
    "leak_rate": leak,
    "gate_status": gate_status,
    "stages_summary": stages_summary,
    "task_tier": task_tier,
    "plan_profile": plan_profile,
    "review_track": review_track,
    "timing": timing,
    "review_provenance": review_prov,
    "loops": loops,
    "quality_summary": {
        "blocker_count_final": blocker_final,
        "leak_rate": leak,
        "handoff_coverage": round(handoff_cov, 4),
    },
}

os.makedirs(os.path.dirname(output), exist_ok=True)
with open(output, "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(json.dumps(report, ensure_ascii=False, indent=2))
PY
