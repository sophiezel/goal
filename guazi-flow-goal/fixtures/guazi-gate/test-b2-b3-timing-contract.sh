#!/usr/bin/env bash
# B2: gate pre/post timing substeps + smoke→quality; B3: contract enrich + implement block on false
set -euo pipefail
export GOAL_ARTIFACT_MODE=repo_full
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_SCRIPTS:-${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts}"
GATE="$SCRIPTS/guazi-gate-stage.sh"
REC="$SCRIPTS/record-pipeline-timing.py"

echo "=== B2: plan pre records timing with phase substep ==="
REPO_ROOT=$(git -C "$DIR" rev-parse --show-toplevel)
mkdir -p "$REPO_ROOT/.cache"
TMP=$(mktemp -d "$REPO_ROOT/.cache/guazi-b2b3-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
repo="$TMP/repo"
TASK="$repo/docs/guazi-flow/plan-pre"
mkdir -p "$TASK/evidence"
cd "$repo"
git init -q
git config user.email "test@example.com"
git config user.name "test"
echo base > README.md
git add README.md && git commit -qm init
cp "$DIR/plan-good/index.md" "$TASK/"
bash "$GATE" --task-dir "$TASK" --project-root "$repo" --stage plan --pre --mode guazi >/dev/null
python3 -c "
import json
d=json.load(open('$TASK/evidence/pipeline-timing.json'))
ev=d['stages']['plan']['events']
assert any(e.get('event')=='start' and e.get('substep')=='pre' for e in ev), ev
assert any(e.get('event')=='end' and e.get('substep')=='pre' for e in ev), ev
print('timing_pre_ok')
"

echo "=== B2: smoke stage maps to quality in timing ==="
TASK2="$repo/docs/guazi-flow/smoke-map"
mkdir -p "$TASK2/evidence"
python3 "$REC" --task-dir "$TASK2" --project-root "$repo" --stage smoke --event start --substep pre >/dev/null
python3 -c "
import json
d=json.load(open('$TASK2/evidence/pipeline-timing.json'))
assert 'quality' in d['stages'] and 'smoke' not in d['stages']
print('smoke_map_ok')
"

echo "=== B3: skipped (guazi_flow_contract_enrich removed in v1.4 decouple) ==="

echo "OK b2-b3-timing-contract"
