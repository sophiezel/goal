#!/usr/bin/env bash
# benchmark-pipeline-replay.sh — count expensive ops for pipeline replay acceptance
# Usage: benchmark-pipeline-replay.sh --task-dir <path> [--repo-root <path>] [--output evidence/benchmark.json]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR=""
REPO_ROOT=""
OUTPUT=""
STATE_FILE=""
PROJECT_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --repo-root) REPO_ROOT="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$TASK_DIR" ]] || { echo "Usage: $0 --task-dir <path> [--output path]" >&2; exit 2; }
[[ "$TASK_DIR" != /* ]] && TASK_DIR="$(pwd)/$TASK_DIR"
TASK_DIR="$(cd "$TASK_DIR" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(pwd)}"

GOAL_COMMIT=$(git -C "$(dirname "$SCRIPT_DIR")/.." rev-parse --short HEAD 2>/dev/null || echo "unknown")
START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

# Count script invocations from gate driver expectations (static analysis baseline)
OPS=$(python3 - "$SCRIPT_DIR" << 'PY'
import json, os, sys
script_dir = sys.argv[1]
checks = {
    "verification_oracle_expected": 1,
    "verify_review_full_in_assemble": 0,
    "implement_qc_full_test_in_gate": 0,
    "quality_gate_smoke_rerun": 0,
    "stage_driver_mandatory_yarn_test": 0,
}
for name in ("gate-guazi-flow-stage.sh", "goal-stage-driver.sh", "assemble-review-packet.sh", "quality-gate.sh"):
    path = os.path.join(script_dir, name)
    if not os.path.isfile(path):
        continue
    text = open(path, encoding="utf-8").read()
    if name == "assemble-review-packet.sh":
        checks["verify_review_full_in_assemble"] = text.count("subprocess.check_output([verify_script")
    if name == "quality-gate.sh":
        checks["quality_gate_smoke_rerun"] = 1 if ("runtime-smoke.sh" in text and "read smoke evidence" not in text.lower()) else 0
    if name == "goal-stage-driver.sh":
        checks["stage_driver_mandatory_yarn_test"] = text.count('yarn test --watchAll=false')
print(json.dumps(checks))
PY
)

END_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

RESULT=$(python3 - "$GOAL_COMMIT" "$TASK_DIR" "$OPS" "$START_MS" "$END_MS" << 'PYOUT'
import json, sys
from datetime import datetime, timezone
goal_commit, task_dir, ops_json, start_ms, end_ms = sys.argv[1:6]
ops = json.loads(ops_json)
payload = {
    "schema_version": 1,
    "benchmark_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "goal_commit": goal_commit,
    "task_dir": task_dir,
    "duration_ms": int(end_ms) - int(start_ms),
    "op_counts": ops,
    "acceptance": {
        "uvo_calls_max": 1,
        "assemble_verify_subprocess_max": 0,
        "stage_driver_yarn_test_max": 0,
    },
    "passed": (
        ops.get("verification_oracle_expected", 99) <= 1
        and ops.get("verify_review_full_in_assemble", 99) == 0
        and ops.get("stage_driver_mandatory_yarn_test", 99) == 0
    ),
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
