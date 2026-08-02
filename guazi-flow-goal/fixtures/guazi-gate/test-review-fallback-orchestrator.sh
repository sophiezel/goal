#!/bin/bash
# test-review-fallback-orchestrator.sh — mock-unified via fallback orchestrator
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_SCRIPTS:-${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts}"
FIX="$DIR/review-unified-good"
ORCH="$SCRIPTS/review_fallback_orchestrator.py"
PACKET="$FIX/handoff/review-packet.json"

[[ -f "$PACKET" ]] || { echo "missing fixture packet"; exit 1; }

OUT=$(python3 "$ORCH" \
  --script-dir "$SCRIPTS" \
  --packet "$PACKET" \
  --verify-json '{"overall":"pass"}' \
  --channel unified \
  --provider mock-unified \
  --model mock \
  --budget-sec 60 \
  --attempt-timeout-sec 30 \
  --max-api-attempts 1 \
  --candidates-json '[{"provider":"mock-unified","model":"mock-unified"}]')

python3 - "$OUT" << 'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data.get("ok") is True, data
body = data.get("review_body") or {}
assert body.get("result") == "pass", body
assert len(data.get("attempts") or []) >= 1, data
assert data.get("fallback_layer") in ("api_horizontal", "packet_vertical", "none"), data
print("orchestrator mock-unified OK")
PY

echo "test-review-fallback-orchestrator passed"
