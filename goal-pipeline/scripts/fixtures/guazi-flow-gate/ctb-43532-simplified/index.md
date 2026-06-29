---
flow:
  version: 1
  current_stage: implement
  profile: h5
  profile_detail: react
---

# CTB-43532 B2C 车况视频不符人员审核

## 概览

- **任务目标**：在 tower 控制台从零实现「不符视频抽检审核」列表与「车况视频审核」详情，接入 CWiki 接口，交互对齐本地原型。
- **约束**：不参照 `CTB-43532` 分支历史实现；评估师接口以 CWiki 为准；未知 `auditStatus` 展示 `auditStatusDesc`。
- **成功标准**：列表筛选/导出/操作列；详情 8 方位 × 3 checklist 审核与查看；提交后回列表并带 `auditStatus=audited`。

## 核心事实

| 来源 | 摘要 |
| --- | --- |
| Jira CTB-43532 | B2C 车况视频不符人员审核 |
| 需求 Wiki pageId=679798669 | 列表 + 详情 + 导出；用户覆盖去掉审核日志列 |
| 接口 Wiki pageId=685489224 | list/detail/submit/export + 城市/评估师下拉 |
| 原型 | 左右视频与 checklist 联动；详情「提交时间」 |

## 写集

- `routes.ts`
- `src/pages/DiscrepancyVideoAudit/**`
- `src/services/discrepancyVideoAudit/index.ts`
- `guazi-flow.config.json`

## 验收矩阵

| ID | 场景 | 预期 |
| --- | --- | --- |
| C01 | 列表列 | 无「审核日志」列 |
| C02 | 操作列 | `unaudited`→审核；`audited`→查看；未知状态展示 `auditStatusDesc` |
| C03 | 评估师筛选 | 依赖 `cityId`；未选城市时 disabled |
| C04 | 详情顶部 | 展示提交时间 `submitTime` |
| C05 | checklist | 不合格且 `availableItems` 存在时展示；`option=true` 默认勾选 |
| C06 | 提交 | 全部标记后可提交；成功后回列表 `auditStatus=audited` |

## Goal 契约

### allowed_patterns

- 新增 B2C 视频审核列表/详情/服务/路由

### exclusions

- 不实现审核日志列/弹窗
- 不参照 CTB-43532 分支代码

### stop_conditions

- 接口路径与 CWiki 不一致且无法确认

## 执行记录

| 日期 | 阶段 | 动作 | 结果 |
| --- | --- | --- | --- |
| 2026-06-29 | plan | 用户确认 Q1-B 从零重写 | 通过 |
| 2026-06-29 | implement | 新增服务/列表/详情/路由/样式 | 进行中 |
