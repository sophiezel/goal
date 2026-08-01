# Wayfinder 本地镜像：Goal 全链路质量与效率 — 系统分析与优化规格（Phase-5）

**Status:** **closed（2026-08-02）** — [PHASE-5-CLOSURE](../PHASE-5-CLOSURE.md)  
**GitHub 主副本（地图）：** [Wayfinder: Goal 全链路质量与效率 — 系统分析与优化规格（Phase-5）](https://github.com/sophiezel/goal/issues/36)（**closed**）  
**Frontier:** none — 实现 → 新地图；规格 SSOT [optimization-spec-outline-v1.2.md](../research/optimization-spec-outline-v1.2.md)

**前置地图（已关闭）：**

- [Wayfinder: Goal 交付质量与全链路效率优化（Phase-3）](https://github.com/sophiezel/goal/issues/1) — [PHASE-3-CLOSURE](../PHASE-3-CLOSURE.md)
- [Wayfinder: guazi-flow-goal 全链路硬化（Phase-4）](https://github.com/sophiezel/goal/issues/24) — [ctb-44243-phase4-pipeline-hardening.md](ctb-44243-phase4-pipeline-hardening.md) · [optimization-spec-outline-v1.1.md](../research/optimization-spec-outline-v1.1.md)

**索引：** [goal-delivery-quality-optimization.md](../goal-delivery-quality-optimization.md) · P2 [tech-debt-p2.md](../tech-debt-p2.md)

## Destination（摘要）

系统级分析 + **goal-pipeline 下一代优化规格（决策/规格，可破坏性）**；**guazi-flow-goal 为独立管线**，本图不以 guazi 历史编排约束 goal-pipeline 设计。

1. **goal-pipeline（主轨）** — 高保真需求、高效率执行、高质量交付、漏出趋 0（W1/W2 + quality plane）。**Stage 图为 profile 可配置外壳**；normative = R1–R4（[v1.1 Part F](../research/optimization-spec-outline-v1.1.md)）+ gate + **独立审核公共服务**（轴 3 **B**：I/O schema + `goal-run-review-chain` 编排 SSOT）。**轴 2：** 外置 `/wayfinder` 制图；Phase 1/profile 软加载 **Goal 内嵌简体 Matt 衍生 Skill Pack**（grill、to-specs 等）；五阶段名非架构常量。**允许 breaking change**，不为 guazi 双轨保留 goal-pipeline 兼容层。
2. **guazi-flow-goal（独立管线）** — 业务仓 + guazi-flow-*；[#37](../research/guazi-flow-goal-node-io-audit-phase5.md) 为现状快照；Phase-5 **不**承担改造 guazi 以匹配新 goal-pipeline。可选接入共享 review 契约（wrapper profile）。
3. **Generic services** — handoff、gates、timing、**独立审核公共服务**（一等公民）；外部流程可 adapter 接入；`goal-review` / `guazi-flow-review` = wrapper profiles。

**Grilling SSOT：** [#40 已关闭](https://github.com/sophiezel/goal/issues/40) — [final ratification（B1–B9）](https://github.com/sophiezel/goal/issues/40#issuecomment-5152145886)。

## 子票

| 标题 | 类型 | URL | Frontier |
| --- | --- | --- | --- |
| Research: guazi-flow-goal 节点图 I/O 契约审计（上下游贯通） | research | https://github.com/sophiezel/goal/issues/37 | **closed** — [guazi-flow-goal-node-io-audit-phase5.md](../research/guazi-flow-goal-node-io-audit-phase5.md) |
| Research: goal-pipeline 阶段图 vs Wayfinder/Matt Pocock 等外部 skill 模式差距 | research | https://github.com/sophiezel/goal/issues/38 | **closed** — [goal-pipeline-external-patterns-gap-phase5.md](../research/goal-pipeline-external-patterns-gap-phase5.md) |
| Research: goal 仓跨平面 generic services 清单与边界 | research | https://github.com/sophiezel/goal/issues/39 | **closed** — [generic-services-inventory-phase5.md](../research/generic-services-inventory-phase5.md) |
| [Grilling: Phase-5 Destination — 优化方案须裁决 vs 可推迟](https://github.com/sophiezel/goal/issues/40) | grilling | https://github.com/sophiezel/goal/issues/40 | **closed** — [final ratification](https://github.com/sophiezel/goal/issues/40#issuecomment-5152145886)（B+C SSOT、Skill Pack、review B、管线独立、B1–B9） |
| Research: 统一 SLO / 质量模型（v1.1 扩展输入） | research | https://github.com/sophiezel/goal/issues/41 | **closed** — [unified-slo-quality-model-phase5.md](../research/unified-slo-quality-model-phase5.md) |
| Task: optimization-spec v1.2 / Part J 文档收口（Phase-5 研究合入） | task | https://github.com/sophiezel/goal/issues/42 | **closed** — [optimization-spec-outline-v1.2.md](../research/optimization-spec-outline-v1.2.md)（Part J–N + B1–B9 + 管线独立） |

## 并发与串行（路由）

| 票 | 可与谁并行 | 必须等待 |
| --- | --- | --- |
| [#37](https://github.com/sophiezel/goal/issues/37) I/O 审计 — **closed** | [#38](https://github.com/sophiezel/goal/issues/38)、[#39](https://github.com/sophiezel/goal/issues/39)、[#40](https://github.com/sophiezel/goal/issues/40) | — |
| [#38](https://github.com/sophiezel/goal/issues/38) 外部模式差距 — **closed** | #39 | — |
| [#39](https://github.com/sophiezel/goal/issues/39) generic services | #37、#38、#40 | — |
| [#40](https://github.com/sophiezel/goal/issues/40) grilling — **closed** | — | — |
| [#41](https://github.com/sophiezel/goal/issues/41) 统一 SLO/质量模型 — **closed** | — | **#37、#38、#39**（GitHub blocked-by）；**应阅读** #40 ratification |
| [#42](https://github.com/sophiezel/goal/issues/42) spec v1.2 / Part J 收口 | — | **#37–#41** + [#40 ratification](https://github.com/sophiezel/goal/issues/40#issuecomment-5152145886) |

**建议认领顺序：** **[#42](https://github.com/sophiezel/goal/issues/42)**（spec 文档收口；研究波 #37–#41 已闭合）→ 后续实现地图（本票不含破坏性代码）。

## Decisions so far（本地镜像）

- **Scope ratification (2026-08-01)** — [#36 评论](https://github.com/sophiezel/goal/issues/36#issuecomment-5151795281)：goal-pipeline **独立审核模型** parity（非仅 guazi-flow-review 路径）；[#37](https://github.com/sophiezel/goal/issues/37)、[#38](https://github.com/sophiezel/goal/issues/38)、[#41](https://github.com/sophiezel/goal/issues/41) Question 已对齐。
- **Scope ratification (2026-08-01, 公共服务)** — [#36 评论](https://github.com/sophiezel/goal/issues/36#issuecomment-5151812266)：**独立审核模型是公共服务**；guazi-flow-goal / goal-pipeline / 外部流程经 **标准接口** 接入；边界盘点见 [#39](https://github.com/sophiezel/goal/issues/39)。
- **Research close [#37](https://github.com/sophiezel/goal/issues/37) (2026-08-01)** — [guazi-flow-goal-node-io-audit-phase5.md](../research/guazi-flow-goal-node-io-audit-phase5.md)：catalog **9+2 delta**（含 bridge `goal-state` 路径漂移、契约融入静默跳过）；review **kernel 契约** vs **goal-review** / **guazi-flow-review** wrapper 分轨表；断点 B1–B9（**guazi 现状**；goal-pipeline 处置见 #40）。
- **Grilling close [#40](https://github.com/sophiezel/goal/issues/40) (2026-08-01)** — [final ratification](https://github.com/sophiezel/goal/issues/40#issuecomment-5152145886)：B+C SSOT；轴 2 简体 Matt pack + Phase 1 软加载；轴 3 review **B** schema + chain；**双线独立 / goal-pipeline breaking-first**；**B1–B9** goal-pipeline 处置表；#38/#39/#41 scope裁剪。
- **Research close [#38](https://github.com/sophiezel/goal/issues/38) (2026-08-01)** — [goal-pipeline-external-patterns-gap-phase5.md](../research/goal-pipeline-external-patterns-gap-phase5.md)：差距矩阵 + Part J 候选；Wayfinder out-of-band；grill/to-specs borrow；review single-default + kernel B；reject guazi parity。
- **Research close [#39](https://github.com/sophiezel/goal/issues/39) (2026-08-01)** — [generic-services-inventory-phase5.md](../research/generic-services-inventory-phase5.md)：跨平面 generic services 表 + ownership；review kernel（B schema + chain SSOT）一等公民；goal-pipeline breaking-first；#41 边界 §6（SLO/timing 数字）。
- **Research close [#41](https://github.com/sophiezel/goal/issues/41) (2026-08-02)** — [unified-slo-quality-model-phase5.md](../research/unified-slo-quality-model-phase5.md)：goal-pipeline 统一质量+效率+漏出模型；DEM/LEAK→信号；W1/W2×stage；B4/B2/DEM-13 breach 语义；**ratify** W1/W2/Q-02/R-02/E-01 与结构；**SLO-Q-01/E-02/E-03/R-01/R-03/B4 数值 → v1.2 校准票**；Part J 输入 §6。
- **Task close [#42](https://github.com/sophiezel/goal/issues/42) (2026-08-02)** — [optimization-spec-outline-v1.2.md](../research/optimization-spec-outline-v1.2.md)：Part J–N + 附录 B1–B9 + 管线独立；Phase-5 研究波文档收口。

## Not yet specified（Fog）

- SLO-Q-01 等 **数值带** — v1.2 Part N 结构 + calibration 脚注；**实现地图** 样本校准 + `sla_breach` 与 timing substep 默认接线（P2）。
- guazi-flow-* SKILL 正文（仓外）审计深度边界。
- eval 覆盖 vs spec 缺口的分工。
- Review kernel 完整 **API v1 semver**（defer impl map；轴 3 B 已冻 schema + chain）。

## Out of scope

- 业务仓单票功能交付；Phase-4 [#30](https://github.com/sophiezel/goal/issues/30) 夹具除非新回归；本图会话内 bulk 实现。
- **用 guazi-flow-goal 编排/历史双轨约束 goal-pipeline 设计**（两条独立管线；见 #40 pipeline independence）。

## 规格交叉引用

- [optimization-spec-outline-v1.md](../research/optimization-spec-outline-v1.md) · [optimization-spec-outline-v1.1.md](../research/optimization-spec-outline-v1.1.md) · [optimization-spec-outline-v1.2.md](../research/optimization-spec-outline-v1.2.md)（Phase-5 SSOT）
- [pipeline-node-catalog.md](../research/pipeline-node-catalog.md) · [review-chain-bottlenecks.md](../research/review-chain-bottlenecks.md)
- [guazi-flow-goal/SKILL.md](../../../guazi-flow-goal/SKILL.md) · [goal-pipeline/SKILL.md](../../../goal-pipeline/SKILL.md)
