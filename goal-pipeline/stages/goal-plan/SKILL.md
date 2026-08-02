---
name: goal-plan
description: goal-pipeline plan 阶段。PQ 语义门禁、契约 enrich、Index-Lite。Use with /goal-pipeline (default track).
---

# goal-plan

**SSOT** for plan stage in goal-pipeline. Local skill is authoritative; guazi-flow-plan is optional via `pipeline_track=compatibility|guazi` (see appendix in root `goal-pipeline/SKILL.md`).

## 必读

- `goal-pipeline/references/dual-track-contract.md`
- `goal-pipeline/references/plan-quality-rules.json`
- `goal-pipeline/references/plan-before-code.md`

## goal_patches（相对纯 guazi 路径）

1. **PQ 语义门禁**：产出 index.md 后 MUST 跑 `plan-quality-gate.py`；block 则按 `evidence/plan-gate-fix-input.json` 修复
2. **契约 enrich**：Allowed Files / Stop Conditions 写入 index.md（桥接层规则）
3. **strict tier**：伪代码 ≥500 字；验收矩阵无模糊措辞
4. **Index-Lite（XS/S）**：`plan_profile: lite` 时按 [`plan-index-rules-lite.json`](../../references/goal-artifact-schema/plan-index-rules-lite.json) 校验（6 段、伪代码 ≥80 chars、PQ-08 warn）；路由由 [`resolve_plan_index_rules.py`](../../scripts/resolve_plan_index_rules.py) 决定；PQ-01/02/05/07 不降级。详见 [`index-lite-protocol.md`](../../references/index-lite-protocol.md)
5. **goal_lite（纯 goal XS/S）**：`plan_profile: goal_lite` 时不强制 guazi index 六段 / fe-argus；验收来自 to-specs 或 prototype handoff（见 profile `task_docs_root: docs/goal`）

## guazi adapter（可选）

`pipeline_track=compatibility|guazi` 时可对照上游 `guazi-flow-plan/SKILL.md` 作为附录；**不**作为默认 SSOT。

## Stage Exit

```bash
gate-goal-stage.sh --stage plan --pre
# 执行 plan 主流程（本 skill）
python3 plan-quality-gate.py --task-dir <task>
gate-goal-stage.sh --stage plan --post
validate-pipeline-chain.sh --task-dir <task>
```

## NEVER

- NEVER 跳过 PQ 门禁（goal_lite 除外：index 硬校验由 gate 放宽，PQ 仍按 profile）
