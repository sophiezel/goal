# 优化规格大纲 v1.2（Phase-5：goal-pipeline 下一代规格）

**Status:** **v1.2 — 文档收口**（2026-08-02）；扩展 [optimization-spec-outline-v1.1.md](optimization-spec-outline-v1.1.md) Part A–I，**不替代** v1/v1.1 ratified 决策。实现轨另开地图；不以本文冒充已落地代码。

**前身:** [optimization-spec-outline-v1.1.md](optimization-spec-outline-v1.1.md)（v1.1 Phase-4 四层 + SLO v0）  
**Grilling SSOT:** [#40 final ratification（B1–B9）](https://github.com/sophiezel/goal/issues/40#issuecomment-5152145886)  
**父地图:** [Wayfinder #36 — Goal 全链路质量与效率（Phase-5）](https://github.com/sophiezel/goal/issues/36) · 本地镜像 [goal-full-chain-phase5-analysis.md](../maps/goal-full-chain-phase5-analysis.md)

**原则（#36 / #40）：** **goal-pipeline** 与 **guazi-flow-goal** 为 **两条独立管线**；goal-pipeline **breaking-first**，不为 guazi 历史双轨保留默认兼容层。规格与实现 **profile / 业务仓无关**；根因修复落在 goal-pipeline / 共享 kernel，不得以业务仓点对点修测替代 oracle 政策。

| 来源 | 文档 |
| --- | --- |
| v1 Part A–E | [optimization-spec-outline-v1.md](optimization-spec-outline-v1.md) |
| v1.1 Part F–I | [optimization-spec-outline-v1.1.md](optimization-spec-outline-v1.1.md) |
| I/O 审计（guazi 现状；goal normative 见 B1–B9） | [guazi-flow-goal-node-io-audit-phase5.md](guazi-flow-goal-node-io-audit-phase5.md) |
| 外部模式 / Part J 候选 | [goal-pipeline-external-patterns-gap-phase5.md](goal-pipeline-external-patterns-gap-phase5.md) |
| Generic services | [generic-services-inventory-phase5.md](generic-services-inventory-phase5.md) |
| 统一 SLO / 质量模型 | [unified-slo-quality-model-phase5.md](unified-slo-quality-model-phase5.md) |

---

## Part J — goal-pipeline profile 与 stage 图（R1–R4 外壳）

### J.1 不变量 vs 可配置外壳

| 类别 | 内容 | 规格动作 |
|------|------|----------|
| **不变量** | R1–R4 职责（v1.1 Part F）、每 R 层机读 handoff + evidence、gate `--pre`/`--post` 语义 | **normative** |
| **可配置** | stage **显示名**、stage 数量排列、`stage_graph` 引用 R 层映射 | **profile**；`profile: default` 保留 plan→implement→quality→review→complete 五名 |
| **非常量** | 五阶段名 **不是** 架构常量；禁止规格/ SKILL 将五名写死为唯一合法拓扑 | **reject**（#40 轴 2） |

**breaking-first：** 允许合并 smoke/quality 单轨（B1）、纯 goal-pipeline 路径 timing 对齐（B2）等 **破坏性** 规格变更；**不** 为 guazi-flow-goal 默认 profile 保留 goal-pipeline 义务镜像。

### J.2 `stage_graph`（规格字段，实现图落地）

- **add** — `plan.json` / profile 可声明 `stage_graph[]`：每项 `{ id, r_layer, gate_stage_id }`；`gate_stage_id` 映射现有 `gate-lib/*.sh`。
- **default profile** — 与 v1.1 F.2 五阶段表一致；R3 验证集中在 implement post（UVO/AM/IQ）+ quality（smoke 条件）+ review preflight。
- **Wayfinder / 大 initiative** — **out-of-band**（`/wayfinder`、GitHub map）；**不** 新增 `gate --post wayfinder` 硬阶段（#40 轴 2）。

### J.3 与 guazi-flow-goal 的关系（只读边界）

[#37](https://github.com/sophiezel/goal/issues/37) 描述 **guazi 调度链** I/O 与 catalog delta；**goal-pipeline normative** 处置以本文 **B1–B9** 与 Part L 为准，**不** 从 guazi 五阶段 lazy-load 表反推 goal-pipeline 默认义务。guazi 可选用同一 **review kernel**（wrapper profile）；dual + `guazi-flow-review` = **guazi 管线 only**（B8）。

---

## Part K — `engineering_pack` 与简体 Matt 衍生 Skill Pack

### K.1 裁决（#40 轴 2）

| 模式 | 处置 | 挂载 |
|------|------|------|
| **Wayfinder map / to-ticket** | **out-of-band** | 用户 `/wayfinder`；可选 `state.wayfinder_map_url` 元数据（**defer P2** ticket claim API） |
| **grill / grill-me-docs** | **borrow** | 简体 **grill** → Phase 1 `skill_to_load`（profile 触发） |
| **to-specs** | **borrow** | 简体 **to-specs** → R2 输入；强化 `handoff/plan.json` 前结构化段与验收矩阵草稿 |
| **to-ticket** | **borrow / out-of-band** | 默认 **不** 进 kernel stage 图 |
| **Implement / review** | **keep + harden** | 无新增 Matt 阶段名；R3/R4 见 v1.1 + Part L |

### K.2 `engineering_pack` profile 键（Phase 1 软加载）

- **add** — profile 可选：`engineering_pack: none | grill | to_specs | grill_to_specs`（枚举实现图细化）。
- **触发** — `goal-stage-driver` / Phase 1 `skill_to_load` 解析 pack → 加载 `skills/goal-engineering/*`（路径与 LICENSE 实现图；**reject** 运行时依赖英文 marketplace skill 为 SSOT）。
- **硬门禁** — pack **不** 替代 PQ/UVO/review chain；仅增强 R1/R2 访谈与规格化。

### K.3 eval 与 pack

- **borrow** — `goal-pipeline/evals` 与 pack 内 eval 对齐 interview-first 等用例；不阻塞 v1.2 文档闭合。

---

## Part L — 独立审核 kernel（B schema + chain SSOT + single-track 默认）

### L.1 一等公民公共服务（#40 轴 3 B）

| 能力 | 编排 / 入口 | 产出工件（kernel） | 规格 |
|------|-------------|-------------------|------|
| 原子链 | `goal-run-review-chain.sh` | packet, run, unified, fix-input | **SSOT**（B5） |
| LLM invoke | `run-independent-review.sh` / `kernel/review/cli.py` | `review-run.json`（provenance 必填） | normative |
| Full run | `cli.py run` | 含 merge → `review-fix-input.json` | 与 shell 链语义等价（B5 delta） |
| 组装 / preflight | `assemble-review-packet.sh`、`review_packet_preflight.py` | `review-packet.json` | PKT-01..04 |
| Channel policy | `review-channel-guard.py` | degraded / hard fail | B4 语义 |
| Merge | `merge-review-issues.sh` / `merge.py` | `review-fix-input.json` | B6；禁止手改 unified |
| Gate 壳 | `gate-lib/review.sh` | `handoff/review.json` | `review_forged`、`review_degraded_as_pass` |

**B 级 schema（normative add）：** `schemas/review-run.schema.json`、`review-unified.schema.json`、`review-fix-input.schema.json`；packet 见 `references/review-packet-schema.md`。完整 API **semver v1** → **defer P2**（#40）。

### L.2 Wrapper 分轨

| Wrapper | 默认消费者 | 角色 |
|---------|------------|------|
| **goal-review** | **goal-pipeline** | single-track 唯一默认 Agent SKILL；消费 kernel 工件 |
| **guazi-flow-review** | guazi-flow-goal（dual） | `issues_gf[]` 经 merge；**reject** goal-pipeline 默认加载 |

**default track:** `review_track=single`（B8）；`state.review_policy.track` plan post 持久化。

### L.3 implement ↔ review 契约（摘要）

- Packet + UVO fresh → review pre → chain → review post。
- 失败 → **仅** `review-fix-input.json` 驱动 implement 子环；`noop_fix` / stagnant / rounds cap（B6、B7）。
- Cross-provider：**NEVER** 同 provider 无降级；0 channel → `separation=degraded`（**非** full pass，见 Part N §N.3）。

---

## Part M — Generic services 索引（指针）

完整资产表见 [generic-services-inventory-phase5.md](generic-services-inventory-phase5.md)。v1.2 **normative 摘要**：

| 域 | 代表服务 | goal-pipeline 默认 | Part J 挂钩 |
|----|----------|-------------------|-------------|
| Control | `goal-pipeline-kernel`、`goal-stage-driver` | Turn Protocol | J.2 |
| Data | `resolve-artifact-paths`、`refresh-handoffs-after-index` | handoff SSOT | B7 |
| Quality | `gate-guazi-flow-stage` + `gate-lib/*`、UVO、AM、IQ | R2/R3 硬门禁 | B1、B3 |
| Quality | review kernel（§L） | single + chain | B4–B8 |
| Efficiency | `record-pipeline-timing` | 全 stage 墙钟（B2） | Part N |
| 遗留 | `gate-lib/smoke.sh` | **deprecate**（B1） | advance **quality only** |

**Ownership：** review kernel + B schemas = goal-pipeline normative；guazi-flow-goal = 独立编排 + 可选 dual wrapper。**不** 要求 guazi-compat 双轨服务为 goal-pipeline 默认消费者。

---

## Part N — 统一 SLO / 质量模型（#41 合入）

正交轴与 v1.1 Part F–I 一致；本文 **ratify 结构 + breach 语义**，数值带见 **N.2 校准脚注**。全文推导见 [unified-slo-quality-model-phase5.md](unified-slo-quality-model-phase5.md)。

### N.1 已 ratify（零或 tier 带）

| ID | 目标 | Breach |
|----|------|--------|
| **SLO-W1-01** | 声明缺陷类 silent pass **0** | 审计；不替代 gate |
| **SLO-W2-01** | `matrix_rows_unsatisfied` **0**（无 separation waive） | complete / delivery-quality |
| **SLO-Q-02** | PQ/IQ 同 `dedupe_key` 双 hard **0** | Part H C1 |
| **SLO-R-02** | handoff 链 complete 路径 **0** | chain validate + doctor |
| **SLO-E-01** | implement post p90：XS≤25m, S≤40m, M≤70m, L≤120m | **warn** + timing；`sla_enforce=hard` → v1.2 可选 block（strict profile） |

### N.2 结构 ratify；数值 **校准脚注**（非地图 HITL 强数字）

| ID | 定义（ratify） | 校准方法 | 至数字落地前 |
|----|--------------|----------|--------------|
| **SLO-Q-01** | DEM-08 纯误拦率 | 夹具 `260728-*` + 生产 N≥30/tier；policy 可标 `excluded_from_slo` | **审计 only**；与 #34 warn-pass 一致 |
| **SLO-E-02** | UVO 步 p90 | timing `substep=uvo` + oracle `steps[].duration` | warn |
| **SLO-E-03** | review 墙钟 p90 | `stage=review` + `review-run.json` | warn |
| **SLO-R-01** | noop_fix 率 | 主轨 30 run 基线 | warn（**提议** <10%，**非** Phase-5 ratified 数字） |
| **SLO-R-03** | duplicate_verify / UVO 触发 | efficiency_plane | warn；趋 0 |
| **SLO-B4-01** | degraded 通道占比 / complete 拦截 | 分层 0-channel vs degraded | `review_degraded_as_pass` complete **= 0**（硬）；比例阈值 **TBD** |

**脚注：** v1.1 Part I **SLO-Q-01 <5%** 为 **provisional hypothesis**；Phase-5 **defer** 至实现地图校准票（样本 + postmortem `dem08`）。政策验收仍跟踪 [#30](https://github.com/sophiezel/goal/issues/30)。

### N.3 B4 降级通道（normative 语义）

| 条件 | outcome | complete |
|------|---------|----------|
| separation 满足 | full channel | `quality_plane_check` 扫 forged |
| **0 channel**（detect 成功） | `separation=degraded`；deterministic only | **`review_degraded_as_pass` 必须 fail** |
| channel 不可达 | blocked + hint（B6） | 不 advance |

degraded **不得** 计为 W1「full 独立审核」等价 pass；matrix 要求 full separation 时须 profile 显式 waive 或记 W2 leakage。

### N.4 B2 timing 与 DEM-13

- **normative** — 每 stage pre/post → `pipeline-timing.json`（含纯 `gates/` 降级路径对齐，B2）。
- **默认 substep（接线目标）** — `uvo`、`review_chain`、`quality_gate`；legacy timing 阶段名 `smoke` **deprecate**（与 B1 一致）。
- **DEM-13** — 超 SLO-E-01 带 → `sla_warn` / timing flag；**不** 默认 block；`failure_code=sla_breach` → P2 实现 + 校准票。

### N.5 切片与报表

- 全指标：`task_tier` × `plan_profile` × `stage`（+ `substep`）× `fixture`。
- `review-run.json` 须带 `wrapper_profile`；goal-pipeline 默认报表过滤 **single + goal-review**（B8）。

### N.6 Part I 关系

v1.1 **Part I** 表保留为 SLO v0 基线；**ratification 状态** 以 Part N §N.1–N.2 为准（W1/W2/Q-02/R-02/E-01 数字确认；原 I.1 中 TBD 行由 N.2 脚注接替）。**不** 用 SLO 聚合绕过 hard gate（v1.1 I.2）。

---

## 附录 C — goal-pipeline normative：B1–B9（#40 ratified）

来源：[#37 §5](guazi-flow-goal-node-io-audit-phase5.md) 断点清单 + [#40 final](https://github.com/sophiezel/goal/issues/40#issuecomment-5152145886)。**Disposition 仅约束 goal-pipeline 规格**（guazi-only 行为见 #37，不进入默认 scope）。

| ID | Disposition | goal-pipeline 规格要求 |
|----|-------------|------------------------|
| **B1** | **normative** | **deprecate** smoke advance 轨；**仅 quality stage** 作为 verify 主轨；`goal-advance-stage` 不认 smoke handoff 为完成条件 |
| **B2** | **normative** | 单条 canonical 执行路径 + **全 stage** `record-pipeline-timing`；降级 `gates/` 路径不得缺效率 SSOT |
| **B3** | **normative** | 契约融入失败 **WARN→BLOCK**（profile 可 waive → W2）；禁止 `guazi_flow_contract_enriched=false` 静默进 implement |
| **B4** | **normative 语义**；数值 **Part N §N.2/N.3** | degraded / 0-channel / complete 护栏；`review_degraded_as_pass` |
| **B5** | **normative** | `goal-run-review-chain` 编排 SSOT；允许 CLI-only 实现若语义等价 |
| **B6** | **normative** | fix-input + stderr 与 B4 一致；unreachable ≠ degraded pass |
| **B7** | **normative** | `contract_stale` + `refresh-handoffs-after-index` 级联 |
| **B8** | **normative** | goal-pipeline **默认 single-track** + `goal-review`；dual + `guazi-flow-review` **guazi 管线 only** |
| **B9** | **P2 / doc-only** | 统一 `bridge-contract` 路径措辞；**不** 绑定 goal-pipeline SSOT 到 legacy `~/.goal-state/` 文档 |

---

## 附录 D — 管线独立性与默认 scope

| 管线 | 角色 | Phase-5 地图 |
|------|------|--------------|
| **goal-pipeline** | 进化轨主轨；breaking-first 规格与默认 profile | Part J–N、B1–B9、共享 review kernel |
| **guazi-flow-goal** | 业务仓 + guazi-flow-* lazy load；可选 dual | #37 现状快照；**不** 承担改造 guazi 以匹配新 goal-pipeline |
| **外部流程** | adapter / CLI | `kernel/review/cli.py`、`platform-review-adapter`；须遵守 kernel 工件 |

**reject（规格层）：**

- 用 guazi 历史五阶段 + dual-review **约束** goal-pipeline 设计。
- goal-pipeline 默认 **guazi parity** 或默认加载 `guazi-flow-review`。
- Wayfinder map 作为 pipeline **硬 gate stage**。

**实现：** 破坏性变更在 **新实现地图** 拆票；Phase-5 Wayfinder #36 交付 **spec v1.2** 文档闭合（[#42](https://github.com/sophiezel/goal/issues/42)）。

---

## 附录 E — Phase-5 轴 1 SSOT（#40 摘要）

| 轴 | 决策 |
|----|------|
| **1 SSOT** | **B+C** — decision pack + 研究 → **v1.2（本文）**；实现另开地图 |
| **2 Choreography** | 简体 Matt pack；Phase 1 软加载；`/wayfinder` 外置 |
| **3 Review** | **B** — I/O schema + chain SSOT |
| **Pipelines** | **Independent**；goal-pipeline **breaking-first** |

---

## Changelog

| Date | Version | Action |
|------|---------|--------|
| 2026-08-02 | v1.2.0 | **Wayfinder [#42](https://github.com/sophiezel/goal/issues/42)** — 合入 Part J–N + 附录 C–E；#37–#41 + [#40 ratification](https://github.com/sophiezel/goal/issues/40#issuecomment-5152145886) |
| 2026-08-01 | v1.1.2 | [#34](https://github.com/sophiezel/goal/issues/34) — Part H DEM-08 warn-pass |
| 2026-08-01 | v1.1.0 | [#31](https://github.com/sophiezel/goal/issues/31) — Part F–I |
| — | v1.0 | [optimization-spec-outline-v1.md](optimization-spec-outline-v1.md) |

---

*Formal spec outline v1.2 — extends v1.1; goal-pipeline breaking-first; guazi independent pipeline.*
