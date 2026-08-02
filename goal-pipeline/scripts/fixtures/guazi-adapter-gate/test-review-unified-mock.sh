#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK="$SCRIPT_DIR/review-unified-good"
RUN="$SCRIPT_DIR/../../run-independent-review.sh"
MERGE="$SCRIPT_DIR/../../merge-review-issues.sh"
ASSEMBLE="$SCRIPT_DIR/../../assemble-review-packet.sh"

"$ASSEMBLE" --task-dir "$TASK" >/dev/null 2>&1 || true
GOAL_REVIEW_TRACK=dual GOAL_REVIEW_PROVIDER=mock-unified GOAL_REVIEW_MODE=unified "$RUN" --task-dir "$TASK" --provider mock-unified --mode unified
"$MERGE" --task-dir "$TASK" --unified-json "$TASK/evidence/review-unified.json"

python3 - "$TASK" << 'PY'
import json, sys
task = sys.argv[1]
run = json.load(open(f"{task}/evidence/review-run.json", encoding="utf-8"))
unified = json.load(open(f"{task}/evidence/review-unified.json", encoding="utf-8"))
fix = json.load(open(f"{task}/evidence/review-fix-input.json", encoding="utf-8"))
assert run.get("gf_skill_attested") is True, "gf_skill_attested missing in review-run"
assert run.get("mode") == "unified", "mode should be unified"
assert run.get("invocation_count", 1) == 1, "single invocation expected"
assert "guazi-flow-review" in run.get("channels", []), "unified channels missing gf"
assert unified.get("gf_skill_attested") is True, "unified gf_skill_attested"
assert fix.get("provenance", {}).get("gf_skill_attested") is True, "fix-input provenance"
assert "gf_rubric_source" in run, "gf_rubric_source field expected"
print("OK review-unified-mock attested")
PY
