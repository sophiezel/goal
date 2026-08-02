#!/bin/bash
# Unit-ish tests for index_contract_hash + merge severity + verify build skip
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_SCRIPTS:-${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts}"
HASH_PY="$SCRIPTS/index_contract_hash.py"
MERGE_PY="$SCRIPTS/merge_review_core.py"
GATE="$SCRIPTS/guazi-gate-stage.sh"
export GOAL_ARTIFACT_MODE=repo_full
export GOAL_SKIP_BUILD=1

echo "=== index_contract_hash: execution-only change keeps contract hash ==="
TMP=$(mktemp -d)
cp -R "$SCRIPT_DIR/plan-good/." "$TMP/task/"
H1=$(python3 "$HASH_PY" "$TMP/task/index.md")
# append execution record
printf '\n- 2026-07-09 [guazi-flow-implement]: done\n' >> "$TMP/task/index.md"
H2=$(python3 "$HASH_PY" "$TMP/task/index.md")
if [[ "$H1" != "$H2" ]]; then
  echo "FAIL contract hash changed after execution append: $H1 vs $H2"; exit 1
fi
echo "OK execution-only preserves contract hash ($H1)"

echo "=== index_contract_hash: write_set change alters contract hash ==="
# change write_set section (after 执行记录 in plan-good — move write_set before 执行记录 for this test)
# plan-good has write_set AFTER 执行记录; contract hash excludes 执行记录 and after,
# so mutating write_set after 执行记录 should NOT change contract hash.
# Create a variant with write_set before 执行记录:
python3 - "$TMP/task/index.md" << 'PY'
from pathlib import Path
p = Path(__import__("sys").argv[1])
text = p.read_text(encoding="utf-8")
# Insert a write_set bullet into 核心事实 (contract section)
text2 = text.replace("## 核心事实\n\n", "## 核心事实\n\n- `src/changed/`\n\n", 1)
p.write_text(text2, encoding="utf-8")
PY
H3=$(python3 "$HASH_PY" "$TMP/task/index.md")
if [[ "$H1" == "$H3" ]]; then
  echo "FAIL contract hash unchanged after contract edit"; exit 1
fi
echo "OK contract edit changes hash ($H1 → $H3)"
rm -rf "$TMP"

echo "=== plan-stale-execution-only: review pre should PASS ==="
FIX="$SCRIPT_DIR/plan-stale-execution-only"
rm -rf "$FIX/handoff" "$FIX/evidence"
mkdir -p "$FIX/handoff" "$FIX/evidence"
# Build index from plan-good, run plan post, then append execution record
cp "$SCRIPT_DIR/plan-good/index.md" "$FIX/index.md"
# Ensure write_set section is before 执行记录 for plan gate — plan-good already has sections
"$GATE" --task-dir "$FIX" --stage plan --post --mode guazi >/dev/null
# Create minimal implement handoff
python3 - "$FIX" << 'PY'
import json, hashlib
from pathlib import Path
from datetime import datetime, timezone
fix = Path(__import__("sys").argv[1])
plan = json.loads((fix/"handoff/plan.json").read_text())
# append execution
idx = fix/"index.md"
idx.write_text(idx.read_text(encoding="utf-8") + "\n- extra implement note\n", encoding="utf-8")
impl = {
  "stage": "implement",
  "schema_version": 1,
  "skill_expected": "guazi-flow-implement",
  "skill_executed": True,
  "write_set": plan.get("write_set", []),
  "changed_files": [],
  "git_head": "deadbeef",
  "candidate_diff_hash": "0"*16,
  "artifact_paths": ["index.md"],
  "gate": {"script": "guazi-gate-stage.sh", "version": 1, "passed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")},
}
(fix/"handoff/implement.json").write_text(json.dumps(impl, indent=2))
MIN_DIFF = "diff --git a/src/fixture.ts b/src/fixture.ts\n" + "+export const fixture = 1;\n" * 25
MIN_PKT = {
  "schema_version": 1,
  "diff": MIN_DIFF,
  "diff_source": "reference_branch",
  "reference_branch": "main...HEAD",
  "integrity": {"ok": True, "errors": []},
  "deterministic_checks": {"overall": "pass"},
  "changed_files": ["src/fixture.ts"],
}
(fix/"handoff/review-packet.json").write_text(json.dumps(MIN_PKT, indent=2))
(fix/"evidence").mkdir(exist_ok=True)
uvo = {
  "schema_version": 1,
  "overall": "pass",
  "oracle_mode": "related_union",
  "git_head": "unknown",
  "candidate_diff_hash": "unknown",
  "passed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
  "steps": [{"id": "scope", "pass": True}, {"id": "secret", "pass": True}],
}
(fix/"evidence/verification-oracle.json").write_text(json.dumps(uvo, indent=2))
# ensure implement marker in index
t = idx.read_text(encoding="utf-8")
if "guazi-flow-implement" not in t:
    idx.write_text(t + "\n- guazi-flow-implement pass\n", encoding="utf-8")
PY
# review pre: should NOT fail on stale (execution only)
export GOAL_SKIP_BUILD=1
export GOAL_SKIP_TEST=1
export GOAL_SKIP_LINT=1
export GOAL_SKIP_SCOPE=1
export GOAL_SKIP_SECRET=1

if "$GATE" --task-dir "$FIX" --stage review --pre --mode guazi; then
  echo "OK plan-stale-execution-only review pre PASS"
else
  echo "FAIL plan-stale-execution-only expected PASS"; exit 1
fi

echo "=== plan-stale-contract-changed: review pre should FAIL ==="
FIX2="$SCRIPT_DIR/plan-stale-contract-changed"
rm -rf "$FIX2/handoff" "$FIX2/evidence"
mkdir -p "$FIX2/handoff" "$FIX2/evidence"
cp "$SCRIPT_DIR/plan-good/index.md" "$FIX2/index.md"
"$GATE" --task-dir "$FIX2" --stage plan --post --mode guazi >/dev/null
python3 - "$FIX2" << 'PY'
import json
from pathlib import Path
from datetime import datetime, timezone
fix = Path(__import__("sys").argv[1])
plan = json.loads((fix/"handoff/plan.json").read_text())
idx = fix/"index.md"
t = idx.read_text(encoding="utf-8")
# mutate contract section
t = t.replace("## 核心事实\n\n", "## 核心事实\n\nCHANGED CONTRACT LINE\n\n", 1)
if "guazi-flow-implement" not in t:
    t += "\n- guazi-flow-implement pass\n"
idx.write_text(t, encoding="utf-8")
impl = {
  "stage": "implement", "schema_version": 1, "skill_executed": True,
  "write_set": plan.get("write_set", []), "changed_files": [],
  "git_head": "deadbeef", "candidate_diff_hash": "0"*16,
  "artifact_paths": ["index.md"],
  "gate": {"passed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")},
}
(fix/"handoff/implement.json").write_text(json.dumps(impl, indent=2))
MIN_DIFF = "diff --git a/src/fixture.ts b/src/fixture.ts\n" + "+export const fixture = 1;\n" * 25
MIN_PKT = {
  "schema_version": 1,
  "diff": MIN_DIFF,
  "diff_source": "reference_branch",
  "reference_branch": "main...HEAD",
  "integrity": {"ok": True, "errors": []},
  "deterministic_checks": {"overall": "pass"},
  "changed_files": ["src/fixture.ts"],
}
(fix/"handoff/review-packet.json").write_text(json.dumps(MIN_PKT, indent=2))
(fix/"evidence").mkdir(exist_ok=True)
uvo = {
  "schema_version": 1,
  "overall": "pass",
  "oracle_mode": "related_union",
  "git_head": "unknown",
  "candidate_diff_hash": "unknown",
  "passed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
  "steps": [{"id": "scope", "pass": True}, {"id": "secret", "pass": True}],
}
(fix/"evidence/verification-oracle.json").write_text(json.dumps(uvo, indent=2))
PY
if "$GATE" --task-dir "$FIX2" --stage review --pre --mode guazi; then
  echo "FAIL plan-stale-contract-changed expected FAIL"; exit 1
else
  echo "OK plan-stale-contract-changed review pre FAIL"
fi

echo "=== merge_review_core: minor is not blocker ==="
python3 - "$MERGE_PY" << 'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("merge_review_core", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
iss = mod.normalize_issue({"severity": "minor", "summary": "V02 not verified"}, "guazi-flow-review", 1)
assert iss["severity"] == "warning", iss
iss2 = mod.normalize_issue({"severity": "medium", "summary": "x"}, "goal", 1)
assert iss2["severity"] == "warning", iss2
iss3 = mod.normalize_issue({"severity": "blocker", "summary": "x"}, "goal", 1)
assert iss3["severity"] == "blocker", iss3
# merged_result with only warning issues should be pass if unified pass
assert mod.compute_action("pass", [iss]) == "proceed_complete"
print("OK minor/medium → warning; blocker stays blocker")
PY

echo "=== write_set normalize /** ==="
python3 - "$HASH_PY" << 'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("h", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
assert m.normalize_write_set(["src/a/**", "src/b"]) == ["src/a/", "src/b"]
assert m.path_allowed("src/a/x.ts", ["src/a/**"])
print("OK write_set normalize + path_allowed")
PY

echo "=== verify-review build skip ==="
OUT=$(GOAL_SKIP_BUILD=1 bash "$ROOT/verify-review.sh" "$SCRIPT_DIR/plan-good" "src/" json)
echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'build' in d['checks']; assert d['checks']['build']['pass'] is True; print('OK build check present and skipped')"

echo "All P0/P1 fixture unit tests passed"
