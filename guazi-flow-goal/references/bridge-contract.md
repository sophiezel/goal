# Bridge Contract（集成桥接层契约）

本文件是 goal-pipeline 内核与 guazi-flow-* 系列之间的桥接契约。goal-pipeline 管线独立运行于所有平台，guazi-flow-* 在可用时按此契约在各阶段被调用。

## NEVER

- **NEVER 在桥接层定义管线逻辑**——管线逻辑（5 阶段、修复子循环、budget）由 goal-pipeline 独占，桥接层只定义映射规则
- **NEVER 修改 goal-pipeline 的 state.json 基础字段**——guazi-flow 扩展字段（guazi_flow_*）只能追加，不覆盖 pipeline/platform/review_config 等管线字段
- **NEVER 在桥接层引入新的持久化路径**——所有数据通过 `~/.goal-state/` 统一管理，不在项目中创建额外目录
- **NEVER 让 guazi-flow-review 替代 goal-pipeline 独立审核**——两者都运行，issues 合并去重，guazi-flow-review 仅作为 Step 1.5 注入
- **NEVER 让契约融入步骤阻断 guazi-flow-plan 或后续阶段的执行**——融入失败时静默跳过，不影响 implement/review/complete

## 核心桥接规则

1. **review 注入点**：Step 1.5（在 Step 1 确定性检查之后、Step 2 独立审核之前）。注入的 issues 合并到 Step 2 结果中。
2. **task_dir 映射**：guazi-flow 集成时 `task_dir = docs/guazi-flow/<task>/`，goal-pipeline 通用模式时 `task_dir = <项目根>/`。
3. **扩展字段**：`guazi_flow_task` / `guazi_flow_profile` / `guazi_flow_stages`——仅在使用 guazi-flow 集成时存在，不可用时全部为空。
4. **降级规则**：guazi-flow 不可用时，所有扩展字段置空，管线行为与纯 goal-pipeline 完全一致。
5. **契约融入规则**：plan 阶段 guazi-flow-plan 产出后，桥接层将 Phase 1 Goal 结构的 Allowed Files / Out of Scope / Stop Conditions 追加到 index.md 的 write_set / scope / contract 子 section 中。纯追加，不修改 index.md 已有内容。后向流程（implement/review/complete）通过读取 index.md 自然消费这些增强字段。
6. **review issue 格式**：goal-pipeline 独立审核输出的 issue 包含 file/line_range/evidence 可选字段（借鉴 Orca diff 级标注）。guazi-flow-review 的 issue 格式不受此约束。合并时保留信息更丰富的版本。

## goal-pipeline ↔ guazi-flow 关系

```
goal-pipeline（通用管线）          guazi-flow-* 系列（可选增强）
       │                              │
       └──────── 本层桥接 ─────────────┘
                    
  goal-pipeline 始终独立运行。guazi-flow-* 可用时:
    plan:      替代 goal-pipeline 通用 plan（结构化文档）
    implement: 替代 goal-pipeline 通用 implement（profile/contract 驱动）
    review:    增强 goal-pipeline review（补充专业审核）
    complete:  增强 goal-pipeline complete（补充收口检查）
```

## 集成规则

**MANDATORY**: 使用桥接层前必须读取 `references/guazi-flow-integration.md`（完整调度规则和条件触发逻辑）
**MANDATORY**: 修改 state.json 前必须读取 `references/guazi-flow-state-schema.md`（guazi-flow 扩展字段定义和写入边界）

## guazi-flow 扩展字段

Goal 状态文件 `~/.goal-state/projects/<pid>/<branch>/<task>/state.json`
中 guazi-flow 相关扩展字段：

```json
{
  "guazi_flow_available": true,
  "guazi_flow_task": "docs/guazi-flow/<task>",
  "guazi_flow_profile": "h5",
  "guazi_flow_stages": {
    "plan": {"used": true},
    "implement": {"used": true},
    "review": {"used": true},
    "complete": {"used": true}
  }
}
```

guazi-flow 不可用时上述字段全部为空，goal-pipeline 完全独立运行。

## 边缘场景

| 场景 | 行为 |
|------|------|
| goal-pipeline 未加载 | 拒绝执行，提示先加载 goal-pipeline |
| 版本不兼容（bridge 与 core） | 警告 + 降级为纯 goal-pipeline |
| state.json 扩展字段缺失 | 视为 guazi_flow_available=false，纯管线模式 |
| guazi-flow-review 与独立审核 issue 冲突 | 以独立审核为准，guazi-flow issue 标记为 `discarded` |
| 契约融入失败（如 index.md 不存在） | 静默跳过，不影响后续阶段，state.json 记录 `guazi_flow_contract_enriched=false` |
| 桥接层加载失败 | goal-pipeline 正常运行，扩展字段为空 |


## Review 统计口径（v2.2）

- `handoff/review.json` 扩展字段（向后兼容）：
  - `gf_execution_mode`: `independent_dual_channel`
  - `gf_skill_attested`: bool — `review-run.json` / `review-fix-input.json` provenance
  - `review_run_id`: 与 `evidence/review-run.json` 对齐
- `issues_gf_count` MUST 来自 `review-gf.json` issues 数组长度，禁止数 markdown 表格行
- `review-run.channels` 记录 `["goal","guazi-flow-review"]` 当 dual 模式启用
