---
flow:
  version: 1
  current_stage: implement
  profile: h5
  profile_detail: react
---

# Test implement post without plan

## 核心事实

Fixture: implement gate must reject post without plan.json.

## 完整伪代码

```tsx
function Page() { return null; }
```

## 验收与验证矩阵

| Case ID | 验收约束 |
| --- | --- |
| C01 | gate --post implement fails without plan handoff |

## 写集

- `src/pages/test/**`

## 执行记录

- 2026-07-03：goal-implement 完成（fixture only）
