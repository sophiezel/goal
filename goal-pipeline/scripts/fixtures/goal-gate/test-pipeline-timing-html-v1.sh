#!/usr/bin/env bash
# test-pipeline-timing-html-v1.sh — HTML v1 report from fixture pipeline-timing.json (#9)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
FIX="$(cd "$DIR/../pipeline-timing-html-v1" && pwd)"
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

TIMING="$FIX/evidence/pipeline-timing.json"
HTML="$OUT/pipeline-timing-report.html"

python3 "$SCRIPTS/render-pipeline-timing-report.py" \
  --format html \
  --timing-json "$TIMING" \
  --uvo-json "$FIX/evidence/verification-oracle.json" \
  --review-json "$FIX/evidence/review-run.json" \
  --task-id pipeline-timing-html-v1-fixture \
  --git-short-head deadbeef \
  --output "$HTML"

[[ -f "$HTML" ]] || { echo "FAIL missing HTML output"; exit 1; }
grep -q 'id="summary"' "$HTML" || { echo "FAIL missing summary section"; exit 1; }
grep -q 'id="uvo"' "$HTML" || { echo "FAIL missing uvo section"; exit 1; }
grep -q 'id="review-provenance"' "$HTML" || { echo "FAIL missing review section"; exit 1; }
grep -q 'id="postmortem-sla"' "$HTML" || { echo "FAIL missing postmortem section"; exit 1; }
grep -q 'id="low-value-flags"' "$HTML" || { echo "FAIL missing flags section"; exit 1; }
grep -q 'pipeline-timing-html-v1-fixture' "$HTML" || { echo "FAIL missing task id"; exit 1; }
grep -q 'build' "$HTML" || { echo "FAIL missing UVO build row"; exit 1; }
grep -q 'R1:' "$HTML" || { echo "FAIL missing R1 low-value flag"; exit 1; }

echo "OK pipeline-timing-html-v1"
