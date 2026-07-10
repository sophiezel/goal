#!/bin/bash
# test-plan-quality-gate.sh — PQ firewall fixture tests
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$DIR/../../plan-quality-gate.py"
GOOD="$DIR/plan-good"
BAD="$DIR/plan-bad"

[[ -f "$GATE" ]] || { echo "plan-quality-gate.py not found at $GATE" >&2; exit 2; }

echo "plan-quality-gate: good fixture"
python3 "$GATE" --task-dir "$GOOD" --tier standard
echo "plan-quality-gate: bad fixture should fail"
if python3 "$GATE" --task-dir "$BAD" --tier standard 2>/dev/null; then
  echo "FAIL: expected plan-bad to fail PQ gate" >&2
  exit 1
fi
echo "plan-quality-gate tests passed"
