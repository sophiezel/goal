#!/bin/bash
# test-readonly-subagent-fallback.sh — Layer 3 mock readonly subagent
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
ORCH="$SCRIPTS/review_fallback_orchestrator.py"
FIX="$DIR/review-unified-good"
PACKET="$FIX/handoff/review-packet.json"

[[ -f "$PACKET" ]] || { echo "missing fixture packet"; exit 1; }

# Force API undetermined → readonly mock succeeds
OUT=$(GOAL_REVIEW_READONLY_MOCK=1 python3 "$ORCH" \
  --script-dir "$SCRIPTS" \
  --packet "$PACKET" \
  --verify-json '{"overall":"pass"}' \
  --channel unified \
  --provider cursor-task \
  --budget-sec 60 \
  --attempt-timeout-sec 10 \
  --max-api-attempts 1 \
  --candidates-json '[{"provider":"cursor-task","model":"cursor-task"}]')

python3 - "$OUT" << 'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data.get("ok") is True, data
assert data.get("fallback_layer") == "readonly_subagent", data
body = data.get("review_body") or {}
assert body.get("result") == "pass", body
assert body.get("readonly_subagent") is True, body
layers = [a.get("fallback_layer") for a in (data.get("attempts") or [])]
assert "readonly_subagent" in layers, layers
print("readonly subagent fallback OK")
PY

echo "test-readonly-subagent-fallback passed"
