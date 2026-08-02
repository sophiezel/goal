---
version: 1
current_stage: plan
profile: h5
plan_profile: full
contract_semantic: required
---

## 概览

Synthetic PQ-10 negative fixture.

## 任务目标

API host contradiction in plan.

## 核心事实

Uses CSP_DELIVERY in prose and CSP_TASK in mapping for same path.

## 完整伪代码

```ts
// detail fetch
await createRequest({ key: 'CSP_DELIVERY', uri: '/external/demo/detail' });
```

## 验收与验证矩阵

| ID | Case | verify_command |
|----|------|----------------|
| V01 | detail | yarn test |

## API 与工程映射

| 方法 | path | request_key | 必填参数 |
|------|------|-------------|----------|
| GET | /external/demo/detail | CSP_TASK | source |

Body also says call `CSP_DELIVERY` for `/external/demo/detail`.

## write_set

- `src/services/demo.ts`
