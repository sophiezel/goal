#!/bin/bash
# test-argus-plan-post-orchestration.sh — C1 fe-argus WO + merge + advance gate
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
POL="$SCRIPTS/argus_plan_post_policy.py"
ENRICH="$SCRIPTS/argus_enrich_plan.py"
FIX="$DIR/plan-write-set-xieji"
LITE="$DIR/plan-lite-good"

echo "=== policy triggers ==="
python3 - "$POL" "$LITE" "$FIX" << 'PY'
import json, subprocess, sys
pol, lite, full = sys.argv[1:4]
for label, td, expect in [
    ("lite", lite, False),
    ("pages+S", full, True),
]:
    out = json.loads(subprocess.check_output(
        ["python3", pol, "--resolve-from-task-dir", "--task-dir", td], text=True
    ))
    assert out["fe_argus_skill_required"] is expect, (label, out)
print("OK triggers")
PY

echo "=== merge_scenario_lists rule wins ==="
python3 - "$ENRICH" << 'PY'
import importlib.util
import sys
from pathlib import Path
p = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("aep", p)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
rule = [{"id": "page-domain", "severity": "soft", "source": "rule", "w1_status": "open"}]
argus = [
    {"id": "page-domain", "severity": "soft", "source": "argus", "w1_status": "open"},
    {"id": "fe-argus-q1", "severity": "soft", "source": "argus", "w1_status": "open"},
]
doc = mod.merge_scenario_lists(rule, argus, argus_status="merged")
by_id = {r["id"]: r for r in doc["scenarios"]}
assert by_id["page-domain"]["source"] == "rule"
assert by_id["fe-argus-q1"]["source"] == "argus"
assert doc["argus_enrich_status"] == "merged"
print("OK merge")
PY

echo "=== merge CLI ==="
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/handoff"
python3 "$ENRICH" --task-dir "$FIX" --handoff-dir "$TMP/handoff" --out "$TMP/handoff/argus-scenario-manifest.json"
cat > "$TMP/handoff/fe-argus-scenarios-pending.json" << 'JSON'
{"scenarios": [{"id": "scenario-q-demo", "severity": "soft", "w1_status": "open", "verify_hint": "fe-argus"}]}
JSON
python3 "$ENRICH" --task-dir "$FIX" --handoff-dir "$TMP/handoff" \
  --merge-fe-argus-file "$TMP/handoff/fe-argus-scenarios-pending.json" --merge-status merged
python3 "$POL" --check-plan-post \
  --plan-json "$FIX/handoff/plan.json" \
  --manifest-json "$TMP/handoff/argus-scenario-manifest.json"
python3 - "$TMP/handoff/argus-scenario-manifest.json" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["argus_enrich_status"] == "merged"
ids = {s["id"] for s in d["scenarios"]}
assert "scenario-q-demo" in ids
print("OK merge CLI")
PY

echo "=== advance blocks rule_only when required ==="
set +e
python3 "$POL" --check-plan-post \
  --plan-json "$FIX/handoff/plan.json" \
  --manifest-json "$FIX/handoff/argus-scenario-manifest.json" >/dev/null
RC=$?
set -e
[[ "$RC" -ne 0 ]] || { echo "FAIL expected block on rule_only"; exit 1; }
echo "OK advance gate"

echo "=== fe_argus_skill discover + WO hints ==="
python3 - "$POL" "$FIX" << 'PY'
import importlib.util
import json
import subprocess
import sys
from pathlib import Path
pol, fix = sys.argv[1:3]
spec = importlib.util.spec_from_file_location("appp", pol)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
disc = mod.fe_argus_skill_discover()
assert "install_one_liner" in disc and "curl" in disc["install_one_liner"]
assert disc["skill_name"] == "fe-argus"
wo = json.loads(
    subprocess.check_output(
        ["python3", pol, "--work-order-json", "--task-dir", fix],
        text=True,
    )
)
assert wo["fe_argus_plan_post"]["required"] is True
assert "fe_argus_skill" in wo
assert wo["fe_argus_plan_post"].get("install_one_liner") == disc["install_one_liner"]
print("OK discover WO")
PY

echo "=== stage driver WO injects fe-argus ==="
DRIVER="$SCRIPTS/goal-stage-driver.sh"
ADVANCE="$SCRIPTS/goal-advance-stage.sh"
TASK_TMP="$TMP/task-driver"
mkdir -p "$TASK_TMP"
cp "$FIX/index.md" "$TASK_TMP/"
STATE="$TMP/state-driver.json"
cat > "$STATE" << JSON
{"pipeline_track":"compatibility","status":"active","current_stage":"plan","project_root":"$TASK_TMP","guazi_flow_task":"."}
JSON
# advance: index present, no plan handoff → next_stage plan
ADV=$(bash "$ADVANCE" --state-file "$STATE" --task-dir "$TASK_TMP" --project-root "$TASK_TMP" --format json)
echo "$ADV" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('next_stage')=='plan', d"
OUT=$(GOAL_KERNEL_COMPAT_WARN=0 bash "$DRIVER" \
  --state-file "$STATE" \
  --task-dir "$TASK_TMP" \
  --project-root "$TASK_TMP" \
  --format json 2>/dev/null)
echo "$OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('fe_argus_plan_post',{}).get('required') is True
assert 'fe-argus' in (d.get('skills_to_load') or [])
cmds=' '.join(d.get('mandatory_commands') or [])
assert 'fe-argus' in cmds or 'argus_plan_post_policy' in cmds
print('OK driver WO')
"

echo "test-argus-plan-post-orchestration passed"
