---
version: 1
current_stage: implement
profile: h5
profile_detail: react
plan_profile: lite
task_tier: S
---

## 概览

XS 常量文案修改：将按钮文案从"提交"改为"确认提交"。

## 任务目标

- 修改 `src/constants/buttons.ts` 中 SUBMIT_LABEL 常量
- 确保 ts 类型检查通过

## 范围与写集

**In scope**

- `src/constants/buttons.ts`

**Out of scope**

- 后端 API / 其他页面 / 路由变更

## 完整伪代码

```ts
// buttons.ts — 修改 SUBMIT_LABEL
export const SUBMIT_LABEL = "确认提交";
export const CANCEL_LABEL = "取消";
```

## 验收与验证矩阵

| ID | Case | Expected | 执行方式 |
|----|------|----------|----------|
| C01 | SUBMIT_LABEL 值 | "确认提交" | automated |
| C02 | ts 类型检查 | tsc --noEmit pass | automated |
| V01 | 构建通过 | yarn build pass | automated |

## 执行记录

| Stage | Skill | Result |
|-------|-------|--------|
| plan | guazi-flow-plan | pass |

## Goal 契约

### allowed_patterns

- src/constants/buttons.ts


### exclusions

- (derive from index scope / out-of-scope sections)


### stop_conditions

- 需要新增未声明外部依赖时停止
- 修改超出 Allowed Files 范围时停止

