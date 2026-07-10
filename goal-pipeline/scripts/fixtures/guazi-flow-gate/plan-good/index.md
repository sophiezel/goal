---
version: 1
current_stage: implement
profile: h5
profile_detail: react
---

## 概览

CTB-43532 B2C discrepancy video audit — list and detail UI changes.

## 任务目标

Remove audit log column from list; show submit time on detail page.

## 范围与非目标

In scope: DiscrepancyVideoAudit pages and services. Out of scope: backend API changes.

## 核心事实

Task CTB-43532: B2C discrepancy video audit list and detail pages.

## 完整伪代码

```tsx
// ListPage: fetch list, city filter, evaluator depends on cityId
function ListPage() {
  const [cityId, setCityId] = useState<number>();
  const evaluators = useEvaluators(cityId);
  return <ProTable columns={columnsWithoutAuditLog} />;
}
```

```tsx
// DetailPage: show submitTime instead of shelfTime
function DetailPage() {
  return <Descriptions items={[{ label: '提交时间', value: submitTime }]} />;
}
```

## 验收与验证矩阵

| ID | Case | Expected |
|----|------|----------|
| C01 | List columns | No audit log column |
| C02 | Detail label | 提交时间 shown |
| V01 | Evaluator filter | Depends on city id |
| V02 | Build | `yarn build:beta` pass |

## 执行记录

| Stage | Skill | Result |
|-------|-------|--------|
| plan | guazi-flow-plan | pass |

## write_set

- `routes.ts`
- `src/pages/DiscrepancyVideoAudit/`
- `src/services/discrepancyVideoAudit/`
