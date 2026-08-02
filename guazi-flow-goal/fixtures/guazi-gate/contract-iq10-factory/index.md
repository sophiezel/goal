---
version: 1
current_stage: implement
profile: h5
plan_profile: full
---

## 概览

Synthetic IQ-10 positive fixture.

## 任务目标

Service matches API table.

## 核心事实

Fixture only.

## 完整伪代码

```ts
export function fetchDetail() {
  return createRequest({ key: 'CSP_GOOD', uri: '/external/demo/detail', source: 100 });
}
```

## 验收与验证矩阵

| ID | Case | verify_command |
|----|------|----------------|
| V01 | detail | yarn test |

## API 与工程映射

| 方法 | path | request_key | 必填参数 |
|------|------|-------------|----------|
| GET | /external/demo/detail | CSP_FACTORY | source |

## write_set

- `src/services/demo.ts`

## 执行记录

| Stage | Skill | Result |
|-------|-------|--------|
| plan | guazi-flow-plan | pass |
