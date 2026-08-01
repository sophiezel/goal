#!/usr/bin/env bash
# B2: gate pre/post timing substeps + smoke→quality; B3: contract enrich + implement block on false
set -euo pipefail
export GOAL_ARTIFACT_MODE=repo_full
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
GATE="$SCRIPTS/gate-guazi-flow-stage.sh"
ENRICH="$SCRIPTS/guazi_flow_contract_enrich.py"
REC="$SCRIPTS/record-pipeline-timing.py"

echo "=== B2: plan pre records timing with phase substep ==="
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TASK="$TMP/plan-pre"
mkdir -p "$TASK/evidence"
cp "$DIR/plan-good/index.md" "$TASK/"
bash "$GATE" --task-dir "$TASK" --stage plan --pre --mode guazi >/dev/null
python3 -c "
import json
d=json.load(open('$TASK/evidence/pipeline-timing.json'))
ev=d['stages']['plan']['events']
assert any(e.get('event')=='start' and e.get('substep')=='pre' for e in ev), ev
assert any(e.get('event')=='end' and e.get('substep')=='pre' for e in ev), ev
print('timing_pre_ok')
"

echo "=== B2: smoke stage maps to quality in timing ==="
TASK2="$TMP/smoke-map"
mkdir -p "$TASK2/evidence"
python3 "$REC" --task-dir "$TASK2" --stage smoke --event start --substep pre >/dev/null
python3 -c "
import json
d=json.load(open('$TASK2/evidence/pipeline-timing.json'))
assert 'quality' in d['stages'] and 'smoke' not in d['stages']
print('smoke_map_ok')
"

echo "=== B3: contract enrich + implement block when state false ==="
TASK3="$TMP/b3"
mkdir -p "$TASK3/handoff" "$TASK3/evidence"
cp "$DIR/plan-good/index.md" "$TASK3/"
grep -q 'guazi-flow-implement' "$TASK3/index.md" || echo '| implement | guazi-flow-implement | pass |' >> "$TASK3/index.md"
cat > "$TASK3/state.json" <<'JSON'
{"guazi_flow_contract_enriched": false}
JSON
cat > "$TASK3/handoff/plan.json" <<'JSON'
{
  "write_set": ["routes.ts"],
  "contract_enriched": false,
  "gate": {"passed_at": "2026-01-01T00:00:00Z", "post_exit_code": 0}
}
JSON
if bash "$GATE" --task-dir "$TASK3" --stage implement --pre --mode guazi --state-file "$TASK3/state.json" 2>/tmp/b3-pre.log; then
  echo "FAIL: implement pre should block contract_enriched=false"; exit 1
fi
grep -q "contract enrich not satisfied" /tmp/b3-pre.log || { cat /tmp/b3-pre.log; exit 1; }

echo "=== B3: plan post enriches index ==="
TASK4="$TMP/plan-post"
mkdir -p "$TASK4/handoff" "$TASK4/evidence"
cp "$DIR/plan-write-set-xieji/index.md" "$TASK4/"
rm -rf "$TASK4/handoff"
bash "$GATE" --task-dir "$TASK4" --stage plan --post --mode guazi >/dev/null
python3 -c "
import json
plan=json.load(open('$TASK4/handoff/plan.json'))
assert plan.get('contract_enriched') is True
text=open('$TASK4/index.md').read()
assert '### allowed_patterns' in text
print('plan_post_enrich_ok')
"

echo "OK b2-b3-timing-contract"
