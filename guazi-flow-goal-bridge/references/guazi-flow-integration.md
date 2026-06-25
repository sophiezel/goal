# Guazi Flow 集成规则

guazi-flow-goal 作为 goal-pipeline 内核与 guazi-flow-* 系列之间的桥接层。
goal-pipeline 内核独立运行。guazi-flow-* 可用时按本规则调度。

## 可用性检测

```
加载 goal-pipeline 后，在 skill_dir 加载完成之后:

if guazi-flow-core/SKILL.md 存在（通过 skill 加载机制）:
    guazi_flow_available = true
    加载 core_skill_dir/SKILL.md（版本检查）
else:
    guazi_flow_available = false
    纯 goal-pipeline 模式运行
```

## 调度规则

### 第一类：管线核心阶段——guazi-flow 可用则 MUST 使用

| 阶段 | guazi-flow 版本 | goal-pipeline 降级版本 |
|------|----------------|-------------|
| plan | guazi-flow-plan | goal-pipeline 通用 plan |
| implement | guazi-flow-implement | goal-pipeline 通用 implement |
| review | guazi-flow-review + goal-pipeline 独立审核（**两者都运行**） | 仅 goal-pipeline 独立审核 |
| complete | guazi-flow-complete | goal-pipeline 通用 complete |
| runtime_smoke | 始终用 goal-pipeline 通用脚本 | — |

### 第二类：条件触发阶段——按 guazi-flow 自身规则决定

| 阶段 | 触发条件 | guazi-flow 版本 |
|------|---------|---------------|
| postmerge | resolved_rule_context.postmerge_policy = required | guazi-flow-postmerge |
| validate | 用户显式开启 或 任务文档 validate=enabled 或 resolved_rule_context.validate_policy = required | guazi-flow-validate |
| e2e | Goal Engineering 阶段用户明确选择 + h5 profile | guazi-flow-e2e |

不可用时跳过，不提供 goal-pipeline 通用替代。

---

## 各阶段集成策略

### plan 阶段

```
if guazi_flow_available:
    → 调 guazi-flow-doctor（环境诊断）
    → 调 guazi-flow-plan（MUST，产出 docs/guazi-flow/<task>/index.md + unit.md）
    → state.json.guazi_flow_task = "docs/guazi-flow/<task>"
    → 输出: "[1/5] plan: ✅ guazi-flow-plan 生成 N 个 unit"
else:
    → goal-pipeline 通用 plan（访谈 + plan 卡片）
    → 输出: "[1/5] plan: ✅ (guazi-flow 不可用)"
```

### implement 阶段

```
if guazi_flow_available:
    → guazi-flow-implement（MUST，profile/contract/write_set 驱动）
    → 写入 evidence/implement.md（guazi-flow schema）
    → 输出: "[2/5] implement: ✅ guazi-flow-implement X files changed"
else:
    → goal-pipeline 通用 implement
    → 输出: "[2/5] implement: ✅ (guazi-flow 不可用)"
```

### review 阶段——统一五步流程

```
implement complete
  ↓
Step 1: verify-review.sh（确定性检查，0 模型调用）
  scope + secret + test + lint
  任一 not_pass → 修复子循环
  全部 pass → 继续
  ↓
Step 2: guazi-flow-review（如果 guazi-flow 可用）
  专业代码审阅：读 index.md/unit.md/Figma/evidence
  检查：契约可追溯、前置状态、E2E 证据、视觉契约
  → issues_gf[]
  不可用 → issues_gf = []
  ↓
Step 3: goal-pipeline 独立审核（始终执行）
  独立 API 模型（跨 provider 优先）
  输入: diff + 验收标准 + 约束
  → issues_goal[]
  ↓
Step 4: 合并结论
  issues = 去重(issues_gf ∪ issues_goal)
  result = 两者都 pass ? pass : not_pass
  ↓
Step 5: 分流
  pass → complete
  not_pass → 修复子循环（使用合并 issues，按决策树处理）

修复子循环决策树见 goal/SKILL.md ——五种场景 + 完整决策树。
```

### complete 阶段

```
if guazi_flow_available:
    → guazi-flow-complete（MUST，完整收口门禁）
    → 输出: "[5/5] complete: ✅ guazi-flow-complete"
else:
    → goal-pipeline 通用 complete
    → 输出: "[5/5] complete: ✅ (guazi-flow 不可用)"
```

## state.json guazi-flow 扩展字段

```json
{
  "guazi_flow_available": true,
  "guazi_flow_task": "docs/guazi-flow/<task>",
  "guazi_flow_stages": {
    "plan": {"used": true},
    "implement": {"used": true},
    "review": {"used": true},
    "complete": {"used": true}
  }
}
```

`guazi_flow_available=false` 时，上述字段全部为空或 false。goal-pipeline 完全独立运行。

## 泛化 review 的桥接

goal-pipeline 的 review 阶段为三步流程（确定性检查 → 独立审核 → 分流）。
桥接层在 Step 1 和 Step 2 之间注入 guazi-flow-review：

```
Step 1: verify-review.sh（确定性检查）
  ↓
[注入] Step 1.5: guazi-flow-review（如果可用）
  专业代码审阅：读 index.md/unit.md/Figma/evidence
  检查：契约可追溯、前置状态、E2E 证据、视觉契约
  → issues_gf[]
  ↓
Step 2: 独立审核（始终执行）
  → issues_goal[]
  ↓
合并: issues = 去重(issues_gf ∪ issues_goal)
  ↓
Step 3: 分流
```

## task_dir 映射

guazi-flow 集成时，task_dir 由 guazi-flow-plan 确定：

```
task_dir = "docs/guazi-flow/<task>"
```

state.json 中 `guazi_flow_task` 字段记录此路径。goal-pipeline 通过此字段定位任务产物。
