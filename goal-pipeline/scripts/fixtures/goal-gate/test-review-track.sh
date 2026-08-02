#!/bin/bash
# test-review-track.sh — review_track.py goal v1.4 single-only
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
RT="$SCRIPTS/review_track.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

TRACK=$(python3 "$RT" --format track)
[[ "$TRACK" == "single" ]] || { echo "FAIL: default expected single got $TRACK"; exit 1; }
echo "OK: default → single"

TRACK=$(GOAL_REVIEW_TRACK=single python3 "$RT" --format track)
[[ "$TRACK" == "single" ]] || { echo "FAIL: env single expected single got $TRACK"; exit 1; }
echo "OK: env single → single"

# v1.4: dual env ignored — always single
TRACK=$(GOAL_REVIEW_TRACK=dual python3 "$RT" --format track)
[[ "$TRACK" == "single" ]] || { echo "FAIL: v1.4 dual env should still be single got $TRACK"; exit 1; }
echo "OK: env dual → single (v1.4)"

echo '{"review_policy":{"track":"single"}}' > "$TMP/state.json"
TRACK=$(python3 "$RT" --state-file "$TMP/state.json" --format track)
[[ "$TRACK" == "single" ]] || { echo "FAIL: state single expected single got $TRACK"; exit 1; }
echo "OK: state review_policy.track=single → single"

echo '{"review_policy":{"track":"dual"}}' > "$TMP/state.json"
TRACK=$(python3 "$RT" --state-file "$TMP/state.json" --format track)
[[ "$TRACK" == "single" ]] || { echo "FAIL: state dual should be single in v1.4 got $TRACK"; exit 1; }
echo "OK: state dual → single (v1.4)"

WP=$(python3 -c "import sys; sys.path.insert(0,'$SCRIPTS'); from review_track import wrapper_profile_for_track; print(wrapper_profile_for_track('single'))")
[[ "$WP" == "goal-review" ]] || { echo "FAIL: wrapper expected goal-review got $WP"; exit 1; }
echo "OK: wrapper_profile_for_track"

echo "test-review-track passed"
