#!/bin/bash
# test-commit-before-review.sh — write_set dirty → fail; committed → pass (v3 §8.3b)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_SCRIPTS:-${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts}"
CHK="$SCRIPTS/check_commit_before_review.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Set up a git repo with a write_set path
cd "$TMP"
git init -q
git config user.email t@t.t
git config user.name t
mkdir -p src
echo "original" > src/a.ts
git add src/a.ts
git commit -qm "init"

mkdir -p task/handoff
echo '{"write_set":["src/a.ts"]}' > task/handoff/plan.json

# Test 1: committed (clean) → pass
OUT=$(python3 "$CHK" --repo-root "$TMP" --task-dir "$TMP/task" --json)
OK=$(echo "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['ok'])")
[[ "$OK" == "True" ]] || { echo "FAIL clean expected ok=True got $OUT"; exit 1; }
echo "OK: committed write_set → pass"

# Test 2: dirty write_set → fail
echo "modified" > src/a.ts
OUT=$(python3 "$CHK" --repo-root "$TMP" --task-dir "$TMP/task" --json 2>&1 || true)
OK=$(echo "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['ok'])")
[[ "$OK" == "False" ]] || { echo "FAIL dirty expected ok=False got $OUT"; exit 1; }
echo "OK: dirty write_set → fail"

# Test 3: untracked write_set path → fail
git checkout -q src/a.ts
echo "new" > src/b.ts
echo '{"write_set":["src/b.ts"]}' > task/handoff/plan.json
OUT=$(python3 "$CHK" --repo-root "$TMP" --task-dir "$TMP/task" --json 2>&1 || true)
OK=$(echo "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['ok'])")
[[ "$OK" == "False" ]] || { echo "FAIL untracked expected ok=False got $OUT"; exit 1; }
echo "OK: untracked write_set → fail"

# Test 4: GOAL_SKIP_COMMIT_BEFORE_REVIEW=1 → skip pass
echo "modified" > src/a.ts
echo '{"write_set":["src/a.ts"]}' > task/handoff/plan.json
OUT=$(GOAL_SKIP_COMMIT_BEFORE_REVIEW=1 python3 "$CHK" --repo-root "$TMP" --task-dir "$TMP/task" --json)
SKIP=$(echo "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('skipped', False))")
[[ "$SKIP" == "True" ]] || { echo "FAIL skip expected skipped=True got $OUT"; exit 1; }
echo "OK: GOAL_SKIP_COMMIT_BEFORE_REVIEW=1 → skip"

# Test 5: empty write_set → pass (no paths to check)
echo '{"write_set":[]}' > task/handoff/plan.json
OUT=$(python3 "$CHK" --repo-root "$TMP" --task-dir "$TMP/task" --json)
OK=$(echo "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['ok'])")
[[ "$OK" == "True" ]] || { echo "FAIL empty ws expected ok=True got $OUT"; exit 1; }
echo "OK: empty write_set → pass"

echo "test-commit-before-review passed"
