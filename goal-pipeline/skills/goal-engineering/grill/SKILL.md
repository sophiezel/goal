---
name: goal-engineering-grill
description: Phase 1 简体 grill — 一问一答澄清需求（R1）。由 profile engineering_pack 软加载；不替代 PQ/plan gate。
---

# goal-engineering-grill

**Stub (v1.2 Part K).** 在 plan 阶段增强 R1 访谈；硬门禁仍为 `gate-goal-stage.sh --stage plan` 与 PQ。

## 行为（最小）

1. 每次只问 **一个** 澄清问题；等待人类回答后再继续。
2. 将结论写入 `docs/goal/<task>/` 下 goal brief（`index.md` 或 profile `task_docs_root` 指定路径），**不** 写 `src/**`。
3. 访谈结束或信息足够时，交还 `goal-plan` 主流程。

## NEVER

- NEVER 替代 plan post gate 或跳过 PQ
- NEVER 依赖英文 marketplace grill skill 为 SSOT
- NEVER 默认写入 `docs/guazi-flow/`（guazi 适配轨须 profile 显式 `task_docs_root: docs/guazi-flow`）
