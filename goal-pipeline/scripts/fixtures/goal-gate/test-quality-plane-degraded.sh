#!/bin/bash
# test-quality-plane-degraded.sh — P0: complete path must run quality_plane_check (forged/degraded blocked)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
QPC="$SCRIPTS/quality_plane_check.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/evidence" "$TMP/handoff"

# Case 1: forged review.md pass without review-run/unified → blocked.
cat > "$TMP/evidence/review.md" << 'MD'
---
stage: review
result: pass
---
MD
OUT=$(python3 "$QPC" --task-dir "$TMP" --mode complete --format text 2>&1 || true)
echo "$OUT" | grep -q "review_forged" || { echo "FAIL expected review_forged code:"; echo "$OUT"; exit 1; }
echo "OK forged review blocked by quality_plane_check"

# Case 2: degraded channel but review.md claims full pass → review_degraded_as_pass.
cat > "$TMP/evidence/review-run.json" << 'JSON'
{"run_id":"r1","provider":"deterministic"}
JSON
cat > "$TMP/evidence/review-unified.json" << 'JSON'
{"result":"pass","issues":[]}
JSON
cat > "$TMP/evidence/review-channel-degraded.json" << 'JSON'
{"separation":"degraded","review_mode":"deterministic_scope_only"}
JSON
cat > "$TMP/evidence/review.md" << 'MD'
---
stage: review
result: pass
---
MD
OUT=$(python3 "$QPC" --task-dir "$TMP" --mode complete --format text 2>&1 || true)
echo "$OUT" | grep -q "review_degraded_as_pass" || { echo "FAIL expected review_degraded_as_pass code:"; echo "$OUT"; exit 1; }
echo "OK degraded-as-pass blocked by quality_plane_check"

# Case 3: honest degraded (confidence: degraded) → allowed.
cat > "$TMP/evidence/review.md" << 'MD'
---
stage: review
result: pass
confidence: degraded
---
MD
python3 "$QPC" --task-dir "$TMP" --mode complete >/dev/null 2>&1 \
  || { echo "FAIL honest degraded pass should be allowed"; exit 1; }
echo "OK honest degraded (confidence tagged) allowed"

echo "test-quality-plane-degraded passed"
