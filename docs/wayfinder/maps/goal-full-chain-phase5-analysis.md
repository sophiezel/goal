# Wayfinder 本地镜像：Goal 全链路质量与效率 — 系统分析与优化规格（Phase-5）

**Status:** **open（chart 2026-08-01）**  
**GitHub 主副本（地图）：** [Wayfinder: Goal 全链路质量与效率 — 系统分析与优化规格（Phase-5）](https://github.com/sophiezel/goal/issues/36)

**前置地图（已关闭）：**

- [Wayfinder: Goal 交付质量与全链路效率优化（Phase-3）](https://github.com/sophiezel/goal/issues/1) — [PHASE-3-CLOSURE](../PHASE-3-CLOSURE.md)
- [Wayfinder: guazi-flow-goal 全链路硬化（Phase-4）](https://github.com/sophiezel/goal/issues/24) — [ctb-44243-phase4-pipeline-hardening.md](ctb-44243-phase4-pipeline-hardening.md) · [optimization-spec-outline-v1.1.md](../research/optimization-spec-outline-v1.1.md)

**索引：** [goal-delivery-quality-optimization.md](../goal-delivery-quality-optimization.md) · P2 [tech-debt-p2.md](../tech-debt-p2.md)

## Destination（摘要）

系统级全链路分析 + **优化设计（决策/规格）**，覆盖三条链：

1. **guazi-flow-goal** — guazi-flow-* 依赖、implement 后自修复环 + 独立 review；节点 I/O 与上下游贯通（基线 [pipeline-node-catalog.md](../research/pipeline-node-catalog.md)）。
2. **goal-pipeline** — 通用目标管线；对照 Wayfinder / grill / to-specs / to-ticket / implement / review 等外部高保真 skill 模式。**独立审核模型（HITL 2026-08-01）：** 与 guazi-flow-goal 环工程 **parity** — 接入 `goal-review`、unified kernel（`goal-run-review-chain` / `run-independent-review`）、与 implement **分离的审核模型**；I/O（packet、review-run、review-unified、fix-input）；review 环质量/效率（single/dual track、latency、`invocation_count`、degraded channel）。
3. **Generic services** — handoff、gates、timing、review kernel、postmerge、doctor、schemas 等横切能力。

## 子票

| 标题 | 类型 | URL | Frontier |
| --- | --- | --- | --- |
| Research: guazi-flow-goal 节点图 I/O 契约审计（上下游贯通） | research | https://github.com/sophiezel/goal/issues/37 | **open** — catalog delta + 断点表 |
| Research: goal-pipeline 阶段图 vs Wayfinder/Matt Pocock 等外部 skill 模式差距 | research | https://github.com/sophiezel/goal/issues/38 | **open** — 差距矩阵 + Phase-5 规格建议 |
| Research: goal 仓跨平面 generic services 清单与边界 | research | https://github.com/sophiezel/goal/issues/39 | **open** — inventory + ownership |
| Grilling: Phase-5 Destination — 优化方案须裁决 vs 可推迟 | grilling | https://github.com/sophiezel/goal/issues/40 | **open** — ratify 决策面 vs P2/实现图 |
| Research: 统一 SLO / 质量模型（v1.1 扩展输入） | research | https://github.com/sophiezel/goal/issues/41 | **open** — blocked by #37–#39 |

## 并发与串行（路由）

| 票 | 可与谁并行 | 必须等待 |
| --- | --- | --- |
| [#37](https://github.com/sophiezel/goal/issues/37) I/O 审计 | [#38](https://github.com/sophiezel/goal/issues/38)、[#39](https://github.com/sophiezel/goal/issues/39)、[#40](https://github.com/sophiezel/goal/issues/40) | — |
| [#38](https://github.com/sophiezel/goal/issues/38) 外部模式差距 | #37、#39、#40 | — |
| [#39](https://github.com/sophiezel/goal/issues/39) generic services | #37、#38、#40 | — |
| [#40](https://github.com/sophiezel/goal/issues/40) grilling | #37–#39（建议早开以裁剪研究范围） | — |
| [#41](https://github.com/sophiezel/goal/issues/41) 统一 SLO/质量模型 | — | **#37、#38、#39**（GitHub blocked-by）；**应阅读** #40 ratification |

**建议认领顺序：** #40 与 #37–#39 并行启动 → #41 在三份 research 闭合后。

## Decisions so far（本地镜像）

- **Scope ratification (2026-08-01)** — [#36 Scope ratification 评论](https://github.com/sophiezel/goal/issues/36#issuecomment-5151795281)：Phase-5 须覆盖 **goal-pipeline 独立审核模型**（非仅 guazi-flow-review 路径）；子票 [#37](https://github.com/sophiezel/goal/issues/37)、[#38](https://github.com/sophiezel/goal/issues/38)、[#41](https://github.com/sophiezel/goal/issues/41) Question 已对齐。

## Not yet specified（Fog）

- optimization-spec 升格形态（v1.2 vs Part J append）。
- goal-pipeline 是否内置 wayfinder/grill 阶段钩子。
- SLO-Q-01 数值与 `sla_breach` / timing substep 默认接线（P2 候选）。
- guazi-flow-* SKILL 正文（仓外）审计深度边界。
- eval 覆盖 vs spec 缺口的分工。
- 纯 **goal-pipeline**（无 guazi index）默认 **review_track** 与 cross-provider 策略。

## Out of scope

- 业务仓单票功能交付；Phase-4 [#30](https://github.com/sophiezel/goal/issues/30) 夹具除非新回归；本图会话内 bulk 实现。

## 规格交叉引用

- [optimization-spec-outline-v1.md](../research/optimization-spec-outline-v1.md) · [optimization-spec-outline-v1.1.md](../research/optimization-spec-outline-v1.1.md)
- [pipeline-node-catalog.md](../research/pipeline-node-catalog.md) · [review-chain-bottlenecks.md](../research/review-chain-bottlenecks.md)
- [guazi-flow-goal/SKILL.md](../../../guazi-flow-goal/SKILL.md) · [goal-pipeline/SKILL.md](../../../goal-pipeline/SKILL.md)
