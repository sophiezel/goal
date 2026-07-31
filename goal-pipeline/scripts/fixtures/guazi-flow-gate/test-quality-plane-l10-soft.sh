#!/bin/bash
# test-quality-plane-l10-soft.sh — B3: soft+open L10 rows must not block complete
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
QPC="$SCRIPTS/quality_plane_check.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/evidence" "$TMP/handoff"
cat > "$TMP/evidence/review-run.json" << 'JSON'
{"run_id":"r1"}
JSON
cat > "$TMP/evidence/review-unified.json" << 'JSON'
{"result":"pass","issues":[]}
JSON
cat > "$TMP/evidence/review.md" << 'MD'
---
stage: review
result: pass
---
MD
cat > "$TMP/handoff/argus-scenario-manifest.json" << 'JSON'
{
  "schema_version": 1,
  "scenarios": [
    {"id": "page-smoke", "severity": "soft", "w1_status": "open"},
    {"id": "hard-gap", "severity": "hard", "w1_status": "open"}
  ]
}
JSON

OUT=$(python3 "$QPC" --task-dir "$TMP" --mode complete --format text 2>&1 || true)
echo "$OUT" | grep -q "hard-gap" || { echo "FAIL expected hard L10 row to block:"; echo "$OUT"; exit 1; }
echo "$OUT" | grep -q "page-smoke" && { echo "FAIL soft open row should not block complete:"; echo "$OUT"; exit 1; }

cat > "$TMP/handoff/argus-scenario-manifest.json" << 'JSON'
{
  "schema_version": 1,
  "scenarios": [
    {"id": "page-smoke", "severity": "soft", "w1_status": "open"}
  ]
}
JSON
python3 "$QPC" --task-dir "$TMP" --mode complete >/dev/null 2>&1 \
  || { echo "FAIL only soft+open manifest should pass complete quality_plane_check"; exit 1; }
echo "OK L10 soft+open allowed at complete"
echo "test-quality-plane-l10-soft passed"
