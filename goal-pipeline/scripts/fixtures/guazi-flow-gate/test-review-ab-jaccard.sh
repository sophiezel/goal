#!/bin/bash
# test-review-ab-jaccard.sh — L0 A/B: dual vs single issues_goal Jaccard ≥0.95 (v3 §8.5 #2)
# Deterministic: same fixture, merge with guazi-flow-review channel present (dual) vs absent (single),
# compare issues_goal sets — must be Jaccard ≥0.95 with no new blockers.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
MERGE="$SCRIPTS/merge_review_core.py"
FIXTURE="$DIR/review-unified-good"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' exit
export GOAL_ARTIFACT_MODE=repo_full

# Dual: unified has both goal + guazi-flow-review issues
mkdir -p "$TMP/dual/task/evidence" "$TMP/dual/task/handoff"
cp "$FIXTURE/evidence/review-unified.json" "$TMP/dual/task/evidence/review-unified.json" 2>/dev/null || true
# Ensure unified has a guazi-flow-review channel issue for dual
python3 - "$TMP/dual/task/evidence/review-unified.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
issues = d.get("issues", [])
if not any(i.get("channel") == "guazi-flow-review" for i in issues):
    issues.append({"channel": "guazi-flow-review", "severity": "warning", "file": "src/x.ts", "summary": "gf nitpick", "root_cause": "implement_error"})
    d["issues"] = issues
    d["result"] = d.get("result", "not_pass")
json.dump(d, open(p, "w"), ensure_ascii=False, indent=2)
PY
echo '{"run_id":"r1","packet_hash":"p1"}' > "$TMP/dual/task/evidence/review-run.json"
echo '---' > "$TMP/dual/task/evidence/review.md"
GOAL_STATE_FILE="$TMP/dual/state.json" python3 "$MERGE" "$TMP/dual/task" "$TMP/dual/task/evidence/review-unified.json" >/dev/null 2>&1 || true

# Single: unified has only goal issues (guazi-flow-review skipped)
mkdir -p "$TMP/single/task/evidence" "$TMP/single/task/handoff"
python3 - "$TMP/single/task/evidence/review-unified.json" <<'PY'
import json, sys, shutil, os
src = sys.argv[1]
# Copy from fixture, strip guazi-flow-review channel
fixture = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(sys.argv[0]))), "review-unified-good", "evidence", "review-unified.json")
# fallback: read from dual and strip
d = json.load(open(os.path.join(os.path.dirname(src), os.path.basename(src))) if False else open(src.replace("single","dual")))
d = json.loads(json.dumps(d))  # deep copy
d["issues"] = [i for i in d.get("issues", []) if i.get("channel", "goal") != "guazi-flow-review"]
json.dump(d, open(src, "w"), ensure_ascii=False, indent=2)
PY
echo '{"run_id":"r1","packet_hash":"p1"}' > "$TMP/single/task/evidence/review-run.json"
echo '---' > "$TMP/single/task/evidence/review.md"
GOAL_STATE_FILE="$TMP/single/state.json" python3 "$MERGE" "$TMP/single/task" "$TMP/single/task/evidence/review-unified.json" >/dev/null 2>&1 || true

# Compare issues_goal sets (Jaccard)
python3 - "$TMP/dual/task/evidence/review-fix-input.json" "$TMP/single/task/evidence/review-fix-input.json" <<'PY'
import json, sys
d1 = json.load(open(sys.argv[1]))
d2 = json.load(open(sys.argv[2]))
def goal_keys(d):
    return {("%s|%s|%s" % (i.get("id",""), i.get("file",""), i.get("summary","")[:80])) for i in d.get("issues",[]) if i.get("channel","goal") != "guazi-flow-review"}
def goal_blockers(d):
    return {("%s|%s" % (i.get("id",""), i.get("summary","")[:80])) for i in d.get("issues",[]) if i.get("channel","goal") != "guazi-flow-review" and i.get("severity")=="blocker"}
k1, k2 = goal_keys(d1), goal_keys(d2)
inter = k1 & k2
union = k1 | k2
jaccard = len(inter) / len(union) if union else 1.0
b1, b2 = goal_blockers(d1), goal_blockers(d2)
new_blockers = b2 - b1
print(f"Jaccard={jaccard:.4f} dual_goal={len(k1)} single_goal={len(k2)} new_blockers={len(new_blockers)}")
assert jaccard >= 0.95, f"Jaccard {jaccard} < 0.95"
assert not new_blockers, f"single introduced new blockers: {new_blockers}"
print("OK: L0 A/B Jaccard >= 0.95, no new blockers")
PY

echo "test-review-ab-jaccard passed"
