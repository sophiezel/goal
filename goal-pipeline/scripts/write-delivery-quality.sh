#!/usr/bin/env bash
# write-delivery-quality.sh — complete 阶段产出 delivery-quality.json（v3 §0 节点 I/O 契约）
# 用法: write-delivery-quality.sh --task-dir <path> [--state-file <path>] [--output <path>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR=""
STATE_FILE=""
OUTPUT=""

usage() { echo "Usage: $0 --task-dir <path> [--state-file <path>] [--output <path>]"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done
[[ -n "$TASK_DIR" && -d "$TASK_DIR" ]] || usage

OUTPUT="${OUTPUT:-$TASK_DIR/handoff/delivery-quality.json}"
HANDOFF="$TASK_DIR/handoff"
EVIDENCE="$TASK_DIR/evidence"

python3 - "$TASK_DIR" "$HANDOFF" "$EVIDENCE" "$OUTPUT" "$STATE_FILE" << 'PY'
import json, os, sys
from datetime import datetime, timezone

task_dir, handoff, evidence, output, state_file = sys.argv[1:6]

stages = ["plan", "implement", "quality", "review", "complete"]
chain = {}
stages_summary = {}
for s in stages:
    p = os.path.join(handoff, f"{s}.json")
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

# leak_rate for single task: 1 if escape-register attributes an escape to this task
leak = 0.0
escape_path = os.path.join(evidence, "escape-register.json")
if os.path.isfile(escape_path):
    try:
        er = json.load(open(escape_path, encoding="utf-8"))
        for e in er.get("escapes", []):
            if os.path.abspath(e.get("task_dir", "")) == os.path.abspath(task_dir):
                leak = 1.0
                break
    except (OSError, json.JSONDecodeError):
        pass

# tier / profile / track from state + plan
task_tier = ""
plan_profile = ""
review_track = ""
plan_path = os.path.join(handoff, "plan.json")
if os.path.isfile(plan_path):
    try:
        plan = json.load(open(plan_path, encoding="utf-8"))
        task_tier = plan.get("task_tier", "")
        plan_profile = plan.get("plan_profile", "full")
    except (OSError, json.JSONDecodeError):
        pass
if os.path.isfile(state_file):
    try:
        st = json.load(open(state_file, encoding="utf-8"))
        task_tier = task_tier or st.get("task_tier", "")
        review_track = (st.get("review_policy") or {}).get("track", "")
    except (OSError, json.JSONDecodeError):
        pass

gate_status = "OK" if (all_complete and leak == 0.0) else "BLOCK"

report = {
    "schema_version": 1,
    "task_dir": task_dir,
    "computed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "chain_complete": chain,
    "leak_rate": leak,
    "gate_status": gate_status,
    "stages_summary": stages_summary,
    "task_tier": task_tier,
    "plan_profile": plan_profile,
    "review_track": review_track,
}

os.makedirs(os.path.dirname(output), exist_ok=True)
with open(output, "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(json.dumps(report, ensure_ascii=False, indent=2))
PY
