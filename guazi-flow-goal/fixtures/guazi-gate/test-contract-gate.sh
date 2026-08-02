#!/bin/bash
# test-contract-gate.sh — PQ-10 / IQ-10 fixture tests
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts"
PQ="$SCRIPTS/plan-quality-gate.py"
IQ="$SCRIPTS/contract-conformance-check.py"
BAD="$DIR/contract-pq10-bad"
GOOD="$DIR/contract-iq10-good"

echo "PQ-10: contract-pq10-bad should fail"
PQ_OUT=$(mktemp)
if ! python3 "$PQ" --task-dir "$BAD" --tier strict --json > "$PQ_OUT" 2>/dev/null; then
  :
fi
if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if not d.get('passed') else 1)" "$PQ_OUT"; then
  echo "OK PQ-10 bad fixture blocked"
else
  echo "FAIL: expected contract-pq10-bad to fail" >&2
  rm -f "$PQ_OUT"
  exit 1
fi
rm -f "$PQ_OUT"

echo "IQ-10: contract-iq10-good should pass"
HASH=$(python3 -c "
import sys
sys.path.insert(0, '$SCRIPTS')
from contract_parser import api_mapping_table_hash
print(api_mapping_table_hash(open('$GOOD/index.md', encoding='utf-8').read()))
")
python3 -c "import json; p=json.load(open('$GOOD/handoff/plan.json')); p['api_mapping_table_hash']='$HASH'; json.dump(p, open('$GOOD/handoff/plan.json','w'), indent=2)"

python3 "$IQ" --task-dir "$GOOD" --repo-root "$GOOD" --json
echo "IQ-10: mismatch should fail"
cat > "$GOOD/src/services/demo.ts" << 'TS'
export function fetchDetail() {
  return createRequest({ key: 'CSP_BAD', uri: '/external/demo/detail', source: 100 });
}
TS
if python3 "$IQ" --task-dir "$GOOD" --repo-root "$GOOD" --json 2>/dev/null; then
  echo "FAIL: expected wrong key to fail" >&2
  exit 1
fi
# restore
cat > "$GOOD/src/services/demo.ts" << 'TS'
export function fetchDetail() {
  return createRequest({ key: 'CSP_GOOD', uri: '/external/demo/detail', source: 100 });
}
TS

echo "IQ-10: Tier-R handoff via GOAL_HANDOFF_DIR when repo handoff/plan.json absent"
SPLIT_HO=$(mktemp -d)
cp "$GOOD/handoff/plan.json" "$SPLIT_HO/plan.json"
rm -f "$GOOD/handoff/plan.json"
export GOAL_HANDOFF_DIR="$SPLIT_HO"
python3 "$IQ" --task-dir "$GOOD" --repo-root "$GOOD" --json
unset GOAL_HANDOFF_DIR
cp "$SPLIT_HO/plan.json" "$GOOD/handoff/plan.json"
rm -rf "$SPLIT_HO"

echo "IQ-10: createRequest factory pattern (key + req({ uri }))"
FACTORY="$DIR/contract-iq10-factory"
HASH_F=$(python3 -c "
import sys
sys.path.insert(0, '$SCRIPTS')
from contract_parser import api_mapping_table_hash
print(api_mapping_table_hash(open('$FACTORY/index.md', encoding='utf-8').read()))
")
python3 -c "import json; p=json.load(open('$FACTORY/handoff/plan.json')); p['api_mapping_table_hash']='$HASH_F'; json.dump(p, open('$FACTORY/handoff/plan.json','w'), indent=2)"
python3 "$IQ" --task-dir "$FACTORY" --repo-root "$FACTORY" --json

echo "contract gate tests passed"
