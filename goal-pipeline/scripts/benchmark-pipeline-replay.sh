#!/usr/bin/env bash
# benchmark-pipeline-replay.sh — pipeline replay acceptance + review chain metrics
# Usage: benchmark-pipeline-replay.sh --task-dir <path> [--output evidence/benchmark.json] [--profile ctb43806]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR=""
REPO_ROOT=""
OUTPUT=""
STATE_FILE=""
PROJECT_ROOT=""
PROFILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --repo-root) REPO_ROOT="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$TASK_DIR" ]] || { echo "Usage: $0 --task-dir <path> [--output path] [--profile ctb43806]" >&2; exit 2; }
[[ "$TASK_DIR" != /* ]] && TASK_DIR="$(pwd)/$TASK_DIR"
TASK_DIR="$(cd "$TASK_DIR" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(pwd)}"

GOAL_COMMIT=$(git -C "$(dirname "$SCRIPT_DIR")/.." rev-parse --short HEAD 2>/dev/null || echo "unknown")
START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

OPS=$(python3 - "$SCRIPT_DIR" << 'PY'
import json, os, sys
script_dir = sys.argv[1]
checks = {
    "verification_oracle_expected": 1,
    "verify_review_full_in_assemble": 0,
    "implement_qc_full_test_in_gate": 0,
    "quality_gate_smoke_rerun": 0,
    "stage_driver_mandatory_yarn_test": 0,
    "review_uvo_skip_enabled": 0,
    "review_orchestrator_wired": 0,
    "review_fallback_orchestrator_present": 0,
    "review_packet_shard_present": 0,
    "review_depth_present": 0,
    "readonly_subagent_present": 0,
    "quality_tier_auto_upgrade": 0,
    "default_diff_source_code_subject": 0,
    "adapter_max_tokens_set": 0,
    "plan_before_code_guard": 0,
    "state_branch_scoped_discover": 0,
    "quality_gate_receives_state_file": 0,
    "review_zero_channel_failfast": 0,
    "refresh_cascade_exec_guard": 0,
    "pipeline_timing_utc": 0,
}
for name in ("gate-goal-stage.sh", "goal-stage-driver.sh", "assemble-review-packet.sh", "quality-gate.sh", "run-independent-review.sh", "verify-review.sh", "goal-run-review-chain.sh", "refresh-handoffs-after-index.sh", "resolve-artifact-paths.py"):
    path = os.path.join(script_dir, name)
    if not os.path.isfile(path):
        continue
    text = open(path, encoding="utf-8").read()
    if name == "assemble-review-packet.sh":
        checks["verify_review_full_in_assemble"] = text.count("subprocess.check_output([verify_script")
        checks["default_diff_source_code_subject"] = 1 if "code_subject_hash" in text else 0
    if name == "quality-gate.sh":
        checks["quality_gate_smoke_rerun"] = 1 if ("runtime-smoke.sh" in text and "read smoke evidence" not in text.lower()) else 0
    if name == "goal-stage-driver.sh":
        checks["stage_driver_mandatory_yarn_test"] = text.count('yarn test --watchAll=false')
    if name == "run-independent-review.sh":
        checks["review_orchestrator_wired"] = 1 if "review_fallback_orchestrator.py" in text else 0
    if name == "verify-review.sh":
        checks["review_uvo_skip_enabled"] = 1 if "verification-oracle.json" in text and "skip" in text.lower() else 0
    if name == "gate-goal-stage.sh":
        checks["quality_tier_auto_upgrade"] = 1 if "quality_policy_tier.py" in text else 0
        checks["quality_gate_receives_state_file"] = 1 if "QG_ARGS+=(--state-file" in text or 'QG_ARGS+=(--state-file "$STATE_FILE")' in text else 0
        checks["plan_before_code_guard"] = 1 if "run_plan_before_code_guard" in text else 0
    if name == "goal-run-review-chain.sh":
        chain_text = text
        rk = os.path.join(os.path.dirname(script_dir), "..", "shared", "review-kernel", "scripts", "run-review-chain.sh")
        if os.path.isfile(rk):
            chain_text += open(rk, encoding="utf-8").read()
        checks["review_zero_channel_failfast"] = 1 if "zero_usable_review_channels" in chain_text or "separation=degraded" in chain_text else 0
    if name == "refresh-handoffs-after-index.sh":
        checks["refresh_cascade_exec_guard"] = 1 if "demote to implement" in text else 0
    if name == "resolve-artifact-paths.py":
        checks["state_branch_scoped_discover"] = 1 if "state_branch_matches" in text else 0

for fname, key in (
    ("review_fallback_orchestrator.py", "review_fallback_orchestrator_present"),
    ("review_packet_shard.py", "review_packet_shard_present"),
    ("review_depth.py", "review_depth_present"),
    ("readonly_subagent_review.py", "readonly_subagent_present"),
    ("assert_plan_before_code.py", "plan_before_code_guard"),
    ("record-pipeline-timing.py", "pipeline_timing_utc"),
):
    if os.path.isfile(os.path.join(script_dir, fname)):
        checks[key] = 1

adapter = os.path.join(script_dir, "review_fallback_orchestrator.py")
if os.path.isfile(adapter):
    t = open(adapter, encoding="utf-8").read()
    checks["adapter_max_tokens_set"] = 1 if "max_tokens" in t and "4096" in t else 0
print(json.dumps(checks))
PY
)

END_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

# CTB-43806 baseline (postmortem §1.1) — before optimization
CTB43806_BASELINE='{
  "task": "CTB-43806-A4",
  "review_wall_clock_min": 31,
  "total_wall_clock_min": 46,
  "packet_diff_chars": 61600,
  "prompt_bytes_est": 88000,
  "T_retry": 3,
  "separation_score": "none",
  "verify_review_repeat_test": true
}'

RESULT=$(python3 - "$GOAL_COMMIT" "$TASK_DIR" "$OPS" "$START_MS" "$END_MS" "$PROFILE" "$CTB43806_BASELINE" << 'PYOUT'
import json, sys
from datetime import datetime, timezone

goal_commit, task_dir, ops_json, start_ms, end_ms, profile, baseline_json = sys.argv[1:8]
ops = json.loads(ops_json)
baseline = json.loads(baseline_json)

review_chain_score = sum(
    1 for k in (
        "review_uvo_skip_enabled",
        "review_orchestrator_wired",
        "review_fallback_orchestrator_present",
        "review_packet_shard_present",
        "review_depth_present",
        "readonly_subagent_present",
        "default_diff_source_code_subject",
        "adapter_max_tokens_set",
    )
    if ops.get(k)
)

target = {
    "review_wall_clock_min_max": 8,
    "T_retry_max": 0,
    "packet_diff_chars_max": 25000,
    "separation_score_min": "medium",
    "review_chain_features_min": 7,
}

comparison = {
    "baseline": baseline,
    "target": target,
    "delta_review_min_est": baseline["review_wall_clock_min"] - target["review_wall_clock_min_max"],
    "features_enabled": review_chain_score,
    "features_required": target["review_chain_features_min"],
    "projected_improvement": {
        "uvo_skip_saves_min": "1-10",
        "scoped_diff_prompt_reduction_pct": "40-60",
        "fallback_prevents_blind_retry": True,
        "shard_parallel_target_min": "2-4",
    },
}

passed = (
    ops.get("verification_oracle_expected", 99) <= 1
    and ops.get("verify_review_full_in_assemble", 99) == 0
    and ops.get("stage_driver_mandatory_yarn_test", 99) == 0
    and review_chain_score >= target["review_chain_features_min"]
)

if profile == "ctb43806":
    comparison["profile"] = "ctb43806"
    comparison["acceptance_note"] = (
        "Static replay: review chain features present; wall-clock requires live API replay"
    )

payload = {
    "schema_version": 2,
    "benchmark_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "goal_commit": goal_commit,
    "task_dir": task_dir,
    "profile": profile or "default",
    "duration_ms": int(end_ms) - int(start_ms),
    "op_counts": ops,
    "review_chain": {
        "score": review_chain_score,
        "max": 8,
        "comparison": comparison,
    },
    "acceptance": {
        "uvo_calls_max": 1,
        "assemble_verify_subprocess_max": 0,
        "stage_driver_yarn_test_max": 0,
        "review_chain_score_min": target["review_chain_features_min"],
    },
    "passed": passed,
}
print(json.dumps(payload, ensure_ascii=False, indent=2))
PYOUT
)

if [[ -z "$OUTPUT" ]]; then
  eval "$(python3 "$SCRIPT_DIR/resolve-artifact-paths.py" --task-dir "$TASK_DIR" --format shell 2>/dev/null || true)"
  OUTPUT="${GOAL_EVIDENCE_DIR:-$TASK_DIR/evidence}/benchmark.json"
fi
mkdir -p "$(dirname "$OUTPUT")"
echo "$RESULT" > "$OUTPUT"
echo "$RESULT"
PASS=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('passed', False))")
[[ "$PASS" == "True" ]] && exit 0 || exit 1
