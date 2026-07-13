#!/bin/bash
# test-benchmark-review-replay.sh — benchmark schema v2 + CTB-43806 profile
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
OUT="/tmp/benchmark-review-replay-test.json"

bash "$SCRIPTS/benchmark-pipeline-replay.sh" \
  --task-dir "$DIR/plan-good" \
  --output "$OUT" \
  --profile ctb43806

python3 - "$OUT" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("schema_version") == 2, d
assert d.get("passed") is True, d
rc = d.get("review_chain") or {}
assert rc.get("score", 0) >= 7, rc
cmp = rc.get("comparison") or {}
assert cmp.get("baseline", {}).get("review_wall_clock_min") == 31
assert cmp.get("target", {}).get("review_wall_clock_min_max") == 8
ops = d.get("op_counts") or {}
assert ops.get("readonly_subagent_present") == 1
assert ops.get("review_uvo_skip_enabled") == 1
print("benchmark review replay OK")
PY

echo "test-benchmark-review-replay passed"
