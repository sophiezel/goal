#!/bin/bash
# test-implement-write-set-pre-block.sh — implement pre BLOCKs empty write_set (v3 §10.2 D15, W1.5)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_SCRIPTS:-${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts}"
GATE="$SCRIPTS/guazi-gate-stage.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' exit

# Build a minimal task dir with handoff/plan.json (empty write_set) + index.md
TASK="$TMP/task"
mkdir -p "$TASK/handoff" "$TASK/evidence"
cat > "$TASK/handoff/plan.json" <<JSON
{ "write_set": [], "reference_branch": "main...HEAD", "passed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)" }
JSON
cat > "$TASK/index.md" <<MD
---
version: 1
current_stage: implement
profile: h5
plan_profile: full
---

## 概览
x

## 任务目标
x

## 范围与写集

## 完整伪代码
function f(){ return 1; }

## 验收与验证矩阵
| ID | 描述 | verify_command |
|----|------|----------------|
| C1 | works | yarn test |

## 执行记录
- guazi-flow-implement done
MD

export GOAL_ARTIFACT_MODE=repo_full
export GOAL_TASK_DIR="$TASK"
export GOAL_HANDOFF_DIR="$TASK/handoff"
export GOAL_EVIDENCE_DIR="$TASK/evidence"
export GOAL_STATE_FILE="$TMP/state.json"
echo '{}' > "$TMP/state.json"

make_plan_json() {
  local ws_json="$1"
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cat > "$TASK/handoff/plan.json" <<JSON
{
  "stage": "plan",
  "schema_version": 1,
  "skill_expected": "guazi-flow-plan",
  "skill_executed": true,
  "profile": "h5",
  "plan_profile": "full",
  "write_set": $ws_json,
  "acceptance_matrix_ids": ["C01"],
  "verification": {"build_command": "CI= yarn build:beta"},
  "gate": {"script": "guazi-gate-stage.sh", "version": 1, "passed_at": "$now", "post_exit_code": 0}
}
JSON
}

# Case 1: empty write_set → implement pre must FAIL
make_plan_json '[]'
if bash "$GATE" --task-dir "$TASK" --stage implement --pre >/tmp/pre-empty.log 2>&1; then
  echo "FAIL: implement pre should block empty write_set"; cat /tmp/pre-empty.log; exit 1
fi
grep -q "write_set empty at implement-pre" /tmp/pre-empty.log || { echo "FAIL: missing pre-BLOCK message"; cat /tmp/pre-empty.log; exit 1; }
echo "OK: empty write_set blocked at implement-pre"

# Case 2: non-empty write_set → implement pre does not trigger pre-BLOCK
make_plan_json '["src/x.ts"]'
bash "$GATE" --task-dir "$TASK" --stage implement --pre >/tmp/pre-nonempty.log 2>&1 || true
if grep -q "write_set empty at implement-pre" /tmp/pre-nonempty.log; then
  echo "FAIL: non-empty write_set should not trigger pre-BLOCK"; cat /tmp/pre-nonempty.log; exit 1
fi
echo "OK: non-empty write_set does not trigger pre-BLOCK"

echo "test-implement-write-set-pre-block passed"
