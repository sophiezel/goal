#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_SCRIPTS:-${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts}"
REC="$SCRIPTS/record-pipeline-timing.py"
POST="$SCRIPTS/pipeline-postmortem.py"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
TASK="$tmp/task"
mkdir -p "$TASK/evidence"
python3 "$REC" --task-dir "$TASK" --stage plan --event start >/dev/null
python3 "$REC" --task-dir "$TASK" --stage plan --event mark --substep cwiki --duration-ms 30000 >/dev/null
python3 "$REC" --task-dir "$TASK" --stage plan --event end --duration-ms 120000 >/dev/null
python3 "$REC" --task-dir "$TASK" --stage implement --event end --duration-ms 600000 >/dev/null
python3 "$REC" --task-dir "$TASK" --stage review --event start >/dev/null
python3 "$REC" --task-dir "$TASK" --stage review --event end --substep attempt --duration-ms 900 >/dev/null

DOC="$TASK/evidence/pipeline-timing.json"
[[ -f "$DOC" ]] || { echo "FAIL timing missing"; exit 1; }
TZ=$(python3 -c "import json; print(json.load(open('$DOC'))['timezone'])")
[[ "$TZ" == "UTC" ]] || { echo "FAIL timezone=$TZ"; exit 1; }
python3 -c "
import json
d=json.load(open('$DOC'))
assert 'Z' in d['updated_at_utc']
assert d['stages']['plan']['duration_ms']==120000
assert d['stages']['plan'].get('started_at_utc')
assert d['stages']['plan']['substeps']['cwiki']['duration_ms']==30000
assert d['stages']['review']['substeps']['attempt']['duration_ms']==900
print('timing_ok')
"

STATE="$tmp/state.json"
echo '{"status":"blocked","failure_code":"plan_code_order","current_stage":"plan"}' > "$STATE"
OUT=$(python3 "$POST" --state-file "$STATE" --task-dir "$TASK" --format json)
echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['failure_code']=='plan_code_order'; assert d['recommendations']"
echo "OK pipeline-timing-sla"
