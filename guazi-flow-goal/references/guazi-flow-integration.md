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
       guazi-flow-plan 执行完毕，不做任何干预
    → 硬门禁（机器可验证，替代纯文本 GATE）:
       ```bash
       gate-guazi-flow-stage.sh --task-dir docs/guazi-flow/<task> --stage plan --pre --mode guazi
       # ... 执行 guazi-flow-plan 9 步 ...
       gate-guazi-flow-stage.sh --task-dir docs/guazi-flow/<task> --stage plan --post --mode guazi
       ```
       - `--post` 校验 index.md schema（frontmatter + 核心事实/完整伪代码/验收与验证矩阵/执行记录）
       - 通过则写入 `handoff/plan.json`；失败 exit 1 → blocked(plan_schema_incomplete)
       - 简化 index（如缺完整伪代码）**无法通过** plan gate

    → 交叉验证（产物质量 GATE 通过后，契约融入之前）:
       1. write_set vs Allowed Files:
          从 index.md 提取 write_set 文件列表
          从 Phase 1 Goal 结构提取 Allowed Files
          write_set 文件 ⊆ Allowed Files?
          超出 → 追加 warn 到 index.md（不阻断，guazi-flow-plan 可能有合理扩展）
       2. 验证清单 vs 验收矩阵:
          从 Phase 1 Goal 结构提取 V#1..V#N
          从 index.md 提取验收与验证矩阵
          V# 全部被矩阵覆盖?
          缺口 → 记录为 plan_gap（review 阶段重点检查）
       3. 交叉验证结果写入 state.json.cross_validation
    → 契约融入（后置，纯追加，不修改 index.md 已有内容）:
       读取 Phase 1 Goal 结构: Allowed Files / Out of Scope / Stop Conditions
       追加到 index.md 对应字段的子 section:
         - Allowed Files → write_set 下 ### allowed_patterns
         - Out of Scope  → scope 下 ### exclusions
         - Stop Conditions → contract 下 ### stop_conditions
       冲突检测: write_set 文件不在 allowed_patterns 内 → 追加 warn 备注（不阻断）
       融入失败（如 index.md 不存在）→ 静默跳过，不影响后续阶段
       state.json.guazi_flow_contract_enriched = true/false
    → state.json.guazi_flow_task = "docs/guazi-flow/<task>"
    → 输出: "[1/5] guazi-flow-plan: ✅ 生成 N 个 unit (+ 交叉验证 + 契约融入)"
else:
    → goal-pipeline 通用 plan（访谈 + plan 卡片）
    → 输出: "[1/5] plan: ✅ (guazi-flow 不可用)"
```

### implement 阶段

```
if guazi_flow_available:
    → guazi-flow-implement（MUST，profile/contract/write_set 驱动）
    → diff 合规性审计（guazi-flow-implement 完成后）:
       1. git diff --name-only → 变更文件列表
       2. 对比 write_set: 全部在 write_set 内? 超出 → warn
       3. 对比 Allowed Files: 全部在 Allowed Files 内? 超出 → warn
       4. 检查 Stop Conditions: 新增依赖? 修改接口协议? 命中 → 暂停
       5. 审计结果写入 evidence/implement.md scope_compliance 字段
    → 写入 evidence/implement.md（guazi-flow schema）
    → 输出: "[2/5] guazi-flow-implement: ✅ X files changed"
else:
    → goal-pipeline 通用 implement
    → 输出: "[2/5] implement: ✅ (guazi-flow 不可用)"
```

### review 阶段——增量注入

基础三步审核流程（Step 1/2/3）由 `goal-pipeline/SKILL.md` review 阶段定义。
guazi-flow 可用时，在基础流程中注入两个增量步骤：

**Step 0**: `gate --pre(review)` — implement handoff fresh
**Step 1.5 注入（guazi-flow-review）**:
  专业代码审阅：读 index.md/unit.md/Figma/evidence
  检查：契约可追溯、前置状态、E2E 证据、视觉契约
  → issues_gf[]
  不可用 → issues_gf = []

**Step 4.5 注入（根因分类）**:
  对每个 blocker issue 标注根因:
  - plan_gap: 对照 index.md/unit.md，plan 未覆盖此场景
  - implement_error: plan 有要求但 diff 未满足
  - spec_ambiguity: 需求源本身模糊
  Step 2 前: `assemble-review-packet.sh` → handoff/review-packet.json
Step 5: `merge-review-issues.sh` 合并 issues
Step 6: `gate --post(review)` — merged result=pass 才过
根因分布写入 evidence/review.md root_cause_summary
  修复策略路由:
  - plan_gap > 50% → mini-replan（调 guazi-flow-plan 更新 index.md）
  - implement_error > 50% → 进入修复子循环
  - spec_ambiguity 存在 → blocked + 用户决策

**合并与去重规则**:
  issues = 去重(issues_gf ∪ issues_goal)
  result = 两者都 pass ? pass : not_pass
  格式归一化: issues_goal 包含 file/line_range/evidence 可选字段。
             issues_gf 可能不含这些字段。
  去重规则: 相同 file + 相似 description 视为重复，保留信息更丰富的版本。

修复子循环决策树见 `goal-pipeline/SKILL.md`——五种场景 + 完整决策树。

### complete 阶段

```
if guazi_flow_available:
    → guazi-flow-complete（MUST，完整收口门禁）
    → 输出: "[5/5] guazi-flow-complete: ✅"
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

## task_dir 映射

guazi-flow 集成时，task_dir 由 guazi-flow-plan 确定：

```
task_dir = "docs/guazi-flow/<task>"
```

state.json 中 `guazi_flow_task` 字段记录此路径。goal-pipeline 通过此字段定位任务产物。


## 硬门禁脚本（goal 侧，不修改 guazi-flow-*）

| 脚本 | 用途 |
|------|------|
| `gate-guazi-flow-stage.sh` | plan/implement/review/complete `--pre`/`--post` |
| `assemble-review-packet.sh` | review Step 2 输入包 |
| `merge-review-issues.sh` | 合并 issues_gf + issues_goal |

implement `--post`: diff ⊆ write_set + 执行记录含 guazi-flow-implement。
review `--post`: evidence/review.md frontmatter + Goal annex；merged result=pass 才过。
complete `--post`: index current_stage=complete + review pass+fresh。

Handoff 规范：`references/stage-handoff-contract.md`。
