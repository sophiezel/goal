#!/bin/bash
# Assert issues_gf_count does NOT count markdown table rows (CTB-43564 false positive fix)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/evidence" "$TMP/handoff"
cat > "$TMP/evidence/review.md" << 'MD'
---
stage: review
result: pass
git_head: "abc123"
review_subject_hash: "deadbeef"
issues_gf_count: 0
merged_result: pass
---
## 审查范围
scope
## 发现项
| ID | Severity | Summary |
|----|----------|---------|
| AM-01 | low | matrix row 1 |
| AM-02 | low | matrix row 2 |
| AM-03 | low | matrix row 3 |
| AM-04 | low | matrix row 4 |
| AM-05 | low | matrix row 5 |
| AM-06 | low | matrix row 6 |
| AM-07 | low | matrix row 7 |
| AM-08 | low | matrix row 8 |
| AM-09 | low | matrix row 9 |
MD

echo '{"schema_version":1,"result":"pass","issues":[],"checklist_goal":[],"checklist_gf":[],"gf_skill_attested":true}' > "$TMP/evidence/review-unified.json"

GF_COUNT=$(python3 - "$TMP/evidence/review-unified.json" << 'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
issues = d.get("issues", [])
print(sum(1 for i in issues if i.get("channel") == "guazi-flow-review"))
PY
)

if [[ "$GF_COUNT" != "0" ]]; then
  echo "FAIL issues_gf_count=$GF_COUNT expected 0 (table rows must not inflate count)"
  exit 1
fi
echo "OK review-gf-count (0 not 9)"
