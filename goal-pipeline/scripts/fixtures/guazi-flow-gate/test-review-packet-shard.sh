#!/bin/bash
# test-review-packet-shard.sh — shard split + merge dedup
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"

python3 - "$SCRIPTS" << 'PY'
import importlib.util, json, os, sys

scripts = sys.argv[1]
for mod_name, fname in (
    ("shard_mod", "review_packet_shard.py"),
    ("depth_mod", "review_depth.py"),
):
    spec = importlib.util.spec_from_file_location(mod_name, os.path.join(scripts, fname))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    if mod_name == "shard_mod":
        shard_mod = m
    else:
        depth_mod = m

packet = {
    "diff": (
        "diff --git a/src/pages/evaluateRecovery/list.tsx b/src/pages/evaluateRecovery/list.tsx\n+list\n"
        "diff --git a/src/services/recovery.ts b/src/services/recovery.ts\n+svc\n"
        "diff --git a/src/pages/evaluateRecovery/components/FailPopup.tsx b/src/pages/evaluateRecovery/components/FailPopup.tsx\n+pop\n"
        "diff --git a/src/pages/evaluateRecovery/index.tsx b/src/pages/evaluateRecovery/index.tsx\n+detail\n"
    ),
    "changed_files": [
        "src/pages/evaluateRecovery/list.tsx",
        "src/services/recovery.ts",
        "src/pages/evaluateRecovery/components/FailPopup.tsx",
        "src/pages/evaluateRecovery/index.tsx",
    ],
    "contract": {},
}
shards = shard_mod.build_shards(packet, scripts, min_shards=2)
assert len(shards) >= 2, len(shards)
ids = {s.get("shard_id") for s in shards}
assert "services" in ids or "list" in ids, ids

r1 = {"result": "pass", "issues": [{"channel": "goal", "file": "a.ts", "summary": "重复", "severity": "warning"}], "checklist_goal": [], "checklist_gf": []}
r2 = {"result": "not_pass", "issues": [{"channel": "goal", "file": "a.ts", "summary": "重复", "severity": "blocker"}], "checklist_goal": [], "checklist_gf": []}
merged = shard_mod.merge_unified_reviews([r1, r2])
assert len(merged["issues"]) == 1, merged["issues"]
assert merged["result"] == "not_pass"

depth, meta = depth_mod.resolve_review_depth(packet, {"quality_policy": {"tier": "standard"}})
assert depth == "light", (depth, meta)
big = dict(packet)
big["changed_files"] = [f"src/f{i}.ts" for i in range(10)]
depth2, _ = depth_mod.resolve_review_depth(big, {"quality_policy": {"tier": "standard"}})
assert depth2 == "full", depth2
print("packet shard + depth OK")
PY

echo "test-review-packet-shard passed"
