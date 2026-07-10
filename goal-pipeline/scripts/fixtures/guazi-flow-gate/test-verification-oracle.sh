#!/bin/bash
# test-verification-oracle.sh — fixture: UVO schema + benchmark static checks
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"

# Core module import
python3 - "$SCRIPTS/verification_oracle_core.py" << 'PY'
import importlib.util, sys, os
path = sys.argv[1]
spec = importlib.util.spec_from_file_location("uvo", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
assert mod.smoke_required(["src/pages/foo/index.tsx"], ["src/pages/foo/**"], "standard") is False
assert mod.smoke_required(["src/App.tsx"], [], "standard") is True
assert mod.smoke_required([], [], "strict") is True
print("verification_oracle_core smoke_required OK")
PY

# Benchmark static acceptance
bash "$SCRIPTS/benchmark-pipeline-replay.sh" --task-dir "$DIR/../guazi-flow-gate/plan-good" --output /tmp/benchmark-test.json
python3 - /tmp/benchmark-test.json << 'PY2'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["passed"] is True, d
assert d["op_counts"]["verification_oracle_expected"] == 1
assert d["op_counts"]["stage_driver_mandatory_yarn_test"] == 0
print("benchmark static checks OK")
PY2

# assemble should read UVO not subprocess verify
grep -q 'verification-oracle.json' "$SCRIPTS/assemble-review-packet.sh" || { echo "assemble missing UVO read path"; exit 1; }
grep -q 'subprocess.check_output(\[verify_script' "$SCRIPTS/assemble-review-packet.sh" && { echo "assemble still invokes verify subprocess"; exit 1; }
grep -q 'diff_resolver' "$SCRIPTS/assemble-review-packet.sh" || { echo "assemble missing diff_resolver"; exit 1; }
grep -q 'review_packet_preflight' "$SCRIPTS/assemble-review-packet.sh" || { echo "assemble missing preflight hook"; exit 1; }

# build dedupe: plan verification_commands with build should not duplicate in run_oracle logic
python3 - "$SCRIPTS/verification_oracle_core.py" << 'PY3'
import importlib.util, sys, os
spec = importlib.util.spec_from_file_location("uvo", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
plan = {"verification_commands": [
    {"id": "h5-test", "cmd": "CI=true yarn test --watchAll=false src/a.test.ts"},
    {"id": "h5-build", "cmd": "CI= yarn build:beta"},
]}
cmds = mod.build_test_commands(os.getcwd(), "/tmp", plan, ["src/a.ts"], "related_union")
builds = [c for c in cmds if c.get("kind") == "build" or mod._is_build_command(c.get("cmd", ""))]
tests = [c for c in cmds if c not in builds]
assert len(builds) == 1, builds
assert not mod._test_files_for_write_set(["docs/guazi-flow/x/index.md"], os.getcwd())
print("UVO dedupe + index basename fix OK")
PY3

echo "test-verification-oracle passed"
