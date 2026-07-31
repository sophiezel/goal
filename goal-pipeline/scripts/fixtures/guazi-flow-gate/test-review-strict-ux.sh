#!/bin/bash
# test-review-strict-ux.sh — strict tier surfaces open L10; standard tier does not
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
RSU="$SCRIPTS/review_strict_ux.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/handoff" "$TMP/evidence"
cat > "$TMP/handoff/argus-scenario-manifest.json" << 'JSON'
{
  "schema_version": 1,
  "scenarios": [{"id": "page-smoke", "severity": "soft", "w1_status": "open"}]
}
JSON
cat > "$TMP/evidence/ux-scan.json" << 'JSON'
{
  "schema_version": 1,
  "findings": [{"id": "UX-D1", "severity": "warn", "w1_status": "open"}]
}
JSON
cat > "$TMP/state-standard.json" << 'JSON'
{"quality_policy": {"tier": "standard"}}
JSON
cat > "$TMP/state-strict.json" << 'JSON'
{"quality_policy": {"tier": "strict"}}
JSON

COUNT=$(python3 "$RSU" --handoff-dir "$TMP/handoff" --goal-evidence-dir "$TMP/evidence" \
  --state-file "$TMP/state-standard.json" | python3 -c "import json,sys; print(json.load(sys.stdin)['count'])")
test "$COUNT" -eq 0 || { echo "FAIL standard tier should have 0 strict UX issues, got $COUNT"; exit 1; }

COUNT=$(python3 "$RSU" --handoff-dir "$TMP/handoff" --goal-evidence-dir "$TMP/evidence" \
  --state-file "$TMP/state-strict.json" | python3 -c "import json,sys; print(json.load(sys.stdin)['count'])")
test "$COUNT" -ge 2 || { echo "FAIL strict tier expected L10+ux-scan issues, got $COUNT"; exit 1; }

echo "test-review-strict-ux passed"
