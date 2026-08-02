---
name: goal-engineering-prototype
description: Phase 1 prototype — UI/logic 可运行资产（R1–R2）。由 engineering_pack=prototype 软加载。
---

# goal-engineering-prototype

**Stub (v1.3 Part P).** 在 plan 阶段生成可运行 prototype（UI 或 logic 分支）；硬 gate 仍为 plan post。

## 行为（最小）

1. grill 收敛后，按 `workflow_profile=prototype_path` 生成终端可运行 prototype（A/B/C 变体可选）。
2. 跑 2–3 个边界用例验证行为；结论写入 `evidence/prototype-*` 或 profile 指定路径。
3. 满意后交还 `goal-engineering-handoff` 写入 `handoff/plan.json` 扩展字段。

## NEVER

- NEVER 替代 plan post gate
- NEVER 写 `src/**`（prototype 在 evidence / sandbox 路径）
