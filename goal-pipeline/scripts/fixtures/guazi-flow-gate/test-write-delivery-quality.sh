#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WDQ="$ROOT/write-delivery-quality.sh"
PLAN_GOOD="$SCRIPT_DIR/plan-good"
OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT
"$WDQ" --task-dir "$PLAN_GOOD" --output "$OUT" >/dev/null
python3 -c "
import json
d=json.load(open('$OUT'))
assert d.get('schema_version')==2, d
assert 'timing' in d and 'loops' in d
print('OK delivery-quality v2 fields')
"
