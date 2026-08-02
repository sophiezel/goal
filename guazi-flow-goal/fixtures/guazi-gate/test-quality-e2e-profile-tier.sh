#!/bin/bash
# test-quality-e2e-profile-tier.sh — #19 e2e profile × tier matrix + quality-gate wiring
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts"
POLICY="$SCRIPTS/goal_quality_e2e_policy.py"
GATE="$SCRIPTS/quality-gate.sh"

export POLICY
python3 - <<'PY'
import importlib.util
import json
import os
import tempfile

spec = importlib.util.spec_from_file_location("goal_quality_e2e_policy", os.environ["POLICY"])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def mk(plan_profile="full", repo_profile="h5"):
    d = tempfile.mkdtemp()
    os.makedirs(f"{d}/handoff")
    os.makedirs(f"{d}/evidence")
    open(f"{d}/evidence/verification-oracle.json", "w").write('{"overall":"pass"}')
    open(f"{d}/evidence/runtime-smoke.md", "w").write('---\nresult: "pass"\n---\n')
    open(f"{d}/handoff/plan.json", "w").write(
        json.dumps({"plan_profile": plan_profile, "profile": repo_profile})
    )
    open(f"{d}/handoff/implement.json", "w").write('{"gate":{"passed_at":"2026-01-01T00:00:00Z"}}')
    open(f"{d}/index.md", "w").write(
        f"---\nplan_profile: {plan_profile}\nprofile: {repo_profile}\n---\n\n## 验证与验证矩阵\n| C1 | x |\n"
    )
    return d


assert mod.agent_orchestration_defaults("standard", "lite", "h5")["e2e"] == "off_default"
assert mod.agent_orchestration_defaults("strict", "lite", "h5")["e2e"] == "recommended"
assert mod.agent_orchestration_defaults("strict", "full", "backend")["e2e"] == "optional"
assert mod.gate_e2e_severity("standard", "h5") == "none"
assert mod.gate_e2e_severity("strict", "h5") == "block"
assert mod.gate_e2e_severity("strict", "backend") == "warn"
assert mod.gate_validate_severity("strict") == "warn"
assert mod.gate_validate_severity("standard") == "none"

td = mk("lite", "h5")
p = mod.resolve_policy(td, quality_tier="strict")
assert p["plan_profile"] == "lite"
assert p["gate"]["e2e_evidence"] == "block"
print("goal_quality_e2e_policy unit OK")
PY

bash "$DIR/test-phase-a2-e2e-block.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TASK="$TMP/task"
mkdir -p "$TASK/handoff" "$TASK/evidence"
echo '{"overall":"pass"}' > "$TASK/evidence/verification-oracle.json"
printf '%s\n' '---' 'result: "pass"' '---' > "$TASK/evidence/runtime-smoke.md"
cat > "$TASK/handoff/plan.json" <<JSON
{"plan_profile":"lite","profile":"h5","write_set":["src/x.ts"]}
JSON
echo '{"gate":{"passed_at":"2026-01-01T00:00:00Z"}}' > "$TASK/handoff/implement.json"
cat > "$TASK/index.md" <<MD
---
plan_profile: lite
profile: h5
---
## 验证与验证矩阵
| C1 | x |
MD
export GOAL_EVIDENCE_DIR="$TASK/evidence"
OUT=$(bash "$GATE" --task-dir "$TASK" --repo-root "$TMP" --tier strict --skip-iq 2>&1 || true)
echo "$OUT" | grep -q "BLOCK.*QG-L1-e2e" || { echo "FAIL: strict+lite+h5 missing e2e should BLOCK"; echo "$OUT"; exit 1; }
echo "OK: strict + plan_profile=lite + h5 → e2e BLOCK unchanged"

OUT_STD=$(bash "$GATE" --task-dir "$TASK" --repo-root "$TMP" --tier standard --skip-iq 2>&1 || true)
if echo "$OUT_STD" | grep -q "QG-L1-e2e"; then
  echo "FAIL: standard must not emit QG-L1-e2e"; echo "$OUT_STD"; exit 1
fi
echo "OK: standard tier → no QG-L1-e2e"

echo "test-quality-e2e-profile-tier passed"
