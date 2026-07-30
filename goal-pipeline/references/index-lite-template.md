---
version: 1
current_stage: plan
profile: h5
profile_detail: react
plan_profile: lite
task_tier: S
---

## 概览

<!-- 1–2 句：改什么、为什么 -->

## 任务目标

<!-- 可量化交付物，1–3 条 bullet -->

## 范围与写集

**In scope**

- `src/path/to/file.tsx`

**Out of scope**

- 后端 API / 其他页面

## 完整伪代码

```tsx
// 关键逻辑骨架（≥80 字即可）
function TargetComponent() {
  const [state, setState] = useState();
  return <div>{/* ... */}</div>;
}
```

## 验收与验证矩阵

| ID | Case | Expected | 执行方式 |
|----|------|----------|----------|
| C01 | 主路径 | 行为符合预期 | manual |
| C02 | 边界 | 空态/错误态 | automated |
| V01 | 构建 | `yarn build:beta` pass | automated |

## 执行记录

| Stage | Skill | Result |
|-------|-------|--------|
| plan | guazi-flow-plan | pass |
