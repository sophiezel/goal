#!/bin/bash
# test-review-track.sh — review_track.py resolves single/dual correctly (B8 default single)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
RT="$SCRIPTS/review_track.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Test 1: default (no env, no state) → single (B8)
TRACK=$(python3 "$RT" --format track)
[[ "$TRACK" == "single" ]] || { echo "FAIL: default expected single got $TRACK"; exit 1; }
echo "OK: default → single"

# Test 2: GOAL_REVIEW_TRACK=single → single
TRACK=$(GOAL_REVIEW_TRACK=single python3 "$RT" --format track)
[[ "$TRACK" == "single" ]] || { echo "FAIL: env single expected single got $TRACK"; exit 1; }
echo "OK: env single → single"

# Test 3: GOAL_REVIEW_TRACK=dual → dual
TRACK=$(GOAL_REVIEW_TRACK=dual python3 "$RT" --format track)
[[ "$TRACK" == "dual" ]] || { echo "FAIL: env dual expected dual got $TRACK"; exit 1; }
echo "OK: env dual → dual"

# Test 4: state review_policy.track=single → single (no env)
echo '{"review_policy":{"track":"single"}}' > "$TMP/state.json"
TRACK=$(python3 "$RT" --state-file "$TMP/state.json" --format track)
[[ "$TRACK" == "single" ]] || { echo "FAIL: state single expected single got $TRACK"; exit 1; }
echo "OK: state review_policy.track=single → single"

# Test 5: state review_policy.track=dual → dual
echo '{"review_policy":{"track":"dual"}}' > "$TMP/state.json"
TRACK=$(python3 "$RT" --state-file "$TMP/state.json" --format track)
[[ "$TRACK" == "dual" ]] || { echo "FAIL: state dual expected dual got $TRACK"; exit 1; }
echo "OK: state review_policy.track=dual → dual"

# Test 6: env overrides state
echo '{"review_policy":{"track":"single"}}' > "$TMP/state.json"
TRACK=$(GOAL_REVIEW_TRACK=dual python3 "$RT" --state-file "$TMP/state.json" --format track)
[[ "$TRACK" == "dual" ]] || { echo "FAIL: env dual should override state single got $TRACK"; exit 1; }
echo "OK: env overrides state"

# Test 7: XS without flag → single (B8 default)
echo '{"task_tier":"XS"}' > "$TMP/state.json"
TRACK=$(python3 "$RT" --state-file "$TMP/state.json" --format track)
[[ "$TRACK" == "single" ]] || { echo "FAIL: XS default should be single got $TRACK"; exit 1; }
echo "OK: XS without --auto-resolve-xs-s → single"

TRACK=$(python3 "$RT" --state-file "$TMP/state.json" --auto-resolve-xs-s --format track)
[[ "$TRACK" == "single" ]] || { echo "FAIL: with flag XS should be single got $TRACK"; exit 1; }
echo "OK: XS with --auto-resolve-xs-s → single"

# Test 8: M tier → single by default (B8)
echo '{"task_tier":"M"}' > "$TMP/state.json"
TRACK=$(python3 "$RT" --state-file "$TMP/state.json" --auto-resolve-xs-s --format track)
[[ "$TRACK" == "single" ]] || { echo "FAIL: M default B8 should be single got $TRACK"; exit 1; }
echo "OK: M with --auto-resolve-xs-s → single (B8 default)"

# Test 9: persist writes review_policy.track to state
echo '{}' > "$TMP/state2.json"
GOAL_REVIEW_TRACK=single python3 "$RT" --state-file "$TMP/state2.json" --persist --format track >/dev/null
PERSISTED=$(python3 -c "import json; print(json.load(open('$TMP/state2.json')).get('review_policy',{}).get('track',''))")
[[ "$PERSISTED" == "single" ]] || { echo "FAIL: persist expected single got $PERSISTED"; exit 1; }
echo "OK: persist writes review_policy.track"

# Test 10: wrapper_profile_for_track
WP=$(python3 -c "import sys; sys.path.insert(0,'$SCRIPTS'); from review_track import wrapper_profile_for_track; print(wrapper_profile_for_track('single'))")
[[ "$WP" == "goal-review" ]] || { echo "FAIL: wrapper single expected goal-review got $WP"; exit 1; }
WP=$(python3 -c "import sys; sys.path.insert(0,'$SCRIPTS'); from review_track import wrapper_profile_for_track; print(wrapper_profile_for_track('dual'))")
[[ "$WP" == "guazi-flow-review" ]] || { echo "FAIL: wrapper dual expected guazi-flow-review got $WP"; exit 1; }
echo "OK: wrapper_profile_for_track"

# Test 11: GOAL_REVIEW_SINGLE_DEFAULT=1 still single for M (redundant with B8)
echo '{"task_tier":"M"}' > "$TMP/state4.json"
TRACK=$(GOAL_REVIEW_SINGLE_DEFAULT=1 python3 "$RT" --state-file "$TMP/state4.json" --format track)
[[ "$TRACK" == "single" ]] || { echo "FAIL: SINGLE_DEFAULT M expected single got $TRACK"; exit 1; }
echo "OK: GOAL_REVIEW_SINGLE_DEFAULT=1 + M → single"

# Test 12: explicit GOAL_REVIEW_TRACK=dual overrides SINGLE_DEFAULT
echo '{"task_tier":"XS"}' > "$TMP/state3.json"
TRACK=$(GOAL_REVIEW_SINGLE_DEFAULT=1 GOAL_REVIEW_TRACK=dual python3 "$RT" --state-file "$TMP/state3.json" --format track)
[[ "$TRACK" == "dual" ]] || { echo "FAIL: explicit dual should override SINGLE_DEFAULT got $TRACK"; exit 1; }
echo "OK: explicit GOAL_REVIEW_TRACK=dual overrides SINGLE_DEFAULT"

echo "test-review-track passed"
