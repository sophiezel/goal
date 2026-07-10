# goal-core（minimal fork）

自 `guazi-flow-core` 摘取 goal-pipeline 所需契约片段。完整 core 仍通过 skill 加载机制只读引用。

## 引用字段

- `failure_code` 枚举（plan_schema_incomplete, implement_gate_pending, quality_gate_failed）
- `resolved_rule_context.validate_policy` / `e2e_policy`
- handoff provenance 规则

## 同步

见 `fork-sync-policy.md`。本目录不替代上游 guazi-flow-core SKILL。
