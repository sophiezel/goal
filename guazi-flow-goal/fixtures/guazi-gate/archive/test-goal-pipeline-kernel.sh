#!/usr/bin/env bash
# Kernel facade + four-plane doctor fixtures
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL="$SCRIPT_DIR/../../goal-pipeline-kernel.sh"
FOUR="$SCRIPT_DIR/../../four_planes_doctor.py"
DATA="$SCRIPT_DIR/../../data_plane_check.py"
EFF="$SCRIPT_DIR/../../efficiency_plane_check.py"
QUAL="$SCRIPT_DIR/../../quality_plane_check.py"

chmod +x "$KERNEL" 2>/dev/null || true
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GOAL_STATE_HOME="$tmp/gs"
export GOAL_ARTIFACT_MODE=repo_full
mkdir -p "$GOAL_STATE_HOME/scripts"
# Point internal bins to repo scripts
for f in goal-stage-driver.sh guazi-gate-stage.sh goal-advance-stage.sh assert-plan-before-code.sh validate-state-path.sh; do
  ln -sf "$SCRIPT_DIR/../../$f" "$GOAL_STATE_HOME/scripts/$f" 2>/dev/null || cp "$SCRIPT_DIR/../../$f" "$GOAL_STATE_HOME/scripts/$f"
done
# py helpers
for f in assert_plan_before_code.py resolve-artifact-paths.py; do
  ln -sf "$SCRIPT_DIR/../../$f" "$GOAL_STATE_HOME/scripts/$f" 2>/dev/null || cp "$SCRIPT_DIR/../../$f" "$GOAL_STATE_HOME/scripts/$f"
done

repo="$tmp/repo"
mkdir -p "$repo/docs/guazi-flow/demo-task/handoff" "$repo/docs/guazi-flow/demo-task/evidence"
cd "$repo"
git init -q
git config user.email t@e.com
git config user.name t
echo x > README.md && git add . && git commit -qm i
TASK="$repo/docs/guazi-flow/demo-task"
cat > "$TASK/index.md" <<'MD'
---
flow:
  version: 1
  current_stage: plan
  profile: h5
  profile_detail: react
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
- docs/guazi-flow/demo-task/**
## 执行记录
- guazi-flow-plan
MD

echo "=== kernel init ==="
INIT=$(bash "$KERNEL" init --project-root "$repo" --task-dir "$TASK" --format json)
echo "$INIT"
STATE=$(echo "$INIT" | python3 -c "import json,sys; print(json.load(sys.stdin)['state_file'])")
[[ -f "$STATE" ]] || { echo "FAIL no state"; exit 1; }
PID=$(python3 -c "import json; print(json.load(open('$STATE'))['project_id'])")
EXP=$(python3 -c "from pathlib import Path; import hashlib; print(hashlib.sha256(str(Path('$repo').resolve()).encode()).hexdigest()[:12])")
[[ "$PID" == "$EXP" ]] || { echo "FAIL project_id $PID != $EXP"; exit 1; }
echo "OK init project_id"

echo "=== kernel next on plan (clean) ==="
NEXT=$(bash "$KERNEL" next --state-file "$STATE" --task-dir "$TASK" --project-root "$repo" --format json)
echo "$NEXT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('next_stage')=='plan' or d.get('kernel'); assert d.get('code_writes_allowed') in (False, None) or d.get('next_stage')=='plan'; print('next_stage', d.get('next_stage'), 'code_writes', d.get('code_writes_allowed'))"
# plan stage must not allow code writes
echo "$NEXT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('code_writes_allowed') is False, d; assert 'capability' in d"

echo "=== kernel next blocks dirty src without plan gate ==="
mkdir -p "$repo/src"
echo "x" > "$repo/src/a.js"
NEXT2=$(bash "$KERNEL" next --state-file "$STATE" --task-dir "$TASK" --project-root "$repo" --format json)
echo "$NEXT2" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('blocked') is True, d; assert d.get('blocked_reason')=='plan_code_order' or d.get('failure_code')=='plan_code_order'; print('OK blocked plan_code_order')"
rm -f "$repo/src/a.js"

echo "=== four_planes_doctor ==="
python3 "$FOUR" --project-root "$repo" --format json | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['ok'] is True, d; assert d['planes_summary']['control']['ok']; print('OK four planes')"

echo "=== data_plane_check ==="
python3 "$DATA" --task-dir "$TASK" --project-root "$repo" --state-file "$STATE" --format json | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['ok'] is True, d; print('OK data')"

echo "=== efficiency_plane_check ==="
python3 "$EFF" --format json | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['ok'] is True, d; print('OK efficiency')"

echo "=== quality_plane_check forged review ==="
mkdir -p "$TASK/evidence"
cat > "$TASK/evidence/review.md" <<'R'
---
result: pass
---
# forged
R
set +e
python3 "$QUAL" --task-dir "$TASK" --project-root "$repo" --mode complete --format json
QRC=$?
set -e
[[ "$QRC" -eq 2 ]] || { echo "FAIL expected quality check fail"; exit 1; }
echo "OK forged review blocked"

echo "=== kernel status ==="
bash "$KERNEL" status --state-file "$STATE" --task-dir "$TASK" --project-root "$repo" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('kernel')=='goal-pipeline-kernel'; assert 'planes' in d; print('OK status')"

echo "=== adapter assert_capability denies src under plan WO ==="
WO_FILE="$tmp/wo.json"
echo "$NEXT" > "$WO_FILE"
ADAPT="$SCRIPT_DIR/../../../adapters/assert_capability.py"
set +e
python3 "$ADAPT" --work-order "$WO_FILE" --path src/a.js --project-root "$repo"
ARC=$?
set -e
[[ "$ARC" -eq 2 ]] || { echo "FAIL adapter should deny rc=$ARC"; exit 1; }
echo "OK adapter deny"

echo "=== migration refs ==="
[[ -f "$SCRIPT_DIR/../../../references/migration-compat.md" ]]
[[ -f "$SCRIPT_DIR/../../../references/measure-field-template.json" ]]
echo "OK migration refs"

echo "OK test-goal-pipeline-kernel"
