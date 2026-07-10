---
name: goal-review
description: 进化轨 review 阶段。Fork 自 guazi-flow-review，强制 unified 独立 LLM + 测试充分性 rubric。
---

# goal-review

Fork-and-Own 自 `guazi-flow-review`，与 goal-pipeline 独立审核链合并。

## 必读

- `goal-pipeline/references/tiered-adjudication.md`（L2 强制独立 LLM）
- 上游 `guazi-flow-review/SKILL.md`

## goal_patches

1. **review_unified 强制**：MUST `run-independent-review.sh` cross-provider
2. **测试充分性 rubric**：V# 覆盖 vs diff 变更映射
3. **fix-input 契约**：修复前 MUST Read `evidence/review-fix-input.json`

## Stage Exit

```bash
refresh-handoffs-after-index.sh --task-dir <task>
gate-guazi-flow-stage.sh --stage review --pre
goal-run-review-chain.sh --task-dir <task>
gate-guazi-flow-stage.sh --stage review --post
```

## NEVER

- NEVER 自填 review-unified.json
- NEVER 询问用户是否继续 review
