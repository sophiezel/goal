#!/bin/bash
# test-review-rounds-exhausted.sh — P0: business fix rounds beyond GOAL_REVIEW_MAX_ROUNDS → blocked_user_decision
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Seed a not_pass unified review with a business blocker.
cp -R "$DIR/review-unified-good/." "$TMP/"

# Simulate prior fix-input at round == max (so next merge → round max+1).
export GOAL_REVIEW_MAX_ROUNDS=2
cat > "$TMP/evidence/review-fix-input.json" << 'JSON'
{
  "schema_version": 1,
  "round": 2,
  "merged_result": "not_pass",
  "action": "fix_and_rerun_review",
  "issues": [{"id":"G01","channel":"goal","severity":"blocker","summary":"prev","root_cause":"implement_error"}],
  "next_steps": [],
  "provenance": {}
}
JSON

python3 "$SCRIPTS/merge_review_core.py" "$TMP" "$TMP/evidence/review-unified.json" >/dev/null

ACTION=$(python3 -c "import json; print(json.load(open('$TMP/evidence/review-fix-input.json'))['action'])")
EXHAUSTED=$(python3 -c "import json; print(json.load(open('$TMP/evidence/review-fix-input.json')).get('rounds_exhausted'))")
ROUND=$(python3 -c "import json; print(json.load(open('$TMP/evidence/review-fix-input.json'))['round'])")

[[ "$ROUND" == "3" ]] || { echo "FAIL expected round=3 got $ROUND"; exit 1; }
[[ "$EXHAUSTED" == "True" ]] || { echo "FAIL expected rounds_exhausted=True got $EXHAUSTED"; exit 1; }
[[ "$ACTION" == "blocked_user_decision" ]] || { echo "FAIL expected blocked_user_decision got $ACTION"; exit 1; }

echo "OK rounds exhausted → blocked_user_decision (round=$ROUND, max=$GOAL_REVIEW_MAX_ROUNDS)"

# Below the cap it must NOT force blocked.
export GOAL_REVIEW_MAX_ROUNDS=10
rm -f "$TMP/evidence/review-fix-input.json"
python3 "$SCRIPTS/merge_review_core.py" "$TMP" "$TMP/evidence/review-unified.json" >/dev/null
ACTION2=$(python3 -c "import json; print(json.load(open('$TMP/evidence/review-fix-input.json'))['action'])")
EXH2=$(python3 -c "import json; print(json.load(open('$TMP/evidence/review-fix-input.json')).get('rounds_exhausted'))")
[[ "$EXH2" == "False" ]] || { echo "FAIL round 1 should not be exhausted"; exit 1; }
[[ "$ACTION2" == "fix_and_rerun_review" ]] || { echo "FAIL round 1 expected fix_and_rerun_review got $ACTION2"; exit 1; }
echo "OK under cap stays fix_and_rerun_review"

echo "test-review-rounds-exhausted passed"
