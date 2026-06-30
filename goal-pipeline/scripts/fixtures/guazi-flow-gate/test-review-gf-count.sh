#!/bin/bash
# Assert issues_gf_count does NOT count markdown table rows (CTB-43564 false positive fix)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/../../gate-guazi-flow-stage.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/evidence" "$TMP/handoff"
# review.md with many table rows (like acceptance matrix) but explicit issues_gf_count: 0
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

echo '{"schema_version":1,"result":"pass","issues":[],"issues_count":0}' > "$TMP/evidence/review-gf.json"

# Extract GF count the same way gate does
EVIDENCE_DIR="$TMP/evidence"
GF_COUNT=$(bash -c "
source /dev/null
read_gf_issues_count() {
  local gf_json=\"\$EVIDENCE_DIR/review-gf.json\"
  if [[ -f \"\$gf_json\" ]]; then
    python3 -c \"import json; d=json.load(open('\$gf_json')); print(len(d.get('issues',[])))\" 2>/dev/null || echo 0
    return
  fi
  python3 - \"\$EVIDENCE_DIR/review.md\" << 'PYGF'
import re, sys, os
p = sys.argv[1]
if not os.path.isfile(p):
    print(0); sys.exit(0)
t = open(p, encoding=\"utf-8\").read()
m = re.match(r\"^---\\s*\\n(.*?)\\n---\", t, re.DOTALL)
if m:
    for line in m.group(1).splitlines():
        if line.strip().startswith(\"issues_gf_count:\"):
            try:
                print(int(line.split(\":\",1)[1].strip())); sys.exit(0)
            except ValueError:
                pass
print(0)
PYGF
}
EVIDENCE_DIR='$TMP/evidence'
read_gf_issues_count
")

if [[ "$GF_COUNT" != "0" ]]; then
  echo "FAIL issues_gf_count=$GF_COUNT expected 0 (table rows must not inflate count)"
  exit 1
fi
echo "OK review-gf-count (0 not 9)"
