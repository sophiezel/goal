#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK="$SCRIPT_DIR/review-unified-good"
RUN="$SCRIPT_DIR/../../run-independent-review.sh"
MERGE="$SCRIPT_DIR/../../merge-review-issues.sh"
ASSEMBLE="$SCRIPT_DIR/../../assemble-review-packet.sh"

"$ASSEMBLE" --task-dir "$TASK" >/dev/null 2>&1 || true
GOAL_REVIEW_PROVIDER=mock-unified GOAL_REVIEW_MODE=unified "$RUN" --task-dir "$TASK" --provider mock-unified --mode unified
"$MERGE" --task-dir "$TASK" --unified-json "$TASK/evidence/review-unified.json"

python3 - "$TASK" << 'PY'
import json, sys
task = sys.argv[1]
run = json.load(open(f"{task}/evidence/review-run.json", encoding="utf-8"))
unified = json.load(open(f"{task}/evidence/review-unified.json", encoding="utf-8"))
fix = json.load(open(f"{task}/evidence/review-fix-input.json", encoding="utf-8"))
assert run.get("mode") == "unified", "mode should be unified"
assert run.get("invocation_count", 1) == 1, "single invocation expected"
assert "goal" in run.get("channels", []), "unified channels missing goal"
assert fix.get("provenance", {}).get("gf_skill_attested") is False, "goal v1.4 no gf attestation"
print("OK review-unified-mock")
PY
