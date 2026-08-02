# 优化规格大纲 v1.3（Phase-6：goal-pipeline 解耦 + Matt 软性 workflow）

**Status:** **v1.3 — 文档收口**（2026-08-02）；扩展 [optimization-spec-outline-v1.2.md](optimization-spec-outline-v1.2.md) Part A–N，**不替代** v1.2 ratified 决策。实现轨 **另开地图**（见 Part Q）；不以本文冒充已落地代码。

**前身:** [optimization-spec-outline-v1.2.md](optimization-spec-outline-v1.2.md)（v1.2 Phase-5 breaking-first）  
**Grilling SSOT:** [#55 ratification](goal-pipeline-decouple-matt-ratification.md)（C1 全采纳）  
**父地图:** [Wayfinder #53 — goal-pipeline 与 guazi 解耦 + Matt 工程化工作流](https://github.com/sophiezel/goal/issues/53)

**原则（#53 / #55）：** goal-pipeline **默认路径零 guazi 依赖**；**高保真 + 效率** 优先于硬性五阶段仪式；Matt Skill Pack **软加载**；guazi-flow-goal **adapter opt-in**。

| 来源 | 文档 |
| --- | --- |
| v1.2 Part A–N | [optimization-spec-outline-v1.2.md](optimization-spec-outline-v1.2.md) |
| Matt 能力清单 | [matt-engineering-skill-canon-phase6.md](matt-engineering-skill-canon-phase6.md) |
| 解耦裁决 | [goal-pipeline-decouple-matt-ratification.md](goal-pipeline-decouple-matt-ratification.md) |
| 耦合审计 | [goal-pipeline-guazi-decouple-inventory.md](goal-pipeline-guazi-decouple-inventory.md) |
| Pack v2 原型 | [goal-engineering-pack-v2-prototype.md](goal-engineering-pack-v2-prototype.md) |

---

## Part O — goal-pipeline ↔ guazi 边界（normative add）

### O.1 两条管线（ratify #55 + v1.2 J.3）

| 管线 | 默认消费者 | 编排 SSOT | review wrapper |
|------|------------|-----------|----------------|
| **goal-pipeline** | goal 仓、通用 Agent 交付 | `goal-pipeline/*` stages + gate | **goal-review** + single-track（B8） |
| **guazi-flow-goal** | 业务仓（瓜子等） | `guazi-flow-*` marketplace skills | **guazi-flow-review**（dual opt-in） |

**共享：** review kernel（`goal-run-review-chain`、B schema）、部分 gate-lib 语义、可选同一 `state.json` 形状。

### O.2 默认路径不变量（goal-pipeline）

延续 v1.2 Part J.1 + #55：

- R1–R4 职责、机读 handoff + evidence、`gate --pre/post` 语义 — **normative**
- 五阶段 **显示名/拓扑** — **profile**（`stage_graph`）
- Wayfinder / to-ticket — **out-of-band**

### O.3 必须剥离项（实现义务，非本文落地）

完整清单见 [goal-pipeline-guazi-decouple-inventory.md](goal-pipeline-guazi-decouple-inventory.md) §2。**规格摘要：**

| 类别 | normative 目标 |
|------|----------------|
| Gate 入口 | 默认名 **goal-pipeline**；`gate-guazi-flow-stage.sh` → 兼容别名或 `--mode guazi` only |
| Stage SKILL | `goal-*` SSOT 本仓；**不** 默认 lazy-load 上游 `guazi-flow-*` |
| 任务目录 | 默认 `docs/goal/<task>/` 或 profile `task_docs_root`；**不** 硬编码 `docs/guazi-flow/` |
| Schema 目录 | `goal-artifact-schema/`（实现重命名自 guazi-flow-artifact-schema） |

### O.4 Adapter 保留（显式 opt-in）

| 机制 | 触发 |
|------|------|
| `--mode guazi` | gate、advance、contract enrich |
| `review_track=dual` | guazi-flow-review + `issues_gf[]` |
| `consumer: guazi` profile | gf-stage-driver、postmerge、index 仪式 |
| `guazi-flow-core` 查找 | resolve_verification_commands（guazi profile） |

### O.5 Reject

- goal-pipeline 默认加载 guazi-flow-review 或 dual-track（B8 延续）
- 从 guazi lazy-load 表反推 goal-pipeline 默认义务
- Wayfinder 作为 gate stage

---

## Part P — `workflow_profile` 与 engineering_pack v2（normative add）

### P.1 三字段正交（#55 轴 4）

| 字段 | 控制面 | 示例 |
|------|--------|------|
| `stage_graph` | 哪些 gate stage、R 层映射 | v1.2 default 五节点 |
| `workflow_profile` | R1–R2 **Matt 链形态** | `spec_path` \| `prototype_path` \| `hybrid` |
| `engineering_pack` | 实际加载的 pack SKILL 文件 | `grill_to_specs` \| `prototype` \| `full_matt` |

**规则：** `workflow_profile` **不** 增减 gate stage；prototype / handoff 为 plan 阶段 **软 skill**。

### P.2 `workflow_profile` 枚举

| 值 | 软链 | 适用 |
|----|------|------|
| `spec_path` | grill → to-specs | 行为已清、低保真足够 |
| `prototype_path` | grill → prototype → handoff | 形态/交互/逻辑需可运行资产 |
| `hybrid` | grill；按信号 to-specs 或 prototype | Wayfinder 默认叙事 |

**升级信号（informative）：** 「得看看长什么样 / 跑起来怎样」→ prototype_path 或 hybrid 内 prototype session。

### P.3 `engineering_pack` 扩展枚举（v1.3 add）

v1.2：`none | grill | to_specs | grill_to_specs`

**v1.3 add：** `prototype | handoff | full_matt`

解析器：`kernel/profile/engineering_pack.py` + `resolve_engineering_pack.py`（实现轨 Impl-7）。

### P.4 Pack SSOT 目录（normative 目标树）

见 [goal-engineering-pack-v2-prototype.md](goal-engineering-pack-v2-prototype.md) §1：

- **fork：** grill, to-specs, prototype, handoff, tdd
- **out-of-band：** wayfinder, to-tickets, loop-me, ask-matt
- **stage 内核：** goal-implement, goal-review（Matt 名 = 内嵌策略）

### P.5 `handoff/plan.json` 扩展字段（add）

| 字段 | 类型 | 何时 |
|------|------|------|
| `workflow_profile` | string | plan post |
| `engineering_pack` | string | plan post（可覆盖 profile） |
| `prototype_assets[]` | array | prototype_path / hybrid |
| `design_decisions[]` | string[] | handoff 后 |

**schema 版本：** `plan.schema.json` bump（实现轨）；v1.3 文档先 normative 字段名。

### P.6 `plan_profile: goal_lite`（add）

纯 goal-pipeline XS/S 任务：**不强制** guazi index 六段 / fe-argus 仪式；验收来自 to-specs 或 prototype handoff。与 v1.2 `plan_profile: lite`（index-lite）**并存**；profile 显式选用。

### P.7 示例 profile

- `goal-pipeline/references/profiles/_examples/xs-prototype-path.pipeline.profile.json`
- `goal-pipeline/references/profiles/_examples/xs-spec-path.pipeline.profile.json`

---

## Part Q — 迁移、breaking 与实现地图指针

### Q.1 Breaking 声明（相对 v1.2 实现态）

| 变更 | 破坏性 | 缓解 |
|------|--------|------|
| Gate 脚本重命名 | 外部脚本调用路径 | 兼容 symlink /  deprecate 窗 1 版本 |
| 默认 stage skill 名 | WO `skill_expected` | advance 默认 goal-*；guazi 模式保留旧名 |
| `docs/guazi-flow` 默认 | 旧任务目录 | profile + 迁移指南 |
| schema 目录重命名 | 引用路径 | 双路径读取窗 |

**非 breaking（规格已声明、v1.2 已有）：** smoke advance deprecate（B1）、single-track default（B8）。

### Q.2 建议实现地图子票（来自 #56）

| ID | 标题 | 优先级 |
|----|------|--------|
| Impl-1 | Gate 重命名与兼容窗 | P0 |
| Impl-2 | Driver / advance 默认 goal 叙事 | P0 |
| Impl-3 | Stage SKILL 去 Fork（5 stages） | P0 |
| Impl-4 | 根 SKILL + references 默认叙事 | P1 |
| Impl-5 | 任务目录 + goal_lite plan | P1 |
| Impl-6 | Artifact schema 重命名 | P1 |
| Impl-7 | profile：engineering_pack + workflow_profile | P1 |
| Impl-8 | 夹具拆分 goal-gate / guazi-adapter | P2 |
| Impl-9 | 安装/部署分 consumer | P2 |

**建议顺序：** Impl-1 → (Impl-2 ∥ Impl-6) → Impl-3 → (Impl-4 ∥ Impl-5) → Impl-7 → Impl-8 → Impl-9

### Q.3 实现地图 Destination（草案）

**标题：** Wayfinder: goal-pipeline v1.3 解耦实现（gate / stage / pack / 夹具）

**成功：** 默认路径零 guazi 隐式依赖；`workflow_profile` + pack v2 可加载；`run-all-gate-tests.sh` 绿；guazi adapter 夹具独立套件绿。

### Q.4 本文不覆盖

- guazi-flow-goal 编排重写
- 业务仓功能交付
- loop-me / 个人生产力 fork

---

## 附录 F — Phase-6 轴 SSOT（#53 / #55 摘要）

| 轴 | 决策 |
|----|------|
| **解耦** | 默认零 guazi；adapter opt-in |
| **Workflow** | R 层硬、五名软；workflow_profile + engineering_pack |
| **Matt pack** | fork v2 五 skill；wayfinder 外置 |
| **Spec** | v1.3 本文；实现另开图 |

---

## Changelog

| Date | Version | Action |
|------|---------|--------|
| 2026-08-02 | v1.3.0 | **Wayfinder #53 规划轨** — Part O–Q；合入 #54–#57 |
| 2026-08-02 | v1.2.0 | [#42](https://github.com/sophiezel/goal/issues/42) Part J–N |
| 2026-08-01 | v1.1.0 | [#31](https://github.com/sophiezel/goal/issues/31) Part F–I |

---

*v1.3 extends v1.2; goal-pipeline default path guazi-free; Matt soft workflow; implementation map separate.*
