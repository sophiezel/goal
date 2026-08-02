#!/bin/bash
# test-merge-review-zh.sh — merge_review_core annex 中文化
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
FIX="$DIR/review-unified-good"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cp -R "$FIX/." "$TMP/"
export GOAL_ARTIFACT_MODE=repo_full
# merge in place on temp copy (avoid mutating fixture)
python3 "$SCRIPTS/merge_review_core.py" "$TMP" "$TMP/evidence/review-unified.json"

grep -q "goal 通道结果" "$TMP/evidence/review.md" || { echo "missing zh annex header"; exit 1; }
grep -q "严重程度" "$TMP/evidence/review.md" || { echo "missing zh table header"; exit 1; }
grep -q "通道 | 结果" "$TMP/evidence/review-transcript.md" || { echo "missing zh transcript"; exit 1; }

echo "test-merge-review-zh passed"
