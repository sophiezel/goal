#!/bin/bash
# benchmark-ci.sh — CI wrapper: run benchmark + compare vs baseline (v3 §10.3, §8.5 #4)
# Exits non-zero if review_chain score regresses (static replay gate).
# Wall-clock ≥25% reduction is verified via live XS replay (see p2-eval-runbook.md), not here.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE="${GOAL_PIPELINE_WORKSPACE:-$REPO_ROOT/../goal-pipeline-workspace}"
BASELINE_DIR="$WORKSPACE/baselines"

FIXTURE_PLAN="$REPO_ROOT/scripts/fixtures/guazi-flow-gate/plan-good"
FIXTURE_CHAIN="$REPO_ROOT/scripts/fixtures/guazi-flow-gate/chain-good"

POST_PLAN="$WORKSPACE/baselines/xs-v3-ci-post.json"
POST_CHAIN="$WORKSPACE/baselines/xs-v3-ci-post-review.json"
mkdir -p "$WORKSPACE/baselines"

echo "=== benchmark-ci: run post benchmark ==="
bash "$SCRIPT_DIR/benchmark-pipeline-replay.sh" --task-dir "$FIXTURE_PLAN" --output "$POST_PLAN" >/dev/null
bash "$SCRIPT_DIR/benchmark-pipeline-replay.sh" --task-dir "$FIXTURE_CHAIN" --output "$POST_CHAIN" >/dev/null

# Gate 1: post benchmark must pass
for f in "$POST_PLAN" "$POST_CHAIN"; do
  PASSED=$(python3 -c "import json; print(json.load(open('$f')).get('passed', False))")
  [[ "$PASSED" == "True" ]] || { echo "FAIL: benchmark $f did not pass"; exit 1; }
done
echo "OK: post benchmark passed"

# Gate 2: review_chain score must not regress vs baseline (if baseline exists)
for pair in "xs-v3-pre.json:xs-v3-ci-post.json" "xs-v3-pre-review.json:xs-v3-ci-post-review.json"; do
  PRE="${pair%%:*}"
  POST="${pair##*:}"
  PRE_PATH="$BASELINE_DIR/$PRE"
  POST_PATH="$WORKSPACE/baselines/$POST"
  if [[ -f "$PRE_PATH" ]]; then
    PRE_SCORE=$(python3 -c "import json; print(json.load(open('$PRE_PATH')).get('review_chain',{}).get('score',0))")
    POST_SCORE=$(python3 -c "import json; print(json.load(open('$POST_PATH')).get('review_chain',{}).get('score',0))")
    if [[ "$POST_SCORE" -lt "$PRE_SCORE" ]]; then
      echo "FAIL: review_chain score regression: $PRE ($PRE_SCORE) → $POST ($POST_SCORE)"
      exit 1
    fi
    echo "OK: review_chain score $PRE_SCORE → $POST_SCORE (no regression)"
  else
    echo "SKIP: baseline $PRE_PATH not found — run P0 baseline first"
  fi
done

echo "benchmark-ci passed"
