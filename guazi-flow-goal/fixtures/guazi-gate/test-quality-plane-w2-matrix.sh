#!/bin/bash
# test-quality-plane-w2-matrix.sh — W2 matrix_rows_unsatisfied vs matrix_rows_waived (#10, #16 C1)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_SCRIPTS:-${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts}"
QPC="$SCRIPTS/quality_plane_check.py"
W2="$SCRIPTS/w2_matrix_bookkeeping.py"
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
cat > "$TMP/evidence/verification-oracle.json" << 'JSON'
{"overall":"pass"}
JSON
cat > "$TMP/evidence/contract-conformance.json" << 'JSON'
{"passed":true}
JSON

# Case 1: unsatisfied row → leakage.matrix_rows_unsatisfied; complete still ok
cat > "$TMP/handoff/plan.json" << 'JSON'
{
  "matrix_satisfaction": {
    "ok": false,
    "rows": [
      {"id": "C05", "status": "fail", "verify_type": "display_assert", "evidence": "manual-check"}
    ]
  }
}
JSON
python3 "$QPC" --task-dir "$TMP" --mode complete --format json > "$TMP/qpc1.json"
python3 -c "
import json
d=json.load(open('$TMP/qpc1.json'))
leak=d.get('leakage') or {}
uns=leak.get('matrix_rows_unsatisfied') or []
ids=[u['row_id'] if isinstance(u,dict) else u for u in uns]
assert 'C05' in ids, leak
assert not leak.get('matrix_rows_waived'), leak
assert d.get('ok') is True, d
"

# Case 2: waived + separation → matrix_rows_waived only
cat > "$TMP/handoff/plan.json" << 'JSON'
{
  "matrix_satisfaction": {
    "ok": true,
    "rows": [
      {
        "id": "C07",
        "status": "waived",
        "verify_type": "am_ratchet",
        "separation_ref": "evidence/am-waive-separation.json",
        "waive_reason": "PM accepted deferral"
      }
    ]
  }
}
JSON
python3 "$QPC" --task-dir "$TMP" --mode complete --format json > "$TMP/qpc2.json"
python3 -c "
import json
d=json.load(open('$TMP/qpc2.json'))
leak=d.get('leakage') or {}
waived=leak.get('matrix_rows_waived') or []
assert any(w.get('row_id')=='C07' for w in waived if isinstance(w,dict)), leak
assert not leak.get('matrix_rows_unsatisfied'), leak
"

# Case 3: waive without separation → unsatisfied (#16)
cat > "$TMP/handoff/plan.json" << 'JSON'
{
  "matrix_satisfaction": {
    "rows": [
      {"id": "C08", "status": "waived", "waive_reason": "no separation"}
    ]
  }
}
JSON
python3 "$W2" --handoff-dir "$TMP/handoff" --goal-evidence-dir "$TMP/evidence" > "$TMP/w2.json"
python3 -c "
import json
d=json.load(open('$TMP/w2.json'))
uns=d.get('matrix_rows_unsatisfied') or []
assert any(r.get('row_id')=='C08' for r in uns), d
"

echo "OK W2 matrix unsatisfied vs waived separation"
echo "test-quality-plane-w2-matrix passed"
