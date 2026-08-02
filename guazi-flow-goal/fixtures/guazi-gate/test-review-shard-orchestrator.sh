#!/bin/bash
# test-review-shard-orchestrator.sh — parallel shard mock-unified merge
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_SCRIPTS:-${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts}"
ORCH="$SCRIPTS/review_fallback_orchestrator.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 - "$TMP" << 'PY'
import json, os, sys
tmp = sys.argv[1]
pkt = {
    "schema_version": 1,
    "diff": "diff --git a/src/pages/a/list.tsx b/src/pages/a/list.tsx\n+list\n"
            "diff --git a/src/services/b.ts b/src/services/b.ts\n+svc\n"
            "diff --git a/src/pages/a/components/P.tsx b/src/pages/a/components/P.tsx\n+p\n",
    "changed_files": [
        "src/pages/a/list.tsx",
        "src/services/b.ts",
        "src/pages/a/components/P.tsx",
    ],
    "contract": {"acceptance_matrix": "C01"},
    "guazi_flow_rubric": {"skill_summary": "x"},
    "goal_checklist": [{"id": "scope_compliant", "priority": "P0", "question": "q"}],
    "deterministic_checks": {"overall": "pass"},
}
json.dump(pkt, open(os.path.join(tmp, "packet.json"), "w"), indent=2)
PY

OUT=$(GOAL_REVIEW_DEPTH=full python3 "$ORCH" \
  --script-dir "$SCRIPTS" \
  --packet "$TMP/packet.json" \
  --verify-json '{"overall":"pass"}' \
  --channel unified \
  --provider mock-unified \
  --review-depth full \
  --budget-sec 120 \
  --attempt-timeout-sec 30 \
  --max-api-attempts 1 \
  --candidates-json '[{"provider":"mock-unified","model":"mock-unified"}]')

python3 - "$OUT" << 'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data.get("ok") is True, data
assert data.get("fallback_layer") == "packet_shard_parallel", data.get("fallback_layer")
body = data.get("review_body") or {}
assert body.get("shard_merge", {}).get("shard_count", 0) >= 2, body
print("shard orchestrator OK")
PY

echo "test-review-shard-orchestrator passed"
