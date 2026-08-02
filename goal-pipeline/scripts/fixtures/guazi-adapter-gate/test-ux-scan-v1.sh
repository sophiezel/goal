#!/bin/bash
# test-ux-scan-v1.sh — minimal ux-scan v1 fixture (generic sample, no host literals)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
SAMPLE="$(cd "$DIR/../ux-scan-sample" && pwd)"
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

python3 "$SCRIPTS/ux_scan_v1.py" \
  --task-dir "$SAMPLE" \
  --repo-root "$SAMPLE" \
  --project-root "$SAMPLE" \
  --format text 2>&1 | grep -q "ux_scan_v1"

SCAN="$SAMPLE/evidence/ux-scan.json"
test -f "$SCAN" || { echo "FAIL missing ux-scan.json"; exit 1; }
python3 - "$SCAN" << 'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
assert doc.get("schema_version") == 1
assert doc.get("mode") == "warn_only"
assert "UX-D1" in doc.get("coverage", [])
assert doc.get("finding_count", 0) >= 1
print("OK ux_scan_v1 fixture", doc["finding_count"], "findings")
PY

echo "test-ux-scan-v1 passed"
