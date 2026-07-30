# CONTEXT — Goal Pipeline 领域语言（v3 SSOT）

> 节点级优化的统一词汇表。所有 skill / gate / 文档引用此处的术语定义，避免「同词异义」。

## 节点（Stage）

| 术语 | 定义 | 输入 | 输出 |
|------|------|------|------|
| **plan** | 需求→契约：产出 `index.md` + `handoff/plan.json` | JIRA / 验收标准 / Figma | `index.md`、`write_set`、`acceptance_matrix_ids` |
| **implement** | 契约→代码：在 `write_set` 内写实现 | `plan.json` + `index.md` | `handoff/implement.json`、`evidence/verification-oracle.json` |
| **quality** | 代码→验证：L0 UVO + L1 smoke + IQ 结构 | `implement.json` | `handoff/quality.json`、`runtime-smoke.md` |
| **review** | 验证→评审：unified issues → fix-input | `quality.json` + review-packet | `evidence/review-fix-input.json` |
| **complete** | 评审→交付：链完整 + delivery 报告 | 全 handoff 链 | `handoff/complete.json`、`delivery-quality.json` |

## 关键概念

| 术语 | 定义 |
|------|------|
| **write_set** | plan 声明的允许改动路径集合；implement 越界即 BLOCK |
| **task_tier** | XS/S/M/L/XL 分级，驱动 SLO 与 Index-Lite/单轨开关 |
| **plan_profile** | `lite`（XS/S 精简 index）或 `full`（M+ 完整 7 段） |
| **review_track** | `single`（仅 goal-review，跳过 guazi-flow-review）或 `dual`（双轨） |
| **info_gain** | 相邻 review 轮 blocker 降幅比 `(prev-cur)/max(prev,1)`；<0.10 连续 2 轮 → `blocked_stagnant` |
| **noop_fix** | 同 `subject_hash` 重跑同一 gate，禁止（防空转） |
| **silent_pass** | gate 未执行其声明检查即放行；Phase A 零容忍 |
| **escape** | 缺陷越过其本应拦截的 gate 到达下游或生产 |
| **leak_rate** | `escapes / completes`，目标 <10% |
| **PQ** | plan-quality 规则（PQ-01..PQ-09） |
| **AM** | acceptance-matrix 棘轮规则（AM-01..AM-10） |
| **UVO** | verification-oracle：统一验证 Oracle（build/test/lint） |
| **Review Packet** | unified 评审上下文（issues_goal + issues_gf + rubric） |

## 失败平面（Failure Planes）

| 平面 | 含义 | 示例 failure code |
|------|------|-------------------|
| **control** | 流程/编排违规 | `uncommitted_write_set`、`plan_gate_missing` |
| **data** | 产物缺失/损坏 | `handoff_missing`、`index_schema_mismatch` |
| **quality** | 质量检查未过 | `review_stagnant`、`review_rounds_exhausted` |
| **efficiency** | 效率退化 | `replay_regression` |

## 质量档位（Quality Tier）

| 档位 | 触发 | e2e | PQ-08 |
|------|------|-----|-------|
| **standard** | 默认 | WARN | warn |
| **strict** | `quality_tier=strict` 或 h5+核心路径 | **BLOCK**（Phase A2，仅 h5） | block |

## 信号开关（Env）

| Env | 作用 | 默认 |
|-----|------|------|
| `GOAL_PLAN_PROFILE` | 强制 lite/full | 自动 |
| `GOAL_REVIEW_TRACK` | 强制 single/dual | dual |
| `GOAL_REVIEW_SINGLE_DEFAULT` | P2 通过后开 XS/S 默认 single | 未设 |
| `GOAL_REVIEW_INFO_GAIN_MIN` | info_gain 阈值 | 0.10 |
| `GOAL_REVIEW_STAGNANT_ROUNDS` | 熔断连续轮数 | 2 |
| `GOAL_SKIP_COMMIT_BEFORE_REVIEW` | 跳过 commit 硬检（本地） | 0 |
