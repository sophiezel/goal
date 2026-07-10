#!/usr/bin/env bash
# goal-metrics-calibrate.sh — lightweight delivery quality metrics snapshot
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR=""
STATE_FILE=""
FORMAT="text"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 --task-dir <path> [--state-file <path>] [--format json|text]"; exit 0 ;;
    *) echo "Unknown: $1"; exit 2 ;;
  esac
done

[[ -n "$TASK_DIR" && -d "$TASK_DIR" ]] || { echo "task-dir required"; exit 2; }

python3 - "$TASK_DIR" "$STATE_FILE" "$FORMAT" << 'PY'
import json, os, sys, glob

task_dir, state_file, fmt = sys.argv[1:4]
handoff = os.path.join(task_dir, "handoff")
stages = ["plan", "implement", "quality", "review", "complete"]
passed = sum(1 for s in stages if os.path.isfile(os.path.join(handoff, f"{s}.json")))
pq_issues = 0
if os.path.isfile(os.path.join(task_dir, "evidence", "plan-gate-fix-input.json")):
    try:
        pq_issues = len(json.load(open(os.path.join(task_dir, "evidence", "plan-gate-fix-input.json"))).get("issues", []))
    except Exception:
        pass
state = {}
if state_file and os.path.isfile(state_file):
    state = json.load(open(state_file))
metrics = {
    "handoff_coverage": passed / len(stages),
    "stages_passed": passed,
    "pipeline_track": state.get("pipeline_track", "compatibility"),
    "quality_tier": (state.get("quality_policy") or {}).get("tier", "standard"),
    "plan_gate_retries": pq_issues,
    "ready_for_production": passed == len(stages) and state.get("status") == "complete",
}
if fmt == "json":
    print(json.dumps(metrics, ensure_ascii=False, indent=2))
else:
    for k, v in metrics.items():
        print(f"{k}={v}")
PY
