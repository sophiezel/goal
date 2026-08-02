# goal-pipeline 解耦 + Matt 软性 workflow 裁决（Phase-6 / Map #53）

**Closes:** [GitHub #55](https://github.com/sophiezel/goal/issues/55)  
**Map:** [#53 goal-pipeline 与 guazi 解耦 + Matt 简体工程化工作流](https://github.com/sophiezel/goal/issues/53)  
**Ratification:** 用户 **C1 全采纳**（轴 1–4，2026-08-02）  
**前置：** [#54 matt-engineering-skill-canon-phase6.md](./matt-engineering-skill-canon-phase6.md) · [optimization-spec-outline-v1.2.md](./optimization-spec-outline-v1.2.md) Part J/K · [#40 final](https://github.com/sophiezel/goal/issues/40#issuecomment-5152145886)

---

## 1. 裁决摘要（C1 全采纳）

| 轴 | 议题 | **C1（已采纳）** | C2（未采纳） |
|----|------|------------------|--------------|
| **1** | 完全解耦 guazi-flow-* 对默认路径的含义 | goal-pipeline **默认路径零依赖** guazi-flow-*：gate 脚本重命名、stage skill 去 Fork、任务目录去 `docs/guazi-flow/` 硬编码；guazi 仅 **`--mode guazi` / adapter 显式挂载** | 仅文档/命名解耦，gate 壳与 skill Fork 暂保留 |
| **2** | 高保真 + 效率 vs 硬性五阶段 | **R1–R4 + handoff/evidence normative 不可跳过**；五阶段 **显示名/排列可 profile 化**；`engineering_pack` **软加载、可省略**；无 index 纯 goal 任务走 **Matt 链**，非 guazi index 仪式 | 五名 + 全 gate 为默认唯一合法拓扑 |
| **3** | Matt 能力进仓 vs 用户命令 | **fork SSOT：** grill、to-specs、prototype、handoff、tdd（implement 子策略）；**out-of-band：** wayfinder、to-tickets、loop-me、ask-matt | 仅 grill + to-specs（v1.2 最小包） |
| **4** | v1.2 Part K 扩展 | **扩展 `engineering_pack` 枚举** + 新增 **`workflow_profile`**（与 `stage_graph` **正交**：`spec_path` \| `prototype_path` \| `hybrid`）；prototype 路径 **不新增 gate stage** | 仅扩 `engineering_pack`，无 workflow_profile |

---

## 2. 轴 1 — 完全解耦（normative）

### 2.1 默认路径（goal-pipeline）

| 耦合面 | C1 处置 | 实现轨（#56 inventory → 新实现地图） |
|--------|---------|--------------------------------------|
| Gate 入口 | `gate-guazi-flow-stage.sh` → **goal-pipeline 命名**（如 `gate-goal-stage.sh`）；`gate-lib/*` 语义不变 | rename + 夹具路径 |
| Stage SKILL | `goal-{plan,implement,quality,review,complete}` **去 Fork guazi-flow-***；SSOT 在本仓 `goal-pipeline/stages/` | 逐 stage 重写引用 |
| 任务目录 | 默认 **不** 要求 `docs/guazi-flow/<task>/index.md`；可选 `docs/goal/<task>/` 或 profile 声明的 docs 根 | profile + driver |
| Lazy-load | 默认 driver **不** 必读上游 guazi SKILL；guazi 编排仅在 adapter 模式加载 | `resolve_engineering_pack` / mode flag |
| 夹具 | `fixtures/guazi-flow-gate/` → 拆分 **goal-pipeline 默认夹具** + guazi adapter 夹具 | #56 优先级表 |

### 2.2 Adapter 保留（显式 opt-in）

- **guazi-flow-goal** 编排、dual review、`guazi-flow-review` wrapper：**不删除**；通过 `--mode guazi`、profile `consumer: guazi` 或业务仓显式配置挂载。
- **review kernel**（`goal-run-review-chain`、B schema）：**共享公共服务**；goal-pipeline 与 guazi **共用 kernel、分轨 wrapper**（延续 v1.2 B8）。

### 2.3 Reject（规格层）

- goal-pipeline 默认路径为兼容 guazi 保留 smoke 双轨（已 v1.2 B1 deprecate，本裁决 **确认**）。
- 从 guazi 五阶段 lazy-load 表 **反推** goal-pipeline 默认义务（延续 v1.2 J.3）。

---

## 3. 轴 2 — 软性 workflow（normative）

### 3.1 不可跳过（硬不变量）

延续 v1.2 Part J.1：

- **R1–R4 职责边界**（澄清 → 规格 handoff → 实现 → 审核/验证）
- 每 R 层 **机读 handoff + evidence**
- **`gate --pre` / `gate --post` 语义**（具体 stage 名可 profile 化）

### 3.2 可配置 / 可省略（效率面）

| 机制 | C1 规则 |
|------|---------|
| **stage_graph** | 五阶段 **显示名、数量排列** 可 profile；R 层映射不变 |
| **engineering_pack** | Phase 1 **软加载**；`none` 合法；不替代 PQ / review chain |
| **workflow_profile** | 见 §4；控制 **Matt 链形态**（spec vs prototype），**不** 增减 gate stage |
| **无 index 任务** | 纯 goal-pipeline 交付 **不强制** guazi index / fe-argus 仪式；验收矩阵来自 to-specs / handoff / plan.json |
| **Wayfinder** | **out-of-band**；不进 `gate --post`（#40 轴 2） |

### 3.3 设计原则（用户 #53 Destination）

- **首要目标：** 高保真 + 链路效率。
- **非首要目标：** 以五阶段名为唯一合法拓扑、锁死每步人工仪式。
- **保真度升级信号：** 「得看看长什么样 / 跑起来怎样」→ `workflow_profile: prototype_path` 或 session 级 prototype（#54 文 1）。

---

## 4. 轴 3 — Skill Pack 边界（normative）

### 4.1 仓内 fork SSOT（`goal-pipeline/skills/goal-engineering/` v2）

| Skill（简体名） | R 层 | 加载点 | 备注 |
|-----------------|------|--------|------|
| **grill** | R1 | Phase 1 `skill_to_load` | 一问一答；已有 v1.2 stub → v2 实化 |
| **to-specs** | R2 | Phase 1 / spec_path | 验收矩阵草稿；已有 stub |
| **prototype** | R1–R2 间 | prototype_path / Wayfinder session | UI + logic 分支；**非 gate 名** |
| **handoff** | R2→R3 | prototype 完成后 | 可运行资产 + 设计决策 |
| **tdd** | R3 内 | implement `skill_to_load` | 红-绿-重构；非独立 stage |

**stage 内核（keep）：** `goal-implement`、`goal-review` + review chain；Matt 名作为 **内嵌策略**，不新增 `gate --post` 阶段名。

### 4.2 out-of-band（用户显式命令）

| 模式 | 入口 | 不进 gate |
|------|------|-----------|
| wayfinder | `/wayfinder`、GitHub map | ✓ |
| to-tickets | `/wayfinder` 或显式 profile | ✓ |
| loop-me | 个人生产力 | ✓ |
| ask-matt | 路由参考 | ✓ |

### 4.3 defer P2（默认 profile 不加载）

codebase-design、domain-modeling、improve-codebase-architecture、triage、research（与 Wayfinder research ticket 重叠处 out-of-band）。

---

## 5. 轴 4 — profile 字段扩展（相对 v1.2 Part K）

### 5.1 `engineering_pack`（扩展枚举，草案）

```json
{
  "engineering_pack": "none | grill | to_specs | grill_to_specs | prototype | handoff | full_matt"
}
```

- **v1.2 已有：** `none | grill | to_specs | grill_to_specs`
- **v1.3 add：** `prototype`、`handoff`、`full_matt`（组合加载 grill→prototype→handoff 或 grill→to_specs，实现图在 #57 细化）
- **硬门禁：** pack **永不** 替代 PQ、UVO、review chain

### 5.2 `workflow_profile`（**新增**，与 `stage_graph` 正交）

```json
{
  "workflow_profile": "spec_path | prototype_path | hybrid"
}
```

| 值 | Matt 链（软加载） | 典型场景 |
|----|-------------------|----------|
| `spec_path` | grill → to-specs →（to-tickets 外置）→ implement | 行为已清、低保真足够 |
| `prototype_path` | grill → prototype → handoff → implement | UI/交互/逻辑需可运行资产 |
| `hybrid` | R1 grill；按保真度信号在 to-specs 与 prototype 间 **session 级切换** | Wayfinder 默认叙事 |

**正交关系：**

- `stage_graph` = **哪些 gate stage 跑、如何映射 R 层**（内核）
- `workflow_profile` = **R1–R2 之间用哪条 Matt 链**（增强）
- `engineering_pack` = **具体加载哪些 pack skill 文件**（解析结果）

三者独立配置；#57 产出 JSON 示例与 XS 叙事。

### 5.3 prototype 路径与 gate

- **add：** prototype / handoff 为 **plan 阶段软 skill**，**不** 新增 `gate --post prototype`
- prototype 产出进入 `handoff/plan.json` 扩展字段或链接资产（#57 定 schema 草案）

---

## 6. 对下游票的约束

| 票 | 本裁决输入 |
|----|------------|
| [#56](https://github.com/sophiezel/goal/issues/56) 耦合面审计 | 按 §2.1 三类分类（必须剥离 / adapter / 文档仅） |
| [#57](https://github.com/sophiezel/goal/issues/57) Skill Pack 原型 | §4–§5 目录树 + `workflow_profile` 示例 + XS 最小高保真路径 |
| [#58](https://github.com/sophiezel/goal/issues/58) spec v1.3 | 本文 + #56 + #57 → Part O（解耦）+ Part P（workflow_profile）增量 |
| **新实现地图**（本图外） | gate 重命名、stage 去 Fork、pack v2 实装、夹具迁移 |

---

## 7. 验收（#55）

- [x] 四轴 C1 表格式裁决
- [x] 与 #54 清单、v1.2 Part J/K 一致且无冲突
- [x] 产出路径：`docs/wayfinder/research/goal-pipeline-decouple-matt-ratification.md`
- [x] 用户 HITL：**C1 全采纳轴 1–4**
