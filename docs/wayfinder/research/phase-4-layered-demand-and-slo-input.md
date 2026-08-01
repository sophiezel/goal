# Phase-4：分层需求模型与 Pipeline SLO 规格输入

**Status:** Research closure for [Wayfinder #28](https://github.com/sophiezel/goal/issues/28)  
**Parent map:** [Wayfinder #24 — guazi-flow-goal 全链路硬化（Phase-4）](https://github.com/sophiezel/goal/issues/24)  
**Upstream:** [optimization-spec-outline-v1.md](optimization-spec-outline-v1.md) · [tech-debt-p2.md](../tech-debt-p2.md) · [pipeline-node-catalog.md](pipeline-node-catalog.md) · [phase-3-hitl-ratified.md](phase-3-hitl-ratified.md)  
**Fixture（非交付定义）：** CTB-44243 `260728-*` — UVO-01 / `related_union` 归因见 [uvo-01-260728-root-cause-and-fix-options.md](uvo-01-260728-root-cause-and-fix-options.md)（[#25](https://github.com/sophiezel/goal/issues/25) closed）；夹具 gate 验收 [#30](https://github.com/sophiezel/goal/issues/30)

**原则（#24 / #29）：** 规格与实现 **profile / 业务仓无关**；根因修复落在 **goal-pipeline / guazi-flow-goal**；不得以业务仓点对点修测、收窄 `testPathPattern` 或单票 skip 门禁替代 oracle 政策。

---

## 1. 建议写入 spec v1.1 的章节骨架

| 新章 | 内容 | 与 v1 关系 |
|------|------|------------|
| **Part F — 四层需求与阶段职责** | 需求层→契约层→验证层→执行层；五阶段 gate 映射 | 扩展 Part D（PQ/IQ），不重复 Part A W1/W2 |
| **Part G — 失败模式 taxonomy 与 owner** | 分层 × 平面 × `failure_code` × 主责节点 | 对齐 draft L1–L10，补「执行层」 |
| **Part H — 横切面政策选项集** | UVO scope、handoff tier、PQ/IQ dedupe、AM/W2 | ratified 默认 + profile 覆盖表 |
| **Part I — Pipeline SLO v0** | 指标定义、采集面、阈值（可 TBD）、与 tier/profile 切片 | 引用 `task-tier-matrix`、timing SSOT |
| **附录 — 行业对照与采纳边界** | TIA / policy gate / 分层验证 | 仅指导 goal 抽象，不绑 Jenkins/GitLab 产品 |

---

## 2. 四层需求模型（profile 无关）

四层描述 **「什么必须在哪一阶段被冻结 / 证明」**，与 [goal-runtime 四平面](https://github.com/sophiezel/goal/blob/main/docs/architecture/goal-runtime.md) 正交：平面是 **SSOT 与检查职责**；四层是 **需求成熟度递进**。

| 层 | 语义 | 典型工件 | 主阶段 | 质量面代表 |
|----|------|----------|--------|------------|
| **R1 需求层** | 范围、验收意图、矩阵行、Out of Scope | index 矩阵 / V#、Goal 卡片、decisions | plan（Agent）+ plan post | PQ 结构子集；AM 行 id |
| **R2 契约层** | 可机读的 API/参数/write_set/集成约定 | index API 表、伪代码、write_set | plan post → implement pre | **PQ** hard；refresh 后 **IQ-10** |
| **R3 验证层** | 变更范围内「证明实现」的机器证据 | UVO、contract-conformance、runtime-smoke | implement post；quality | **UVO**、IQ-10/CC、smoke |
| **R4 执行层** | 编排、handoff、墙钟、修复循环、通道 | state、handoff 链、timing、review-run | 全阶段；complete 汇总 | Control / Data / Efficiency；`quality_plane_check` |

**五阶段职责（摘要）：**

| Stage | R1 | R2 | R3 | R4 |
|-------|----|----|----|-----|
| **plan** | 冻结矩阵与范围（Index-Lite 仍须矩阵） | PQ block 不完整契约 | — | `task_tier`、Argus manifest（lite=rule v1） |
| **implement** | AM ratchet 绑定矩阵 verify 列 | IQ-10 / CC 对 `src` | **UVO 必填**；IQ structural QC | noop_fix ratchet；UVO hash 缓存 |
| **quality** | — | handoff 链与 implement 一致 | runtime-smoke（条件） | quality-gate QG-01 |
| **review** | rubric 对 L9 语义（软/硬由 tier） | packet 与 index hash | preflight 要求 UVO fresh | channel guard；merge-review 不可 skip |
| **complete** | W2 记账（`matrix_rows_unsatisfied`） | — | `quality_plane_check` 扫 forged/UVO skip | delivery-quality；timing 可选 SLA |

**lite vs standard vs tier M/L（与 v1 Part C 一致，Phase-4 强调）：**

- **lite（XS/S）：** 不降级 R2（PQ-01/02/05/07）、不跳过 R3（UVO/IQ-10/review preflight/complete `quality_plane_check`）；仅 **效率面** 可减（Argus fe-argus、dual review、doctor、timing substep）。
- **standard：** hybrid Argus；review single/dual 按 `review_track`。
- **strict：** review-first UX/L10；goal-quality e2e 证据可 **BLOCK**（[#19](https://github.com/sophiezel/goal/issues/19)）。
- **M/L/XL：** 强制 full index；墙钟与并行策略吃满 [task-tier-matrix.md](../../../guazi-flow-goal/references/task-tier-matrix.md)；**禁止**把 M/L 压成 XS 20m；子 agent DAG / multi-unit 属于 R4，不替代 R3 节点。

---

## 3. 失败模式 taxonomy × 平面 × owner

在 [draft-zero-leakage L1–L10](draft-zero-leakage-and-ux-policy.md) 上增加 **执行层（R4）** 与 **误拦（false block）** 分型，便于 SLO 与 postmortem。

| 层 | 模式 ID | 现象 | 平面 | 主责 gate / 脚本 | primary `failure_code` |
|----|---------|------|------|------------------|------------------------|
| R1 | DEM-01 | 矩阵/范围未冻结即写码 | Control | `assert-plan-before-code` | `plan_code_order` |
| R1 | DEM-02 | 空 write_set | Quality | plan/implement post | `empty_write_set` |
| R2 | DEM-03 | index/API 表/schema 不合格 | Quality | `plan-quality-gate.py` | PQ-* / `plan_schema_incomplete` |
| R2 | DEM-04 | plan–implement 绑定漂移 | Data+Quality | IQ-10 / refresh | `contract_stale`, IQ-10 |
| R2 | DEM-05 | split handoff 读错 tier | Data | `resolve-artifact-paths` | `handoff_missing`, doctor `handoff_ssot_drift` |
| R3 | DEM-06 | 无 UVO 或 oracle 失败 | Quality | UVO | `uvo_not_pass`, `verification_oracle_failed` |
| R3 | DEM-07 | 矩阵 verify 列未覆盖 diff | Quality | AM ratchet | `am_ratchet_failed` |
| R3 | DEM-08 | **验证范围过宽（误拦）** | Quality+Efficiency | UVO `findRelatedTests` / related_union | `verification_oracle_failed`（根因：oracle 政策，非业务单测「修绿」） |
| R3 | DEM-09 | smoke 条件未满足仍 advance | Quality | `quality-gate.sh` | QG-01 |
| R4 | DEM-10 | subject_hash 不变重跑 | Efficiency | implement/review post | `noop_fix` |
| R4 | DEM-11 | 重复贵验证 | Efficiency | UVO / efficiency_plane | `duplicate_verify` |
| R4 | DEM-12 | review 伪造/降级当 pass | Quality | review-chain, complete | `review_forged`, `review_degraded_as_pass` |
| R4 | DEM-13 | 墙钟超 tier 无记账 | Efficiency | timing（**缺口**：无统一 breach code） | **TBD** `sla_breach`（P2 实现） |
| 漏出 | LEAK-* | L1–L9（v1 Part A） | 见 draft | 对应闸门 | 见 failure-codes.json |

**Owner 约定（规格级）：**

- **PQ / plan post owner：** 契约冻结（R2 入口）。
- **UVO owner：** R3 变更范围验证 + DEM-08 政策（Phase-4 实现轨，见 [#25](https://github.com/sophiezel/goal/issues/25) 选项收敛）。
- **IQ owner：** 实现绑定与 dedupe（v1 Part D）。
- **AM owner：** 矩阵 verify 与 ratchet；W2 waive 语义（#16 C1）。
- **Data plane owner：** handoff tier、chain validate、refresh cascade。
- **Efficiency owner：** noop、duplicate_verify、timing SLA（与 Agent WO 协同，不替代质量面）。

---

## 4. 横切面政策：选项集与推荐默认（profile 可覆盖）

| 主题 | 选项 | **推荐默认（C1 延续）** | profile 覆盖 |
|------|------|-------------------------|--------------|
| **PQ/IQ dedupe** | 双 hard / 单键单次 W1 / warn-only | **v1 Part D C1**：同 `dedupe_key` PQ fail 则 IQ 不二次 block；PQ 覆盖则 IQ warn | 无 lite 降级 |
| **UVO scope** | 全量 test / write_set+import 闭包 / `test:related-tests` / 显式 matrix 列命令 | **tier+matrix 驱动**；`test:related-tests` 仅当 index 声明；**禁止** Dev Loop 默认全量 `yarn test` | `plan.json` verification 段；env 逃逸须 separation |
| **UVO `related_union`** | 全局常量名匹配 / hub 文件（App.tsx）扩集 / 仅 direct imports | **待 #25 闭合**；规格方向：**write_set 闭包优先**，hub 扩集须 **opt-in**（index 或 profile），避免 DEM-08 | `GOAL_UVO_*` 或 plan 字段（实现票） |
| **handoff tier** | repo-only / split Tier-R | **#14/#17 C1**：resolver SSOT；doctor live check 在 Wave/CI | `artifact_layout.split` |
| **AM waive → W2** | 一律漏出 / separation waive | **#16 C1** | — |
| **review track** | single / dual | lite & XS/S → **single** | `review_track` |
| **legacy smoke gate** | 允许直调 / hard-disable | **hard-disable** | `GOAL_ALLOW_LEGACY_SMOKE_STAGE=1` |

**P2（不阻塞 #28）：** `dedupe_key` 字段在 gate JSON 与 fixture 显式化 — [tech-debt-p2.md](../tech-debt-p2.md)。

---

## 5. Pipeline SLO v0（可 ratify 草案）

**计量窗口：**

- **W1-SLO：** 单次 `kernel init` → `complete`（或 blocked 退出点）的 run。
- **W2-SLO：** 同一 MR/分支上连续 run 或产品声明的矩阵窗口（与 v1 W2 漏出口径一致）。
- **切片：** `task_tier` × `plan_profile` × `stage`；夹具 run 单独打标 `fixture=CTB-44243-260728`。

### 5.1 指标表

| ID | 名称 | 定义 | 采集面 | v0 目标阈值 | 备注 |
|----|------|------|--------|-------------|------|
| **SLO-W1-01** | W1 silent pass 率 | W1 内声明缺陷类漏出事件数 / 应检闸门次数 | `quality_plane_check`、handoff `gate`、retro 标签 LEAK-* | **0**（硬） | 与北星一致 |
| **SLO-W2-01** | W2 矩阵未满足率 | `\|matrix_rows_unsatisfied\| / 声明行数` | `delivery-quality.json` / leakage 字段 | **0**（无 separation waive） | L9 软码不强制 implement block |
| **SLO-E-01** | implement post 墙钟 p90 | `pipeline-timing.json` stage=implement 的 end−start | `record-pipeline-timing` gate 边界 | XS ≤25m, S ≤40m, M ≤70m, L ≤120m（**p90**） | 对齐 [task-tier-matrix](https://github.com/sophiezel/goal/blob/main/guazi-flow-goal/references/task-tier-matrix.md) |
| **SLO-E-02** | UVO 步耗时 p90 | `verification-oracle.json` steps[].duration 或 sum | UVO evidence | **TBD** 按 tier（需 substep 接线） | catalog：substep 未默认接线 |
| **SLO-E-03** | review 墙钟 p90 | timing stage=review 或 `review-run.json` latency | timing + review-run | **TBD**（P2 single track 后基线） | |
| **SLO-Q-01** | UVO 误拦率 | DEM-08：失败用例路径 ∩ write_set 相关闭包 = ∅ 的次数 / UVO fail 次数 | postmortem 标签 + oracle JSON 用例列表 | **< 5%**（v0 假设，**需 #25 后校准**） | 夹具 `260728` 为高误拦样本 |
| **SLO-Q-02** | PQ/IQ 重复 block 率 | 同 `dedupe_key` 双 hard 次数 / IQ fail 次数 | plan/implement QC JSON（dedupe 字段落地后） | **0** | P2 实现 |
| **SLO-R-01** | noop_fix 率 | blocked(`noop_fix`) / implement+review post 尝试次数 | `state.failure_code`、fix-input | **< 10%**（v0） | 效率+Agent 质量信号 |
| **SLO-R-02** | handoff 一致性失败率 | `validate-pipeline-chain` + doctor `handoff_*` fail / gate 次数 | chain validate、four_planes_doctor | **0** on complete 路径 | |
| **SLO-R-03** | duplicate_verify 率 | `duplicate_verify` / UVO 触发次数 | efficiency_plane_check | **TBD** | 目标趋近 0（同 hash 跳过） |

### 5.2 采集与门禁关系

- **不新增 silent pass：** SLO 记账 **不得** 绕过既有 hard gate（仅审计与 postmortem）。
- **SLA breach：** v0 仅 **warn + timing 标记**；v1.1 可选 `sla_breach` failure_code（catalog 已记缺口）。
- **夹具：** `260728-*` 用于校准 **SLO-Q-01** 与 UVO 政策验收；达标定义为 goal 修复后 **implement post exit 0** ([#30](https://github.com/sophiezel/goal/issues/30))。

---

## 6. 行业成熟方案对照与采纳边界

| 实践 | 成熟态要点 | **采纳（goal 抽象）** | **拒绝 / 不在 Phase-4** |
|------|------------|----------------------|-------------------------|
| **变更影响分析（TIA）** | 只跑受影响测试；依赖图 / 文件→测试映射 | UVO write_set + import 闭包；`test:related-tests` 作为 **声明命令**；hub opt-in | 在 jian-h5 等业务仓改 Jest 配置「只为单票绿」 |
| **Policy-as-code gates** | OPA/Conftest、required checks、不可 skip | PQ/IQ/UVO/AM 即声明式 policy；lite **不** skip 质量节点；`failure-codes.json` SSOT | 每 repo 复制一套 gate shell |
| **分层验证** | lint → unit → integration → e2e 分层 | plan→implement（UVO）→quality（smoke）→review→complete；e2e **tier strict 可选** | Dev Loop 默认全量 e2e / 全量 `yarn test` |
| **Test quarantine / flaky** | 隔离不稳定测 | separation + matrix waive（#16）；**不**默认 quarantine 跳过 UVO | 无 separation 的 gate skip |
| **Merge queue / batched CI** | 预合并验证 | goal **单 task run** 语义；多 unit 并行在 M/L tier（Pack F） | 用外部 queue 替代 handoff SSOT |

---

## 7. 与夹具 `260728-*` 的关系（输入事实）

| 事实 | 分层归类 | Phase-4 动作 |
|------|----------|--------------|
| UVO-01 `test:related-tests` 失败含 `order/newbie` 等与 write_set 弱相关套件 | R3 **DEM-08** | goal `verification_oracle_core` 政策（[#25](https://github.com/sophiezel/goal/issues/25)） |
| `findRelatedTests` 含 `App.tsx`、constants 基名匹配 | R3 oracle 设计 | 非业务仓修测 |
| 早期 IQ-10 / split handoff | R2/R4 | Phase-3 已大量收口；complete 仍靠 doctor tier |

---

## 8. 下游实现与开放问题

| 项 | 建议工单类型 | 阻塞关系 |
|----|--------------|----------|
| UVO `related_union` / hub 政策实现 | Task（goal-pipeline） | [#25](https://github.com/sophiezel/goal/issues/25) → [#30](https://github.com/sophiezel/goal/issues/30) |
| optimization-spec **v1.1** 文档合入 Part F–I | Doc / Wayfinder | 本研究 + #25 结论 |
| `sla_breach` + timing substep 默认接线 | P2 工程 | [tech-debt-p2](../tech-debt-p2.md)、catalog 耗时缺口 |
| SLO 聚合脚本 / dashboard | P2 | 依赖采集面落地 |

---

## Changelog

| Date | Action |
|------|--------|
| 2026-08-01 | #28 research closure — layered demand R1–R4, failure taxonomy, policy defaults, SLO v0 table, industry bounds |

---

**Ratified 合入:** [optimization-spec-outline-v1.1.md](optimization-spec-outline-v1.1.md)（[#31](https://github.com/sophiezel/goal/issues/31)）。

*输入稿 — 供 Phase-4 spec v1.1 与 goal 实现轨引用；不替代 ratified v1 Part A–E。*
