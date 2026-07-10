---
version: 1
current_stage: implement
profile: h5
profile_detail: react
---

## 概览

SCC-41328 style task — write_set under ## 写集 alias.

## 任务目标

Verify gate extracts write_set from ## 写集 section.

## 范围与非目标

In scope: one page. Out of scope: backend.

## 核心事实

Single page change.

## 完整伪代码

```tsx
// ListPage: fetch audit list with city filter; evaluator dropdown depends on cityId
function ListPage() {
  const [cityId, setCityId] = useState<number>();
  const evaluators = useEvaluators(cityId);
  const columns = useMemo(() => buildColumns({ showAuditLog: false }), []);
  return (
    <ProTable
      columns={columns}
      request={fetchList}
      toolBarRender={() => [<CitySelect onChange={setCityId} />, <EvaluatorSelect cityId={cityId} />]}
    />
  );
}
```

```tsx
// DetailPage: submitTime label, eight-direction video checklist
function DetailPage() {
  const { data } = useDetail(id);
  return (
    <Descriptions items={[{ label: '提交时间', value: data.submitTime }]} />
  );
}
```

## 验收与验证矩阵

| ID | Case | Expected |
|----|------|----------|
| C01 | Renders | Page loads |
| V02 | Build | `yarn build:beta` pass |

## 执行记录

| Stage | Skill | Result |
|-------|-------|--------|
| plan | guazi-flow-plan | pass |

## 写集

- `src/pages/Foo/`
- `src/services/foo/`
