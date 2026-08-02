#!/usr/bin/env bash
# B2: gate pre/post timing substeps + smoke→quality (B3 contract enrich removed in goal v1.4)
set -euo pipefail
export GOAL_ARTIFACT_MODE=repo_full
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
GATE="$SCRIPTS/gate-goal-stage.sh"
REC="$SCRIPTS/record-pipeline-timing.py"

init_isolated_repo() {
  local root="$1"
  mkdir -p "$root"
  cd "$root"
  git init -q
  git config user.email "test@example.com"
  git config user.name "test"
  echo base > README.md
  git add README.md && git commit -qm "init"
}

echo "=== B2: plan pre records timing with phase substep ==="
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
init_isolated_repo "$REPO"
TASK="$REPO/plan-pre"
mkdir -p "$TASK/evidence"
cp "$DIR/plan-good/index.md" "$TASK/"
git add plan-pre && git commit -qm "add plan-pre fixture"
bash "$GATE" --task-dir "$TASK" --stage plan --pre --project-root "$REPO" >/dev/null
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

echo "=== B3: skipped (guazi contract enrich not in goal-pipeline v1.4) ==="

echo "OK b2-b3-timing-contract"
