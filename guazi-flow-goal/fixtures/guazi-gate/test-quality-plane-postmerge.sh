#!/bin/bash
# test-quality-plane-postmerge.sh — #18 postmerge_required at complete quality_plane_check
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_SCRIPTS:-${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts}"
QPC="$SCRIPTS/quality_plane_check.py"
RESOLVE="$SCRIPTS/resolve_postmerge_policy.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/evidence" "$TMP/handoff"
cat > "$TMP/index.md" << 'MD'
---
postmerge_policy: required
---
# task
MD
cat > "$TMP/evidence/review-run.json" << 'JSON'
{"run_id":"r1"}
JSON
cat > "$TMP/evidence/review-unified.json" << 'JSON'
{"result":"pass","issues":[]}
JSON
cat > "$TMP/evidence/review.md" << 'MD'
---
stage: review
result: pass
review_subject_hash: abc123
---
MD
cat > "$TMP/evidence/verification-oracle.json" << 'JSON'
{"overall":"pass"}
JSON
cat > "$TMP/evidence/contract-conformance.json" << 'JSON'
{"passed":true}
JSON

# Case 1: required policy, no postmerge.md → block complete
if python3 "$QPC" --task-dir "$TMP" --mode complete >/dev/null 2>&1; then
  echo "FAIL expected postmerge_required without postmerge.md"; exit 1
fi
OUT=$(python3 "$QPC" --task-dir "$TMP" --mode complete 2>/dev/null || true)
echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); codes=[e['failure_code'] for e in d.get('errors',[])]; assert 'postmerge_required' in codes, codes"
echo "OK required policy blocks complete without postmerge.md"

# Case 2: optional policy (no frontmatter flag) → pass
TMP2=$(mktemp -d)
mkdir -p "$TMP2/evidence"
cp "$TMP/evidence/"* "$TMP2/evidence/"
cat > "$TMP2/index.md" << 'MD'
---
---
# task
MD
if ! python3 "$QPC" --task-dir "$TMP2" --mode complete >/dev/null 2>&1; then
  echo "FAIL optional policy should pass without postmerge.md"; exit 1
fi
echo "OK optional policy passes without postmerge.md"
rm -rf "$TMP2"

# Case 3: required + postmerge pass with matching hash → pass
cat > "$TMP/evidence/postmerge.md" << 'MD'
---
stage: postmerge
result: pass
review_subject_hash: abc123
---
MD
if ! python3 "$QPC" --task-dir "$TMP" --mode complete >/dev/null 2>&1; then
  python3 "$QPC" --task-dir "$TMP" --mode complete --format text >&2 || true
  echo "FAIL expected pass with postmerge.md"; exit 1
fi
echo "OK required policy passes with fresh postmerge.md"

# Case 4: resolver + advance routing smoke
POL=$(python3 "$RESOLVE" --index "$TMP/index.md" --format json | python3 -c "import json,sys; print(json.load(sys.stdin)['postmerge_policy'])")
[[ "$POL" == "required" ]] || { echo "FAIL resolver expected required got $POL"; exit 1; }
if ! python3 "$RESOLVE" --index "$TMP/index.md" --repo-evidence-dir "$TMP/evidence" --check-evidence --format json >/dev/null 2>&1; then
  echo "FAIL resolver check-evidence should pass"; exit 1
fi
echo "OK resolve_postmerge_policy"

echo "test-quality-plane-postmerge passed"
