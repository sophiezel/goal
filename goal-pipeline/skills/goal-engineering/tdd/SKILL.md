---
name: goal-engineering-tdd
description: implement 子策略 — 红-绿-重构（R3）。由 implement WO skills 软加载。
---

# goal-engineering-tdd

**Stub (v1.3 Part P).** implement 阶段内嵌 TDD 子策略；不改变 gate stage 名。

## 行为（最小）

1. 每个 ticket：先写失败测试（RED）→ 最小实现（GREEN）→ 小步重构（IMPROVE）。
2. 测试须落在 plan `write_set` 内。
3. implement post 仍由 UVO / IQ gate 裁决。

## NEVER

- NEVER 替代 implement post gate 或 UVO
- NEVER 为通过 gate 删除/弱化测试
