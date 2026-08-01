# goal-pipeline vs Wayfinder / 高保真工程模式差距（Phase-5）

**Closes:** [GitHub #38](https://github.com/sophiezel/goal/issues/38)  
**Map:** [Phase-5 #36](https://github.com/sophiezel/goal/issues/36)  
**Ratification:** [Grilling #40 final](https://github.com/sophiezel/goal/issues/40#issuecomment-5152145886)（B+C SSOT、简体 Matt Skill Pack + Phase 1 软加载、`/wayfinder` 外置、review kernel **B**、goal-pipeline **breaking-first**、与 guazi-flow-goal **独立管线**、B1/B8 等）

**Baseline:** [goal-pipeline/SKILL.md](../../../goal-pipeline/SKILL.md)、[interview-protocol.md](../../../goal-pipeline/references/interview-protocol.md)、[goal-review/SKILL.md](../../../goal-pipeline/stages/goal-review/SKILL.md)、[guazi-flow-goal-node-io-audit-phase5.md](./guazi-flow-goal-node-io-audit-phase5.md) §3（review kernel）

---

## 1. 结论摘要

| 维度 | 现状 | Phase-5 规格方向（#40） |
|------|------|-------------------------|
| **阶段外壳** | 文档固定五名 + Phase 1 访谈 | **R1–R4 + profile 可配置 stage 图**；五名为 default profile，非常量 |
| **Wayfinder（制图/走票）** | 仓外 Cursor skill；goal 仅 `docs/wayfinder/*` 样本 | **out-of-band** `/wayfinder`；大 initiative 不进入 gate stage |
| **Grill / grill-me-docs** | `interview-protocol` + `decisions.json` / grill-with-docs 片段 | **borrow** → Goal 内嵌 **简体 Matt 衍生 grill**；**Phase 1 / profile 软加载** |
| **to-specs / to-ticket** | 部分由 plan 卡片 + PQ +（guazi）index 承担；无独立 skill 名 | **borrow** 简体 pack；to-specs → R2 输入 plan handoff；to-ticket → **out-of-band** 或 optional profile（非默认 gate） |
| **Implement + 自修复** | kernel WO、`implement-gate-fix-input`、noop_fix、UVO/AM/IQ | **keep + harden**（#40 B1/B3）；规格化 R3 环，不新增 Matt 阶段 |
| **独立审核** | `goal-run-review-chain`、goal-review SKILL、cross-provider、fix-input 环 | **add（规格）** kernel **B 级 schema** + chain SSOT；goal-pipeline **默认 single-track**（B8）；非 guazi dual 叙事 |
| **Review 与 guazi** | 代码路径可加载 guazi-flow-review | **reject for goal-pipeline default** — dual/gf-review = guazi 管线；goal-pipeline spec 不写 parity 义务 |

---

## 2. 能力差距矩阵

Matt Pocock 系能力在此作 **模式名**（wayfinder / grill / to-specs / to-ticket / implement / review）；落地形态为 **Goal 内 fork 简体 Skill Pack**（#40 轴 2），非运行时依赖英文仓外 skill。

| 能力模式 | goal-pipeline 现状（内嵌 / 脚本 / 文档） | 缺口 | 裁决 | Phase-5 / 实现轨 |
|----------|----------------------------------------|------|------|------------------|
| **Wayfinder map（制图）** | 无；Wayfinder 在 `docs/wayfinder` + GitHub issues | 大目标无仓内 SSOT skill；与 `/goal-pipeline` 未声明边界 | **borrow** | **out-of-band** only；不新增 gate stage；地图 Destination 驱动 research |
| **Wayfinder ticket（一会话一票）** | kernel 无 ticket 概念；靠 Agent 自律 | 无 claim/assignee 机读钩子 | **defer P2** | 可选 `state.wayfinder_map_url` 元数据；不阻塞 goal 执行 |
| **Grill / grill-me-docs** | Phase 1 三步访谈；`decisions.schema.json`；declarative-contract-gates 提及 grill | 无结构化「一问一答」skill；多仓集成靠 ad hoc | **borrow** | 简体 **grill** pack → Phase 1 `skill_to_load`（profile: integration / L+） |
| **to-specs** | plan gate + PQ + plan 卡片；guazi index 时 R2 更重 | 纯 goal-pipeline 无 index 时规格化弱 | **borrow** | 简体 **to-specs** → 产出 `handoff/plan.json` 前结构化段 + 验收矩阵草稿 |
| **to-ticket** | 无 GitHub/Jira 阶段机 | 拆票与执行环分离不足 | **borrow / out-of-band** | 默认 **不** 进五阶段；`/wayfinder` 或 explicit profile `planning_mode=wayfinder` |
| **Implement（高保真执行）** | FrozenWorkOrder、`code_writes_allowed`、write_set、fix-input 环 | 双轨 smoke/quality（B1）；静默契约跳过（B3） | **add（normative）** | 规格写清 R3 + B1/B3；实现图合并单轨 |
| **Review（独立模型）** | review-pre 确定性检查；chain；goal-review；分离 provider NEVER | wrapper/schema 未升 Part J；文档仍写「五阶段+guazi dual」话术 | **add（normative）** | Part J：kernel B schema + **single default**；`goal-review` = 唯一默认 wrapper |
| **TDD / 小步提交** | 依赖 Agent；无 named stage | 可选模式未 profile 化 | **defer P2** | implement 内策略，不新 gate 名 |
| **Expert eval（repo skills）** | `goal-pipeline/evals`、response-playbook | 与 Matt pack 未统一目录 | **borrow** | pack 内 eval 对齐 interview-first 等用例 |

**reject（goal-pipeline 规格层）：**

- 要求 goal-pipeline **默认** 加载 guazi-flow-review 或 dual-track（#40 B8）。
- 为兼容 guazi 保留 smoke 与 quality 双 advance 轨（#40 B1）。
- 将 Wayfinder **map** 设为 `gate --post` 硬阶段（#40 轴 2）。

---

## 3. 阶段 / 钩子：显式 vs out-of-band（#40 对齐）

```
[ out-of-band ]  /wayfinder  →  map issue + research tickets（Plan, don't do）
[ Phase 1 soft ] profile.engineering_pack → grill | to-specs（简体 Matt 衍生）
[ kernel stages ] R1–R4 外壳（profile 命名可变）→ plan → implement → verify → review → complete
[ gate SSOT ]     每 R 层机读 handoff + evidence；breaking-first 单轨
[ review ]        goal-run-review-chain（normative）→ goal-review wrapper only（default）
```

| 钩子类型 | 挂载点 | 技能/产物 |
|----------|--------|-----------|
| **软加载** | `goal-stage-driver` / Phase 1 `skill_to_load` | `goal-engineering/grill`、`goal-engineering/to-specs`（路径待实现图） |
| **硬门禁** | 现有 `gate --pre/post` | 不变语义；stage **名**可 profile 化 |
| **外置** | 用户命令 | `/wayfinder`、`to-ticket`（拆票） |
| **公共服务** | review stage exit | chain + B 级 JSON schema（#39 与本文互补） |

---

## 4. 独立审核：goal-pipeline 一等公民（非 guazi 附庸）

依据 [#40](https://github.com/sophiezel/goal/issues/40#issuecomment-5152145886) 与 [#37 §3](./guazi-flow-goal-node-io-audit-phase5.md)：

| 主题 | goal-pipeline 规格主张 |
|------|-------------------------|
| **默认 track** | **single**；rubric 嵌入 packet；仅 `goal-review` + chain |
| **Kernel** | `review-packet` / `review-run` / `review-unified` / `review-fix-input` **B 级字段**；编排 **goal-run-review-chain.sh** |
| **模型分离** | 沿用 SKILL NEVER（同 provider → 置信度降级） |
| **修复环** | `review-fix-input.json` SSOT；`blocked_stagnant` / rounds cap |
| **与 guazi** | guazi-flow-goal 可 dual + `guazi-flow-review`；**不**写入 goal-pipeline normative 默认 |
| **效率** | 去掉 goal-pipeline 侧重路径上的 duplicate gate（B1）；timing 全阶段（B2）→ #39 |

---

## 5. Phase-5 规格建议（Part J 候选条目）

写入 v1.2 / Part J 时使用 **add / borrow / reject / defer** 标签：

1. **add** — `goal-pipeline` profile 模型：`stage_graph` 引用 R1–R4 职责表，default 五名仅为 `profile: default`。
2. **add** — `engineering_pack`：可选 `grill` | `to_specs` | `none`；触发 Phase 1 软加载简体 skill。
3. **add** — Review kernel public schema（B）+ single-track default for goal-pipeline.
4. **add** — B1/B3/B7 normative（见 #40 B1–B9 表）；B4 语义 normative，数字 #41。
5. **borrow** — Matt 系流程语义经 **简体 fork** 落盘 `skills/goal-engineering/`（LICENSE + changelog）；**reject** 运行时依赖英文 Cursor marketplace 为 SSOT。
6. **reject** — goal-pipeline 规格内的 guazi parity / dual-review 默认。
7. **defer P2** — Wayfinder ticket claim API；to-ticket 与 kernel 深度集成；Review API v1 semver（#40 轴 3 defer C）。

---

## 6. 与 #39 / #41 分工

| 票 | 本文 (#38) 边界 | 对方 |
|----|-----------------|------|
| **#39** | 不重复列全仓服务清单 | handoff、timing、doctor、kernel 文件级 inventory |
| **#41** | 不 ratify SLO 数字 | B4 数值、leakage SLO、degraded 口径量化 |

---

## 7. 验证建议（关票后）

- #39 闭合时交叉检查：Part J 条目与 generic services 表无矛盾。
- 实现地图首票：简体 grill stub + `engineering_pack` profile 字段（可不在 Phase-5 地图内实现）。

*Phase-5 Wayfinder research；父地图 [#36](https://github.com/sophiezel/goal/issues/36)。*
