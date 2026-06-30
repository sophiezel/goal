#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/../../gate-guazi-flow-stage.sh"

echo "=== plan-good should PASS ==="
if "$GATE" --task-dir "$SCRIPT_DIR/plan-good" --stage plan --post --mode guazi; then
  echo "OK plan-good"
else
  echo "FAIL plan-good expected pass"; exit 1
fi

echo "=== plan-bad should FAIL ==="
if "$GATE" --task-dir "$SCRIPT_DIR/plan-bad" --stage plan --post --mode guazi; then
  echo "FAIL plan-bad expected fail"; exit 1
else
  echo "OK plan-bad rejected"
fi

echo "=== ctb-43532-simplified should FAIL ==="
if "$GATE" --task-dir "$SCRIPT_DIR/ctb-43532-simplified" --stage plan --post --mode guazi; then
  echo "FAIL ctb-43532 expected fail"; exit 1
else
  echo "OK ctb-43532-simplified rejected"
fi


echo "=== smoke-good should PASS post ==="
if "$GATE" --task-dir "$SCRIPT_DIR/smoke-good" --stage smoke --post --mode guazi; then
  echo "OK smoke-good"
else
  echo "FAIL smoke-good expected pass"; exit 1
fi

echo "=== review-fake (no review-run) should FAIL post ==="
mkdir -p "$SCRIPT_DIR/review-fake-good/handoff"
echo '{"stage":"implement","gate":{"passed_at":"2026-01-01T00:00:00Z"}}' > "$SCRIPT_DIR/review-fake-good/handoff/implement.json"
echo '{}' > "$SCRIPT_DIR/review-fake-good/handoff/review-packet.json"
if "$GATE" --task-dir "$SCRIPT_DIR/review-fake-good" --stage review --post --mode guazi; then
  echo "FAIL review-fake expected fail (no review-run.json)"; exit 1
else
  echo "OK review-fake rejected"
fi

echo "=== smoke dev_cmd boundary ==="
"$SCRIPT_DIR/test-smoke-resolve.sh"

echo "=== macOS duration_ms sanity ==="
python3 -c "import json,subprocess,os,tempfile; d=tempfile.mkdtemp(); os.makedirs(d+'/task/evidence'); open(d+'/package.json','w').write('{}'); r=subprocess.run(['bash','/Users/xuwei/Profession/goal/goal-pipeline/scripts/runtime-smoke.sh','--repo-root',d,'--task-dir',d+'/task','--skip-install'],capture_output=True,text=True); j=json.loads(r.stdout.strip() or '{}'); assert 'duration_ms' in j or j.get('result')=='skipped'; print('OK macOS duration field')"

echo "=== review-dual-mock gf_skill_attested ==="
"$SCRIPT_DIR/test-review-dual-mock.sh"

echo "=== review-gf-count (no table inflation) ==="
"$SCRIPT_DIR/test-review-gf-count.sh"

echo "=== validate-pipeline-chain chain-good ==="
VALIDATOR="$SCRIPT_DIR/../../validate-pipeline-chain.sh"
if "$VALIDATOR" --task-dir "$SCRIPT_DIR/chain-good"; then
  echo "OK chain-good"
else
  echo "FAIL chain-good"; exit 1
fi


echo "=== review-fix-input-good should PASS post ==="
if "$GATE" --task-dir "$SCRIPT_DIR/review-fix-input-good" --stage review --post --mode guazi; then
  echo "OK review-fix-input-good"
else
  echo "FAIL review-fix-input-good expected pass"; exit 1
fi

echo "=== review-fix-input-not-pass should FAIL post ==="
if "$GATE" --task-dir "$SCRIPT_DIR/review-fix-input-not-pass" --stage review --post --mode guazi; then
  echo "FAIL review-fix-input-not-pass expected fail"; exit 1
else
  echo "OK review-fix-input-not-pass rejected"
fi


echo "=== verify-review JSON validity ==="
python3 -c "import json,subprocess; r=subprocess.run(['bash','/Users/xuwei/Profession/goal/goal-pipeline/scripts/verify-review.sh','$SCRIPT_DIR/plan-good','src/', 'json'],capture_output=True,text=True); json.loads(r.stdout); print('OK verify-review JSON valid')"

echo "All gate fixture tests passed"
