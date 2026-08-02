---
name: goal-engineering-handoff
description: prototype → implement 交接（R2→R3）。由 engineering_pack 含 handoff 软加载。
---

# goal-engineering-handoff

**Stub (v1.3 Part P).** prototype 满意后，将设计决策与资产链接写入 plan handoff 扩展。

## 行为（最小）

1. 读取 prototype 资产路径与已验证边界行为。
2. 写入 `handoff/plan.json` 扩展：`prototype_assets[]`、`design_decisions[]`（schema 见 v1.3 原型文档）。
3. 交还 `goal-plan` / implement 主流程。

## NEVER

- NEVER 手写 gate 终态 handoff（kernel post 仍 authoritative）
- NEVER 跳过 write_set 声明
