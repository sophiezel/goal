#!/bin/bash
# test-review-failfast-unreachable.sh — configured keys + all unreachable → cascade skipped
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_SCRIPTS:-${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts}"
ORCH="$SCRIPTS/review_fallback_orchestrator.py"
PACKET="$DIR/review-unified-good/handoff/review-packet.json"
[[ -f "$PACKET" ]] || { echo "missing fixture packet"; exit 1; }

# Force probe path: monkey via env — make probe report all unreachable by pointing keys
# and stubbing GOAL_REVIEW_PROBE with a fake detect via candidates override empty +
# we unit-test _unreachable through detect mock:

python3 - "$SCRIPTS" "$PACKET" << 'PY'
import importlib.util, json, os, sys, tempfile, time

scripts, packet = sys.argv[1:3]
sys.path.insert(0, scripts)
spec = importlib.util.spec_from_file_location("orch", os.path.join(scripts, "review_fallback_orchestrator.py"))
orch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(orch)

# Stub load_detect → configured but unreachable
orch.load_detect = lambda script_dir: {
    "has_candidates": False,
    "ranked": [],
    "selected": None,
    "configured_keys": True,
    "configured_but_unreachable": True,
    "probe_enabled": True,
}

t0 = time.time()
out = orch.run_fallback(
    scripts,
    packet,
    '{"overall":"pass"}',
    "unified",
    "deepseek",
    "deepseek-v4-flash",
    budget_sec=480,
    attempt_timeout_sec=240,
    max_api_attempts=3,
)
elapsed = time.time() - t0
assert out.get("ok") is False, out
body = out.get("review_body") or {}
assert body.get("error_kind") == "review_channel_unreachable", body
assert any(i.get("id") == "CH-UNREACHABLE" for i in (body.get("issues") or [])), body
assert elapsed < 5.0, f"fail-fast too slow: {elapsed}s (cascade leaked?)"
assert out.get("fallback_layer") == "hard_stop_unreachable", out
print(f"failfast_unreachable OK ({elapsed:.3f}s)")
PY

# merge infra → switch_to_cursor_task
python3 - "$SCRIPTS" << 'PY'
import importlib.util, json, os, sys, tempfile, shutil

scripts = sys.argv[1]
sys.path.insert(0, scripts)
spec = importlib.util.spec_from_file_location("m", os.path.join(scripts, "merge_review_core.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

issues = [{
    "id": "CH-UNREACHABLE",
    "severity": "blocker",
    "summary": "Review API channels unreachable — use Cursor Task",
    "channel": "goal",
    "root_cause": "infra_channel",
}]
assert m.issues_are_infra_only(issues, "review_undetermined")
assert m.compute_action("not_pass", issues, unified_result="review_undetermined") == "switch_to_cursor_task"
# ADP-ERR network should not become business fix
adp = [{"id": "ADP-ERR", "severity": "medium", "summary": "HTTP timeout after 90s", "channel": "goal"}]
assert m.compute_action("not_pass", adp, unified_result="review_undetermined") in ("fix_channel", "switch_to_cursor_task")
# Business issue still fix_and_rerun
biz = [{"id": "G01", "severity": "blocker", "summary": "missing C03", "channel": "goal", "root_cause": "implement_error"}]
assert m.compute_action("not_pass", biz, unified_result="not_pass") == "fix_and_rerun_review"
print("merge_infra_action OK")
PY

echo "test-review-failfast-unreachable passed"
