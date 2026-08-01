#!/usr/bin/env bash
# v1.2 Part K: engineering_pack profile + Phase 1 work_order soft-load
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/../../resolve_engineering_pack.py"

echo "=== engineering_pack default profile (none) ==="
python3 "$RESOLVER" --profile default | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d.get('ok') and d.get('engineering_pack') == 'none' and d.get('skills_to_load') == [], d
print('OK default none')
"

echo "=== engineering_pack grill-pack profile ==="
python3 "$RESOLVER" --profile grill-pack --validate-stubs | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d.get('ok') and d.get('stubs_ok'), d
assert d.get('engineering_pack') == 'grill', d
assert d.get('skills_to_load') == ['goal-engineering-grill'], d
print('OK grill-pack profile + stubs')
"

echo "=== engineering_pack plan.json override (grill_to_specs) ==="
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/plan.json" <<'JSON'
{
  "stage": "plan",
  "schema_version": 1,
  "pipeline_profile": "default",
  "engineering_pack": "grill_to_specs",
  "gate": {"script": "x", "version": 1, "passed_at": "2026-01-01T00:00:00Z"}
}
JSON
python3 "$RESOLVER" --plan-json "$tmp/plan.json" --validate-stubs | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d.get('source') == 'plan.json', d
assert d.get('skills_to_load') == ['goal-engineering-grill', 'goal-engineering-to-specs'], d
print('OK plan override grill_to_specs')
"

echo "=== goal-stage-driver plan WO carries engineering_pack ==="
KERNEL="$SCRIPT_DIR/../../goal-pipeline-kernel.sh"
tmp2=$(mktemp -d)
export GOAL_STATE_HOME="$tmp2/gs"
export GOAL_ARTIFACT_MODE=repo_full
mkdir -p "$GOAL_STATE_HOME/scripts"
for f in goal-stage-driver.sh gate-guazi-flow-stage.sh goal-advance-stage.sh assert-plan-before-code.sh validate-state-path.sh; do
  ln -sf "$SCRIPT_DIR/../../$f" "$GOAL_STATE_HOME/scripts/$f" 2>/dev/null || cp "$SCRIPT_DIR/../../$f" "$GOAL_STATE_HOME/scripts/$f"
done
for f in assert_plan_before_code.py resolve-artifact-paths.py review_track.py argus_plan_post_policy.py goal_state_paths.py; do
  ln -sf "$SCRIPT_DIR/../../$f" "$GOAL_STATE_HOME/scripts/$f" 2>/dev/null || cp "$SCRIPT_DIR/../../$f" "$GOAL_STATE_HOME/scripts/$f"
done
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
INIT=$(bash "$KERNEL" init --project-root "$repo" --task-dir "$TASK" --format json)
STATE=$(echo "$INIT" | python3 -c "import json,sys; print(json.load(sys.stdin)['state_file'])")
cat > "$TASK/handoff/plan.json" <<'JSON'
{
  "stage": "plan",
  "schema_version": 1,
  "pipeline_profile": "grill-pack"
}
JSON
NEXT=$(GOAL_KERNEL_INTERNAL=1 bash "$SCRIPT_DIR/../../goal-stage-driver.sh" \
  --state-file "$STATE" --task-dir "$TASK" --project-root "$repo" --format json)
echo "$NEXT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d.get('engineering_pack') == 'grill', d
assert d.get('pipeline_profile') == 'grill-pack', d
assert d.get('next_stage') == 'plan', d
assert 'goal-engineering-grill' in (d.get('skills_to_load') or []), d
assert any('engineering_pack=grill' in c for c in d.get('mandatory_commands') or []), d
print('OK work_order engineering_pack hook')
"

echo "All engineering_pack tests passed"
