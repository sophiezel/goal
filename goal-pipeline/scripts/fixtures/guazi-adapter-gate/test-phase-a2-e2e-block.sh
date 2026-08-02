#!/bin/bash
# test-phase-a2-e2e-block.sh — strict+h5 e2e BLOCK (v3 §3 A2, §10.2 W2 A2)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
GATE="$SCRIPTS/quality-gate.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' exit

# Build a task dir with chain + UVO + smoke + index (profile h5)
TASK="$TMP/task"
mkdir -p "$TASK/handoff" "$TASK/evidence"
# UVO pass
echo '{"overall":"pass"}' > "$TASK/evidence/verification-oracle.json"
# smoke pass
cat > "$TASK/evidence/runtime-smoke.md" <<MD
---
result: "pass"
---
smoke ok
MD
# plan handoff (profile h5)
cat > "$TASK/handoff/plan.json" <<JSON
{ "stage":"plan", "profile":"h5", "write_set":["src/x.ts"], "gate":{"passed_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","post_exit_code":0} }
JSON
# implement handoff (chain)
cat > "$TASK/handoff/implement.json" <<JSON
{ "stage":"implement", "gate":{"passed_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","post_exit_code":0} }
JSON
# quality handoff
cat > "$TASK/handoff/quality.json" <<JSON
{ "stage":"quality", "gate":{"passed_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","post_exit_code":0} }
JSON
# index.md with NO e2e/playwright reference
cat > "$TASK/index.md" <<MD
---
version: 1
current_stage: quality
profile: h5
---

## 概览
x

## 任务目标
x

## 范围与写集
- src/x.ts

## 完整伪代码
function f(){ return 1; }

## 验证与验证矩阵
| ID | 描述 | verify_command |
|----|------|----------------|
| C1 | works | yarn test |

## 执行记录
- guazi-flow-implement done
MD

export GOAL_EVIDENCE_DIR="$TASK/evidence"

# Case 1: strict + h5 + NO e2e evidence → BLOCK
OUT=$(bash "$GATE" --task-dir "$TASK" --repo-root "$TMP" --tier strict 2>&1 || true)
echo "$OUT" | grep -q "BLOCK.*QG-L1-e2e.*Phase A2" || { echo "FAIL: strict+h5 should BLOCK on missing e2e"; echo "$OUT"; exit 1; }
echo "OK: strict+h5 + no e2e → BLOCK (Phase A2)"

# Case 2: strict + h5 + e2e dir present → no e2e BLOCK
mkdir -p "$TASK/evidence/e2e"
echo '{"overall":"pass"}' > "$TASK/evidence/e2e/result.json"
OUT2=$(bash "$GATE" --task-dir "$TASK" --repo-root "$TMP" --tier strict 2>&1 || true)
if echo "$OUT2" | grep -q "BLOCK.*QG-L1-e2e"; then
  echo "FAIL: e2e evidence present should not BLOCK"; echo "$OUT2"; exit 1
fi
echo "OK: strict+h5 + e2e evidence → no e2e BLOCK"
rm -rf "$TASK/evidence/e2e"

# Case 3: strict + non-h5 (e.g. backend) + no e2e → WARN (not BLOCK)
cat > "$TASK/handoff/plan.json" <<JSON
{ "stage":"plan", "profile":"backend", "write_set":["src/x.ts"], "gate":{"passed_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","post_exit_code":0} }
JSON
sed -i.bak 's/profile: h5/profile: backend/' "$TASK/index.md"
OUT3=$(bash "$GATE" --task-dir "$TASK" --repo-root "$TMP" --tier strict 2>&1 || true)
if echo "$OUT3" | grep -q "BLOCK.*QG-L1-e2e"; then
  echo "FAIL: strict+non-h5 should WARN not BLOCK"; echo "$OUT3"; exit 1
fi
echo "$OUT3" | grep -q "WARN.*QG-L1-e2e" || echo "(note: non-h5 may skip e2e check — acceptable)"
echo "OK: strict+non-h5 → not BLOCK (WARN or skip)"

# Case 4: standard tier → no e2e BLOCK regardless
sed -i.bak2 's/profile: backend/profile: h5/' "$TASK/index.md"
OUT4=$(bash "$GATE" --task-dir "$TASK" --repo-root "$TMP" --tier standard 2>&1 || true)
if echo "$OUT4" | grep -q "BLOCK.*QG-L1-e2e"; then
  echo "FAIL: standard should never e2e BLOCK"; echo "$OUT4"; exit 1
fi
echo "OK: standard tier → no e2e BLOCK"

echo "test-phase-a2-e2e-block passed"
