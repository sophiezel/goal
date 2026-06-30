#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK="$SCRIPT_DIR/review-dual-mock-good"
RUN="$SCRIPT_DIR/../../run-independent-review.sh"
MERGE="$SCRIPT_DIR/../../merge-review-issues.sh"
ASSEMBLE="$SCRIPT_DIR/../../assemble-review-packet.sh"

"$ASSEMBLE" --task-dir "$TASK" >/dev/null 2>&1 || true
GOAL_REVIEW_PROVIDER=mock-dual GOAL_REVIEW_MODE=dual "$RUN" --task-dir "$TASK" --provider mock-dual --mode dual
"$MERGE" --task-dir "$TASK" --goal-json "$TASK/evidence/review-goal.json"

python3 - "$TASK" << 'PY'
import json, sys
task = sys.argv[1]
run = json.load(open(f"{task}/evidence/review-run.json", encoding="utf-8"))
gf = json.load(open(f"{task}/evidence/review-gf.json", encoding="utf-8"))
fix = json.load(open(f"{task}/evidence/review-fix-input.json", encoding="utf-8"))
assert run.get("gf_skill_attested") is True, "gf_skill_attested missing in review-run"
assert "guazi-flow-review" in run.get("channels", []), "dual channels missing"
assert gf.get("skill_attested") is True, "skill_attested missing in review-gf"
assert fix.get("provenance", {}).get("gf_skill_attested") is True, "fix-input provenance"
assert "gf_rubric_source" in run, "gf_rubric_source field expected"
print("OK review-dual-mock attested")
PY
