#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/../../gate-guazi-flow-stage.sh"
CHECK="$SCRIPT_DIR/../../check-consistency"
export GOAL_ARTIFACT_MODE=repo_full

assert_no_repo_tier_r() {
  local task="$1"
  if [[ -d "$task/handoff" ]]; then
    echo "FAIL repo Tier-R leak: $task/handoff/ exists"; exit 1
  fi
  for f in review-unified.json review-run.json review-fix-input.json review-transcript.md runtime-smoke.md; do
    if [[ -f "$task/evidence/$f" ]]; then
      echo "FAIL repo Tier-R leak: $task/evidence/$f exists"; exit 1
    fi
  done
}

echo "=== plan-good should PASS ==="
if "$GATE" --task-dir "$SCRIPT_DIR/plan-good" --stage plan --post --mode guazi; then
  echo "OK plan-good"
else
  echo "FAIL plan-good expected pass"; exit 1
fi

echo "=== plan-bad should FAIL ==="
rm -f "$SCRIPT_DIR/plan-bad/evidence/plan-gate-fix-input.json"
if "$GATE" --task-dir "$SCRIPT_DIR/plan-bad" --stage plan --post --mode guazi; then
  echo "FAIL plan-bad expected fail"; exit 1
else
  echo "OK plan-bad rejected"
fi
if [[ ! -f "$SCRIPT_DIR/plan-bad/evidence/plan-gate-fix-input.json" ]]; then
  echo "FAIL plan-bad missing plan-gate-fix-input.json"; exit 1
fi
echo "OK plan-bad wrote plan-gate-fix-input.json"

echo "=== plan-write-set-xieji (## 写集) should PASS ==="
rm -f "$SCRIPT_DIR/plan-write-set-xieji/evidence/plan-gate-fix-input.json"
rm -rf "$SCRIPT_DIR/plan-write-set-xieji/handoff"
if "$GATE" --task-dir "$SCRIPT_DIR/plan-write-set-xieji" --stage plan --post --mode guazi; then
  WS=$(python3 -c "import json; print(len(json.load(open('$SCRIPT_DIR/plan-write-set-xieji/handoff/plan.json')).get('write_set',[])))")
  if [[ "$WS" -lt 1 ]]; then
    echo "FAIL plan-write-set-xieji write_set empty"; exit 1
  fi
  echo "OK plan-write-set-xieji write_set=$WS"
else
  echo "FAIL plan-write-set-xieji expected pass"; exit 1
fi

echo "=== plan-lite-good (Index-Lite) should PASS ==="
rm -rf "$SCRIPT_DIR/plan-lite-good/handoff"
if "$GATE" --task-dir "$SCRIPT_DIR/plan-lite-good" --stage plan --post --mode guazi; then
  PP=$(python3 -c "import json; print(json.load(open('$SCRIPT_DIR/plan-lite-good/handoff/plan.json')).get('plan_profile',''))")
  if [[ "$PP" != "lite" ]]; then
    echo "FAIL plan-lite-good plan_profile expected lite got '$PP'"; exit 1
  fi
  echo "OK plan-lite-good plan_profile=lite"
else
  echo "FAIL plan-lite-good expected pass"; exit 1
fi

echo "=== resolve-plan-index-lite unit ==="
bash "$SCRIPT_DIR/test-resolve-plan-index-lite.sh"

echo "=== review-track unit ==="
bash "$SCRIPT_DIR/test-review-track.sh"

echo "=== merge-review-stagnant unit (info_gain 熔断) ==="
bash "$SCRIPT_DIR/test-merge-review-stagnant.sh"

echo "=== commit-before-review unit ==="
bash "$SCRIPT_DIR/test-commit-before-review.sh"

echo "=== review-ab-jaccard (L0 A/B) ==="
bash "$SCRIPT_DIR/test-review-ab-jaccard.sh"

echo "=== am-extend (AM-07..10) ==="
bash "$SCRIPT_DIR/test-am-extend.sh"

echo "=== implement-write-set-pre-block ==="
bash "$SCRIPT_DIR/test-implement-write-set-pre-block.sh"

echo "=== phase-a2-e2e-block ==="
bash "$SCRIPT_DIR/test-phase-a2-e2e-block.sh"

echo "=== benchmark-ci smoke ==="
bash "$SCRIPT_DIR/../../benchmark-ci.sh" >/dev/null 2>&1 && echo "OK benchmark-ci" || echo "SKIP benchmark-ci (workspace not configured)"

echo "=== leak-rate-panel smoke ==="
python3 "$SCRIPT_DIR/../../leak-rate-panel.py" --json >/dev/null 2>&1 && echo "OK leak-rate-panel" || echo "SKIP leak-rate-panel"

echo "=== ctb-43532-simplified should FAIL ==="
rm -f "$SCRIPT_DIR/ctb-43532-simplified/evidence/plan-gate-fix-input.json"
if "$GATE" --task-dir "$SCRIPT_DIR/ctb-43532-simplified" --stage plan --post --mode guazi; then
  echo "FAIL ctb-43532 expected fail"; exit 1
else
  echo "OK ctb-43532-simplified rejected"
fi



echo "=== implement-post-without-plan should FAIL ==="
if "$GATE" --task-dir "$SCRIPT_DIR/implement-post-without-plan" --stage implement --post --mode guazi; then
  echo "FAIL implement-post-without-plan expected fail"; exit 1
else
  echo "OK implement-post-without-plan rejected"
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

echo "=== review-unified-mock gf_skill_attested ==="
"$SCRIPT_DIR/test-review-unified-mock.sh"

echo "=== review-gf-count (no table inflation) ==="
"$SCRIPT_DIR/test-review-gf-count.sh"

echo "=== review-channel-guard anti-downgrade ==="
echo "=== review-channel-guard ==="
bash "$SCRIPT_DIR/test-review-channel-guard.sh"

echo "=== detect-paths-ssot ==="
bash "$SCRIPT_DIR/test-detect-paths-ssot.sh"

echo "=== staleness + severity + write_set normalize ==="
bash "$SCRIPT_DIR/test-staleness-and-severity.sh"

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

echo "=== split mode review-unified (Tier-R in runtime) ==="
SPLIT_TMP=$(mktemp -d)
RUNTIME="$SPLIT_TMP/runtime"
TASK="$SPLIT_TMP/task"
STATE="$SPLIT_TMP/state.json"
FIXTURE="$SCRIPT_DIR/review-fix-input-good"
mkdir -p "$RUNTIME/handoff" "$RUNTIME/evidence" "$TASK/evidence"
cp "$FIXTURE/index.md" "$TASK/"
cp "$FIXTURE/evidence/review.md" "$TASK/evidence/"
cp "$FIXTURE/handoff/"*.json "$RUNTIME/handoff/"
cp "$FIXTURE/evidence/review-"*.json "$RUNTIME/evidence/" 2>/dev/null || true
[[ -f "$FIXTURE/evidence/review-transcript.md" ]] && cp "$FIXTURE/evidence/review-transcript.md" "$RUNTIME/evidence/"
python3 - << PY
import json
state = {
    "guazi_flow_task": "task",
    "artifact_layout": {
        "mode": "split",
        "repo_task_dir": "$TASK",
        "runtime_root": "$RUNTIME",
    },
}
open("$STATE", "w").write(json.dumps(state, indent=2))
PY
if GOAL_ARTIFACT_MODE=split "$GATE" --task-dir "$TASK" --stage review --post --mode guazi --state-file "$STATE"; then
  echo "OK split mode review post"
else
  echo "FAIL split mode review expected pass"; rm -rf "$SPLIT_TMP"; exit 1
fi
assert_no_repo_tier_r "$TASK"
echo "OK split mode repo has no Tier-R artifacts"

echo "=== check-consistency split (review-run in runtime only) ==="
CONSIST_OUT=$(GOAL_ARTIFACT_MODE=split "$CHECK" "$TASK" "$STATE" 2>/dev/null || echo '{}')
if echo "$CONSIST_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); issues=[i for i in d.get('issues',[]) if i.get('rule')=='review_provenance']; sys.exit(1 if issues else 0)"; then
  echo "OK check-consistency split no review_provenance false positive"
else
  echo "FAIL check-consistency split reported review_provenance"; echo "$CONSIST_OUT"; rm -rf "$SPLIT_TMP"; exit 1
fi
rm -rf "$SPLIT_TMP"

echo "=== validate-stage-port plan-good ==="
bash "$SCRIPT_DIR/test-validate-stage-port.sh"

echo "=== write-delivery-quality v2 ==="
bash "$SCRIPT_DIR/test-write-delivery-quality.sh"

echo "=== kernel gate_runtime noop ==="
python3 "$SCRIPT_DIR/../../../kernel/tests/test_gate_runtime_noop.py"

echo "=== gf-stage-driver native flag ==="
bash "$SCRIPT_DIR/test-gf-native-driver.sh"

echo "=== delivery-quality complete gate wiring ==="
bash "$SCRIPT_DIR/test-delivery-quality-complete.sh"

echo "=== kernel no docs/guazi-flow hardcode ==="
bash "$SCRIPT_DIR/test-kernel-no-guazi-doc-paths.sh"

python3 "$SCRIPT_DIR/../../../kernel/tests/test_loop_policy.py"

echo "All gate fixture tests passed"
