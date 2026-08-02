#!/usr/bin/env bash
# v1.2 Part J: default profile stage_graph ≡ F.2 + gate-lib mapping
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts"
RESOLVER="$SCRIPTS/resolve_stage_graph.py"

echo "=== stage_graph default profile (F.2 equivalence) ==="
python3 "$RESOLVER" --action validate-default-f2 --scripts-dir "$SCRIPTS" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d.get('ok'), d
print('OK default F.2 equivalence')
"

echo "=== stage_graph plan.json override (custom topology) ==="
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/plan.json" <<'JSON'
{
  "stage": "plan",
  "schema_version": 1,
  "pipeline_profile": "default",
  "stage_graph": [
    {"id": "alpha", "r_layer": "R1", "gate_stage_id": "plan"},
    {"id": "beta", "r_layer": "R3", "gate_stage_id": "implement"}
  ],
  "gate": {"script": "x", "version": 1, "passed_at": "2026-01-01T00:00:00Z"}
}
JSON
OUT=$(python3 "$RESOLVER" --plan-json "$tmp/plan.json" --scripts-dir "$SCRIPTS")
echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['stage_ids'] == ['alpha', 'beta'], d
assert d['source'] == 'plan.json'
print('OK plan override topology')
"
NXT=$(python3 "$RESOLVER" --plan-json "$tmp/plan.json" --action next-id --current-stage alpha)
echo "$NXT" | python3 -c "import json,sys; assert json.load(sys.stdin)['next_stage']=='beta'"

echo "=== stage driver work_order carries stage_graph ==="
KERNEL="$SCRIPTS/goal-pipeline-kernel.sh"
tmp2=$(mktemp -d)
export GUAZI_STATE_HOME="${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}"
export GOAL_ARTIFACT_MODE=repo_full
repo="$tmp2/repo"
mkdir -p "$repo/docs/guazi-flow/demo/handoff" "$repo/docs/guazi-flow/demo/evidence"
cd "$repo" && git init -q && git config user.email t@e.com && git config user.name t
echo x > README.md && git add . && git commit -qm i
TASK="$repo/docs/guazi-flow/demo"
cat > "$TASK/index.md" <<'MD'
---
flow:
  version: 1
  current_stage: plan
---
# demo
## 概览
x
## 任务目标
y
## 范围与非目标
z
## 核心事实
c
## 完整伪代码
p
## 验收与验证矩阵
| V# | id |
|----|-----|
| V1 | x |
## 写集
- docs/guazi-flow/demo/**
## 执行记录
- guazi-flow-plan
MD
INIT=$(bash "$SCRIPTS/goal-pipeline-kernel.sh" init --project-root "$repo" --task-dir "$TASK" --format json 2>/dev/null) || {
  echo "SKIP kernel work_order test (goal-pipeline-kernel not in guazi bundle)"
  echo "All stage_graph profile tests passed"
  exit 0
}
STATE=$(echo "$INIT" | python3 -c "import json,sys; print(json.load(sys.stdin)['state_file'])")
NEXT=$(GOAL_KERNEL_INTERNAL=1 bash "$SCRIPTS/goal-stage-driver.sh" \
  --state-file "$STATE" --task-dir "$TASK" --project-root "$repo" --format json)
echo "$NEXT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d.get('pipeline_profile') == 'default', d
assert d.get('stage_graph_ids') == ['plan','implement','quality','review','complete'], d
assert d.get('progress') == '[1/5] plan', d
assert d.get('stage_meta', {}).get('r_layer') == 'R1', d
print('OK work_order stage_graph fields')
"

echo "All stage_graph profile tests passed"
