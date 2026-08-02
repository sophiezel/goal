#!/bin/bash
# test-merge-review-stagnant.sh — info_gain 熔断 → blocked_stagnant (v3 §8.3a)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
MERGE="$SCRIPTS/merge_review_core.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export GOAL_ARTIFACT_MODE=repo_full

# Set up task dir with evidence + handoff
mkdir -p "$TMP/task/evidence" "$TMP/task/handoff"

# Round 1: 3 blockers, no prev → info_gain=0 (no prev_blockers, cur>0), stagnant_rounds=1
cat > "$TMP/task/evidence/review-unified.json" <<'EOF'
{
  "result": "not_pass",
  "issues": [
    {"channel": "goal", "severity": "blocker", "file": "src/a.ts", "summary": "bug1", "root_cause": "implement_error"},
    {"channel": "goal", "severity": "blocker", "file": "src/b.ts", "summary": "bug2", "root_cause": "implement_error"},
    {"channel": "goal", "severity": "blocker", "file": "src/c.ts", "summary": "bug3", "root_cause": "implement_error"}
  ]
}
EOF
echo '{"run_id":"r1","packet_hash":"p1"}' > "$TMP/task/evidence/review-run.json"
echo '---' > "$TMP/task/evidence/review.md"

GOAL_STATE_FILE="$TMP/state.json" python3 "$MERGE" "$TMP/task" "$TMP/task/evidence/review-unified.json" >/dev/null 2>&1 || true
R1=$(python3 -c "import json; d=json.load(open('$TMP/task/evidence/review-fix-input.json')); print(d['action'], d['info_gain'], d['stagnant_rounds'], d['stagnant_blocked'])")
echo "Round 1: $R1"
[[ "$R1" == "fix_and_rerun_review 0.0 1 False" ]] || { echo "FAIL round1 expected 'fix_and_rerun_review 0.0 1 False' got '$R1'"; exit 1; }

# Round 2: same 3 blockers (no reduction) → info_gain=0.0, stagnant_rounds=2 → blocked_stagnant
cat > "$TMP/task/evidence/review-unified.json" <<'EOF'
{
  "result": "not_pass",
  "issues": [
    {"channel": "goal", "severity": "blocker", "file": "src/a.ts", "summary": "bug1", "root_cause": "implement_error"},
    {"channel": "goal", "severity": "blocker", "file": "src/b.ts", "summary": "bug2", "root_cause": "implement_error"},
    {"channel": "goal", "severity": "blocker", "file": "src/c.ts", "summary": "bug3", "root_cause": "implement_error"}
  ]
}
EOF
GOAL_STATE_FILE="$TMP/state.json" python3 "$MERGE" "$TMP/task" "$TMP/task/evidence/review-unified.json" >/dev/null 2>&1 || true
R2=$(python3 -c "import json; d=json.load(open('$TMP/task/evidence/review-fix-input.json')); print(d['action'], d['info_gain'], d['stagnant_rounds'], d['stagnant_blocked'])")
echo "Round 2: $R2"
[[ "$R2" == "blocked_stagnant 0.0 2 True" ]] || { echo "FAIL round2 expected 'blocked_stagnant 0.0 2 True' got '$R2'"; exit 1; }

# Round 3 (recovery): 1 blocker (reduction from 3) → info_gain=0.667, stagnant_rounds=0
cat > "$TMP/task/evidence/review-unified.json" <<'EOF'
{
  "result": "not_pass",
  "issues": [
    {"channel": "goal", "severity": "blocker", "file": "src/a.ts", "summary": "bug1", "root_cause": "implement_error"}
  ]
}
EOF
GOAL_STATE_FILE="$TMP/state.json" python3 "$MERGE" "$TMP/task" "$TMP/task/evidence/review-unified.json" >/dev/null 2>&1 || true
R3=$(python3 -c "import json; d=json.load(open('$TMP/task/evidence/review-fix-input.json')); print(d['action'], d['info_gain'], d['stagnant_rounds'])")
echo "Round 3: $R3"
[[ "$R3" == "fix_and_rerun_review 0.6667 0" ]] || { echo "FAIL round3 expected 'fix_and_rerun_review 0.6667 0' got '$R3'"; exit 1; }

# Infra-only exempt: ADP-ERR should NOT trigger stagnant
cat > "$TMP/task/evidence/review-unified.json" <<'EOF'
{
  "result": "review_undetermined",
  "issues": [
    {"channel": "goal", "severity": "blocker", "id": "ADP-ERR-1", "file": "", "summary": "channel unreachable", "root_cause": "infra_channel"}
  ]
}
EOF
GOAL_STATE_FILE="$TMP/state.json" python3 "$MERGE" "$TMP/task" "$TMP/task/evidence/review-unified.json" >/dev/null 2>&1 || true
RI=$(python3 -c "import json; d=json.load(open('$TMP/task/evidence/review-fix-input.json')); print(d['action'], d['stagnant_blocked'])")
echo "Infra: $RI"
[[ "$RI" == "switch_to_cursor_task False" ]] || { echo "FAIL infra expected 'switch_to_cursor_task False' got '$RI'"; exit 1; }

echo "test-merge-review-stagnant passed"
