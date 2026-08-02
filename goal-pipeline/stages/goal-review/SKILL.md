---
name: goal-review
description: goal-pipeline review 阶段。强制 unified 独立 LLM + 测试充分性 rubric。Use with /goal-pipeline (default track).
---

# goal-review

**SSOT** for review stage. guazi-flow-review is optional via `pipeline_track=compatibility|guazi` appendix.

## 必读

- `goal-pipeline/references/tiered-adjudication.md`（L2 强制独立 LLM）
- `goal-pipeline/references/separation-strategies.md`

## goal_patches

1. **review_unified 强制**：MUST `run-independent-review.sh` cross-provider
2. **测试充分性 rubric**：V# 覆盖 vs diff 变更映射
3. **fix-input 契约**：修复前 MUST Read `evidence/review-fix-input.json`
4. **单轨模式（v3 §8.2）**：`review_track=single` 时本 skill 是 review 阶段唯一加载的 skill（不加载 `guazi-flow-review/SKILL.md`）。rubric 经 `assemble-review-packet.sh` 嵌入 `review-packet.json`，`goal-run-review-chain.sh` unified 分支直接产出 issues。`review_track=dual`（默认 guazi 兼容轨）时仍可按上游双轨执行。路由见 [`review_track.py`](../../scripts/review_track.py)。

## guazi adapter（可选）

`pipeline_track=compatibility|guazi` 且 `review_track=dual` 时可加载 `guazi-flow-review` 作为 Step 1.5 注入；默认 goal 轨 **不** 加载。

## Stage Exit

```bash
refresh-handoffs-after-index.sh --task-dir <task>
gate-goal-stage.sh --stage review --pre
goal-run-review-chain.sh --task-dir <task>
gate-goal-stage.sh --stage review --post
```

## NEVER

- NEVER 自填 review-unified.json
- NEVER 询问用户是否继续 review
