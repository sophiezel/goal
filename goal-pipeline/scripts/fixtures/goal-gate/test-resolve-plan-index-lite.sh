#!/bin/bash
# test-resolve-plan-index-lite.sh — lite profile resolves lite rules + PQ pass
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/index.md" <<'EOF'
---
version: 1
current_stage: plan
profile: h5
profile_detail: react
plan_profile: lite
task_tier: S
---

## 概览

XS 常量文案修改。

## 任务目标

- 修改按钮常量

## 范围与写集

**In scope**

- `src/constants/buttons.ts`

**Out of scope**

- 其他页面

## 完整伪代码

```ts
export const SUBMIT_LABEL = "确认提交";
export const CANCEL_LABEL = "取消";
```

## 验收与验证矩阵

| ID | Case | Expected | 执行方式 |
|----|------|----------|----------|
| C01 | SUBMIT_LABEL 值 | 确认提交 | automated |
| C02 | ts 类型检查 | tsc pass | automated |
| V01 | 构建通过 | yarn build pass | automated |

## 执行记录

| Stage | Skill | Result |
|-------|-------|--------|
| plan | goal-plan | pass |
EOF

# Test 1: frontmatter plan_profile: lite → lite
PROFILE=$(python3 "$SCRIPTS/resolve_plan_index_rules.py" --index "$TMP/index.md" --format json | python3 -c "import json,sys; print(json.load(sys.stdin)['profile'])")
[[ "$PROFILE" == "lite" ]] || { echo "FAIL: expected lite profile got $PROFILE"; exit 1; }
echo "OK: frontmatter plan_profile → lite"

# Test 2: rules path points to lite
RULES=$(python3 "$SCRIPTS/resolve_plan_index_rules.py" --index "$TMP/index.md" --format path)
[[ "$RULES" == *"plan-index-rules-lite.json" ]] || { echo "FAIL: expected lite rules path got $RULES"; exit 1; }
echo "OK: rules path → plan-index-rules-lite.json"

# Test 3: PQ gate passes on lite index
PQ=$(python3 "$SCRIPTS/plan-quality-gate.py" --task-dir "$TMP" --json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['plan_profile'], d['passed'])")
[[ "$PQ" == "lite True" ]] || { echo "FAIL: PQ lite gate expected 'lite True' got '$PQ'"; exit 1; }
echo "OK: PQ gate passes on lite index"

# Test 4: index with units[] → full (pre-estimate fails: has units)
cat > "$TMP/index-full.md" <<'EOF'
---
version: 1
current_stage: plan
profile: h5
profile_detail: react
---

## 概览
test

## 任务目标
test

## 范围与非目标
test

## 核心事实
test

## 完整伪代码
```ts
function Foo() { return <div>hello world this is a full pseudocode section that exceeds 200 chars for the standard tier validation to pass without issues</div>; }
```

## 验收与验证矩阵
| C01 | a | b | manual |

## 执行记录
| plan | goal-plan | pass |

## units
- src/a.ts
- src/b.ts
- src/c.ts
- src/d.ts
EOF
PROFILE_FULL=$(python3 "$SCRIPTS/resolve_plan_index_rules.py" --index "$TMP/index-full.md" --format json | python3 -c "import json,sys; print(json.load(sys.stdin)['profile'])")
[[ "$PROFILE_FULL" == "full" ]] || { echo "FAIL: expected full profile got $PROFILE_FULL"; exit 1; }
echo "OK: has units[] → full"

# Test 5: M+ task_tier in plan.json → forced full (overrides frontmatter lite)
mkdir -p "$TMP/handoff"
echo '{"task_tier":"M"}' > "$TMP/handoff/plan.json"
PROFILE_M=$(python3 "$SCRIPTS/resolve_plan_index_rules.py" --index "$TMP/index.md" --plan-json "$TMP/handoff/plan.json" --format json | python3 -c "import json,sys; print(json.load(sys.stdin)['profile'])")
[[ "$PROFILE_M" == "full" ]] || { echo "FAIL: M+ task_tier expected full got $PROFILE_M"; exit 1; }
echo "OK: M+ task_tier → forced full"

# Test 6: frontmatter plan_profile: full overrides plan.json XS/S
cat > "$TMP/index-full-fm.md" <<'EOF'
---
version: 1
current_stage: plan
profile: h5
profile_detail: react
plan_profile: full
task_tier: S
---

## 概览
test
EOF
mkdir -p "$TMP/handoff-s"
echo '{"task_tier":"S"}' > "$TMP/handoff-s/plan.json"
PROFILE_FM_FULL=$(python3 "$SCRIPTS/resolve_plan_index_rules.py" --index "$TMP/index-full-fm.md" --plan-json "$TMP/handoff-s/plan.json" --format json | python3 -c "import json,sys; print(json.load(sys.stdin)['profile'])")
[[ "$PROFILE_FM_FULL" == "full" ]] || { echo "FAIL: frontmatter full should override plan.json S, got $PROFILE_FM_FULL"; exit 1; }
echo "OK: frontmatter plan_profile=full overrides plan.json XS/S"

echo "test-resolve-plan-index-lite passed"
