#!/bin/bash
# test-argus-enrich-plan.sh — L10 manifest from plan.json write_set only
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
FIX="$DIR/contract-iq10-good"
OUT=$(mktemp -d)
mkdir -p "$OUT"
python3 "$SCRIPTS/argus_enrich_plan.py" \
  --task-dir "$FIX" \
  --handoff-dir "$FIX/handoff" \
  --out "$OUT/argus-scenario-manifest.json" \
  --format text
python3 - "$OUT/argus-scenario-manifest.json" << 'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
assert doc.get("schema_version") in (1, 2)
sc = doc.get("scenarios") or []
assert len(sc) >= 1
text = json.dumps(doc)
for bad in ("suspectedDealer", "CTB-", "jian-h5", "appointId"):
    assert bad not in text, f"project literal leaked: {bad}"
ids = {s["id"] for s in sc}
assert "service-layer" in ids or "page-smoke" in ids, ids
print("argus-enrich-plan OK", len(sc), "scenarios")
PY
rm -rf "$OUT"
echo "test-argus-enrich-plan passed"
