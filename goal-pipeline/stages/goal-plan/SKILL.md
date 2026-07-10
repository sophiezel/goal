---
name: goal-plan
description: 进化轨 plan 阶段。Fork 自 guazi-flow-plan，叠加 PQ 语义门禁与契约 enrich。Use with /goal-pipeline when pipeline_track=evolution.
---

# goal-plan

Fork-and-Own 自 `guazi-flow-plan`。上游只读；本 skill 在 goal 仓库内可优化。

## 必读

- `goal-pipeline/references/dual-track-contract.md`
- `goal-pipeline/references/plan-quality-rules.json`
- 上游 `guazi-flow-plan/SKILL.md`（执行主流程）

## goal_patches（相对上游）

1. **PQ 语义门禁**：产出 index.md 后 MUST 跑 `plan-quality-gate.py`；block 则按 `evidence/plan-gate-fix-input.json` 修复
2. **契约 enrich**：Allowed Files / Stop Conditions 写入 index.md（桥接层规则）
3. **strict tier**：伪代码 ≥500 字；验收矩阵无模糊措辞

## Stage Exit

```bash
gate-guazi-flow-stage.sh --stage plan --pre
# 执行 guazi-flow-plan 等价 9 步（本 skill 可优化步骤顺序）
python3 plan-quality-gate.py --task-dir <task>
gate-guazi-flow-stage.sh --stage plan --post
validate-pipeline-chain.sh --task-dir <task>
```

## NEVER

- NEVER 跳过 PQ 门禁
- NEVER 修改上游 guazi-flow-plan 文件
