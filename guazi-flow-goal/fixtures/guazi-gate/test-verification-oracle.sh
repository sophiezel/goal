#!/bin/bash
# test-verification-oracle.sh — fixture: UVO schema + benchmark static checks
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts"

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
bash "$SCRIPTS/benchmark-pipeline-replay.sh" --task-dir "$DIR/plan-good" --output /tmp/benchmark-test.json
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
assert not mod._test_files_for_write_set(["docs/guazi-flow/x/index.md"], os.getcwd(), [])
print("UVO dedupe + index basename fix OK")
PY3

# G1: colocated constants tests only under write_set tree (no cross-directory basename match)
python3 - "$SCRIPTS/verification_oracle_core.py" << 'PY4'
import importlib.util, sys, os, tempfile, shutil
path = sys.argv[1]
spec = importlib.util.spec_from_file_location("uvo", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
tmpdir = tempfile.mkdtemp()
try:
    os.makedirs(os.path.join(tmpdir, "src/pages/foo"))
    os.makedirs(os.path.join(tmpdir, "src/pages/bar"))
    open(os.path.join(tmpdir, "src/pages/foo/constants.ts"), "w").close()
    open(os.path.join(tmpdir, "src/pages/foo/constants.test.ts"), "w").close()
    open(os.path.join(tmpdir, "src/pages/bar/constants.test.ts"), "w").close()
    ws = ["src/pages/foo/**"]
    changed = ["src/pages/foo/constants.ts"]
    tests = mod._test_files_for_write_set(changed, tmpdir, ws)
    assert tests == ["src/pages/foo/constants.test.ts"], tests
    related = mod._related_source_files(
        ["src/App.tsx", "src/pages/foo/index.tsx", "src/App.test.tsx"],
        ["src/App.tsx", "src/pages/foo/**", "src/App.test.tsx"],
    )
    assert "src/App.tsx" not in related, related
    assert "src/pages/foo/index.tsx" in related, related
    seeds, direct = mod._find_related_test_targets(
        ["src/config/env.js", "src/pages/foo/constants.ts", "src/App.test.tsx"],
        ["src/pages/foo/**", "src/App.test.tsx"],
        tmpdir,
    )
    assert "src/config/env.js" not in seeds, seeds
    assert "src/App.test.tsx" in direct, direct
    assert "src/App.test.tsx" not in seeds, seeds
    cmd = mod._compose_find_related_test_cmd(
        tmpdir,
        ["src/pages/foo/constants.ts"],
        ["src/App.test.tsx"],
    )
    assert cmd is not None
    assert "src/config/env.js" not in cmd, cmd
    assert '--findRelatedTests "src/pages/foo/constants.ts"' in cmd, cmd
    assert '"src/App.test.tsx"' in cmd, cmd
    assert cmd.index("--findRelatedTests") < cmd.index('"src/App.test.tsx"'), cmd
    os.environ["GOAL_UVO_RELATED_UNION_MODE"] = "legacy_wide"
    wide = mod._changed_files_for_related_union(
        ["src/config/env.js", "src/pages/foo/constants.ts"],
        ["src/pages/foo/**"],
    )
    assert "src/config/env.js" in wide, wide
    os.environ.pop("GOAL_UVO_RELATED_UNION_MODE", None)
    dem08 = mod._dem08_diagnostics(
        [{"id": "test:related-tests", "ok": False, "output_tail": "FAIL src/pages/order/newbie/list/index.test.tsx"}],
        ["src/pages/foo/**"],
    )
    assert dem08["verification_scope_overreach"] is True, dem08
    assert "src/pages/order/newbie/list/index.test.tsx" in dem08["out_of_write_set_closure"], dem08
    assert mod._dem08_implement_warn_pass(
        False,
        dem08,
        "write_set_closure",
    ), dem08
    assert not mod._dem08_implement_warn_pass(False, dem08, "legacy_wide")
    mixed = mod._dem08_diagnostics(
        [{"id": "test:t", "ok": False, "output_tail": "FAIL src/pages/foo/constants.test.ts"}],
        ["src/pages/foo/**"],
    )
    assert mixed["verification_scope_overreach"] is False, mixed
    assert not mod._dem08_implement_warn_pass(False, mixed, "write_set_closure"), mixed
    print("G1+G2+G5+G3+G6 oracle policy OK")
finally:
    shutil.rmtree(tmpdir)
PY4

echo "test-verification-oracle passed"
