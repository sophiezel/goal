#!/bin/bash
# test-review-ab-jaccard.sh — merge parity: same unified input → stable goal issues (v1.4 single-only)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
MERGE="$SCRIPTS/merge_review_core.py"
FIXTURE="$DIR/review-unified-good"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export GOAL_ARTIFACT_MODE=repo_full

for label in run1 run2; do
  mkdir -p "$TMP/$label/task/evidence" "$TMP/$label/task/handoff"
  cp "$FIXTURE/evidence/review-unified.json" "$TMP/$label/task/evidence/review-unified.json"
  echo '{"run_id":"r1","packet_hash":"p1"}' > "$TMP/$label/task/evidence/review-run.json"
  echo '---' > "$TMP/$label/task/evidence/review.md"
  GOAL_STATE_FILE="$TMP/$label/state.json" python3 "$MERGE" "$TMP/$label/task" "$TMP/$label/task/evidence/review-unified.json" >/dev/null
done

python3 - "$TMP/run1/task/evidence/review-fix-input.json" "$TMP/run2/task/evidence/review-fix-input.json" <<'PY'
import json, sys
d1 = json.load(open(sys.argv[1]))
d2 = json.load(open(sys.argv[2]))
def keys(d):
    return {("%s|%s" % (i.get("id",""), i.get("summary","")[:80])) for i in d.get("issues",[])}
k1, k2 = keys(d1), keys(d2)
inter = k1 & k2
union = k1 | k2
jaccard = len(inter) / len(union) if union else 1.0
assert jaccard >= 0.95, f"Jaccard {jaccard} < 0.95"
print(f"OK: merge parity Jaccard={jaccard:.4f}")
PY

echo "test-review-ab-jaccard passed"
