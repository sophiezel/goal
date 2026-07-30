# 声明式契约门禁（术语说明）

本文是 goal 管线里 **PQ-10～PQ-14、IQ-10** 等规则的统一叫法和边界说明。  
**不用 Jira 编号当缺陷类型名**；历史需求只作样本，不写入引擎。

## 指什么

**声明式契约**：当次任务在 `index.md`（及可选 `handoff/decisions.json`）里**自己写清楚**的约定，例如：

- `## API 与工程映射` 表里的 path、`request_key`、必填参数
- 响应 VO / 字段路径、验收矩阵里的可验证项
- grill 冻结的集成口径（写入 decisions + index `## 冻结决策`）

**plan 与实现不一致**（口语里也叫 **plan–implement 语义漂移**）：实现或 plan 正文与上述约定矛盾，或实现未按表落地。

门禁**只校验「当次 plan 写了什么」是否自洽、是否在 `write_set` 内对上表**；不内置具体仓库、框架、域名或 `CSP_*` 常量。

## 规则编号（做什么）

| 编号 | 阶段 | 作用（大白话） |
|------|------|----------------|
| PQ-10 | plan | 同一 API path 在 index 里只能有一种 `request_key`/网关表述；有 API 意图时应有映射表 |
| PQ-11 | plan | 需要 detail/VO 时，plan 里要有响应结构说明 |
| PQ-12 | plan | 存在 `decisions.json` 时，index 须有冻结决策且 hash 一致 |
| PQ-13 | plan | index 内同一业务数字多处矛盾时 warn/block（可配置） |
| PQ-14 | plan | 有 API 契约时，验收矩阵宜含展示/字段类可验证行（渐进收紧） |
| IQ-10 | implement | 映射表每一行与 write_set 内代码绑定（经 [profile adapter](profile-contract-adapters.md)）一致 |
| IQ-11 | implement | 可选：存在 `handoff/integration-manifest.json` 时，`integration-contract-check.sh` 校验 `cross_app` |

形态类 PQ/IQ（写集、验收表、UVO 等）见 `plan-quality-rules.json` 与 `dual-track-contract.md`。

## 不指什么

- **不是**某张 Jira 或「CTB 类」内部类型
- **不是** UI 像素、文案、骨架屏长什么样（靠 review / 验收矩阵 + 人工）
- **不是** `delivery-quality.json` 的判定依据（那是 complete 阶段**管线快照**，见 [Pipeline I/O Port Spec](../../docs/architecture/pipeline-io-port-spec.md)）

## 相关产物

- 表解析与 IQ-10：`contract_parser.py`、`contract-conformance-check.py`
- 冻结决策：`decisions-handoff-protocol.md`（guazi-flow-goal）
- 多仓集成（可选）：`multi-goal-orchestration.md`、`integration-manifest.schema.json`
