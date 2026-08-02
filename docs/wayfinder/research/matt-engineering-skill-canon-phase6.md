# Matt 工程化 Skill 能力清单（Phase-6 / Map #53）

**Closes:** [GitHub #54](https://github.com/sophiezel/goal/issues/54)  
**Map:** [#53 goal-pipeline 与 guazi 解耦 + Matt 简体工程化工作流](https://github.com/sophiezel/goal/issues/53)  
**Baseline:** [goal-pipeline-external-patterns-gap-phase5.md](./goal-pipeline-external-patterns-gap-phase5.md) · [optimization-spec-outline-v1.2.md](./optimization-spec-outline-v1.2.md) Part K · `goal-pipeline/skills/goal-engineering/`（v1.2 仅 **grill** / **to-specs** stub）

**采集方式：** 四篇微信正文经 **Playwright（Chrome）** 抓取（2026-08-02）；公开 skill 目录经 `github.com/mattpocock/skills` API 核对。

---

## 1. 来源摘要

| # | URL | 主题 | 与 Matt Pack 关系 |
|---|-----|------|-------------------|
| 1 | [别浪费时间写 Spec / Prototype](https://mp.weixin.qq.com/s/eEZhAnoI7PMDQ899VuD_rw) | Spec 路径 vs 原型路径；Wayfinder 内嵌 grilling / prototype 切换 | **核心 workflow** |
| 2 | [loop-me Skill](https://mp.weixin.qq.com/s/9iOh0gG0Vp_gXip3FP6Xwg) | 发现重复 loop → `workflows/*.md`；Push Right + Brief | **个人生产力 / in-progress**；与工程链互补 |
| 3 | [tdd 流程解读](https://mp.weixin.qq.com/s/jB8dr7QLBo5O4fAoOU_5Ew) | 红-绿-重构；主链位置；与 to-spec / codebase-design 边界 | **implement 内方法** |
| 4 | [Loop Engineering / Karpathy](https://mp.weixin.qq.com/s/DZM2-wG_p17kcnehD9dfww) | Verifier + State + Stop；五块积木；何时值得造 loop | **模式参考**（非 Matt 官方 skill）；对齐 R3 自修复环 |

**视频/原文（文 1 附录）：** Matt Pocock — *Don't waste time on specs: prototype instead*（2026-07-23）  
**公开仓库：** https://github.com/mattpocock/skills — `skills/engineering/*` + `skills/in-progress/*`

> **注：** 文 1 提及上一篇为 `/wayfinder` 专题，但地图 Notes 第二链为 **loop-me** 文（非 wayfinder 全文）。Wayfinder 行为以文 1 + 公开 `engineering/wayfinder` 目录为准。

---

## 2. 两条主链（文 1）

### 2.1 Spec 驱动链（高文字损耗）

```
to-spec → to-tickets → implement（内嵌 tdd + code-review）
```

- **痛点：** `to-spec` / `to-tickets` 以文字为唯一载体；文字→代码跳跃大，多轮改 spec 仍易偏离交互细节。
- **适用：** 行为已清晰、接口形态已定、低保真讨论即可收敛的需求。

### 2.2 原型驱动链（高保真优先）

```
grill-with-docs → prototype →（A/B/C 评审 + 迭代）→ handoff → implement（AFK agent 生产化）
```

- **核心：** 原型 = 可丢弃、回答一个问题的代码；可运行资产即最高精度「需求文档」。
- **保真度信号：** 当出现「我得看看它长什么样 / 跑起来怎样」→ 从 grilling **升级** prototype（Wayfinder 默认 grilling，按信号切换）。
- **分支：** UI prototype（浏览器内、最好嵌 live page）与 **logic prototype**（终端小程序验证状态机/管道）。
- **交付：** 满意后 compact 上下文 → **handoff** → 后台 **implement** 删临时代码、接真实功能。

### 2.3 Wayfinder 在链上的角色

- **out-of-band 大任务规划：** 拆成多个 planning session；每 session 有 ticket 类型。
- **默认 session 类型：** grilling（讨论范围、结构、命名）。
- **升级 session 类型：** prototype（关键问题是形态/表现/交互）。
- **与 goal-pipeline：** 对齐 v1.2 裁决 — Wayfinder **不进 gate stage**；地图驱动 research ticket（[#40](https://github.com/sophiezel/goal/issues/40) / Part K）。

---

## 3. 公开 Engineering Skill 全表

路径前缀：`mattpocock/skills/skills/engineering/`（`in-progress/` 见 §4）

| Skill | 意图（一句话） | 典型输入 | 典型输出 | R1–R4 | 进仓 fork | 备注 |
|-------|----------------|----------|----------|-------|-----------|------|
| **wayfinder** | 大 initiative 制图、拆 session / ticket | 用户目标、约束 | map、session 计划、ticket 类型 | **外置**（Plan） | **否** — out-of-band `/wayfinder` | 与 `docs/wayfinder/*` + GitHub issues 对齐 |
| **grill-with-docs** | 苏格拉底式对齐；一问一答 | 草案、docs、模糊需求 | 对齐后的决策、澄清记录 | **R1**（软） | **是** — 简体 `grill`（已有 stub） | 每次一问；不替代 PQ/plan gate |
| **to-spec** | 结构化规格文档 | grilling 结论 | Spec 文档 | **R2** | **是** — 简体 `to-specs`（已有 stub） | 规格路径前置；高保真场景可跳过 |
| **to-tickets** | Spec → 可执行 tickets | Spec | Ticket 列表（曳光弹） | **外置** / 可选 profile | **defer** — 默认不进五阶段 | `/wayfinder` 或显式 `planning_mode` |
| **prototype** | 可运行原型（UI / logic） | 方向 + 开放设计问题 | 2–3 变体可运行代码、设计决策 | **R1–R2 之间**（规划轨） | **是** — v2 pack 候选（#57） | 非 gate 名；profile 软加载 |
| **handoff** | 原型 → 实施交接包 | 原型分支、评审结论 | 实施 agent 可读 handoff | **R2→R3 边界** | **是** — 与 `handoff/plan.json` 语义对齐 | 含设计决策的可运行资产 |
| **implement** | 按 ticket 构建生产代码 | handoff / tickets | `src/**` 变更 | **R3** | **部分** — 能力在 `goal-implement` stage | 内嵌 tdd；遵守 write_set / WO |
| **tdd** | 红-绿-重构，一次一行为切片 | 单一待验证行为 | 测试 + 最小实现 | **R3 内** | **是** — implement 子策略（#57） | 不批量先写全测试；独立期望值 |
| **code-review** | 实施后代审 | diff、handoff | 审查意见 / fix 清单 | **R4** | **部分** — `goal-review` + chain | 与 kernel B schema 对齐 |
| **codebase-design** | 接口/测试边界设计 | 模糊 API 形态 | 设计结论 | **R1–R2** | **borrow P2** | 行为不清 → to-spec；接口不清 → 本 skill |
| **domain-modeling** | 领域模型澄清 | 业务描述 | 模型/术语表 | **R1–R2** | **borrow P2** | 可与 grill 串联 |
| **research** | 调研型任务 | 问题陈述 | 调研笔记 | **R1** | **out-of-band** | 与 Wayfinder research ticket 重叠 |
| **diagnosing-bugs** | 缺陷诊断 | 复现/日志 | RCA | **R3** | **borrow** — 对齐 fix-input 环 | 与 `implement-gate-fix-input` 协同 |
| **resolving-merge-conflicts** | 合并冲突 | git 状态 | 解决后树 | **R3** | **defer** | 通用工程 |
| **improve-codebase-architecture** | 架构改进 | 代码库上下文 | 重构计划 | **R2–R3** | **defer P2** | 大改不进默认 profile |
| **ask-matt** | Skill / 流程路由 | 用户意图 | 推荐 skill 链 | **外置** | **否** | 可映射为 goal-pipeline doctor / profile 提示 |
| **triage** | 问题分诊 | issue/症状 | 优先级/归属 | **外置** | **否** | 偏运维 |
| **setup-matt-pocock-skills** | 初始化 tracker/docs 路径 | 用户环境 | 本地配置 | **外置** | **否** | 安装用，非运行时 |

**R 层缩写（goal-pipeline）：** R1 澄清/计划 · R2 规格 handoff · R3 实现 · R4 审核/验证/完成

---

## 4. In-progress 与相邻 Skill（文 2）

| Skill | 意图 | 输出 | 与 grill 区别 | 进仓建议 |
|-------|------|------|---------------|----------|
| **loop-me** | 发现工作中**未意识到的重复 loop** | `NOTES.md` + `workflows/*.md` | grill = **对齐已有计划**；loop-me = **发现尚未抽象的模式** | **out-of-band** / 个人生产力；不并入默认 delivery gate |
| **batch-grill-me** | 批量拷问变体 | （in-progress） | — | defer |
| **claude-handoff** | 跨工具交接 | handoff 包 | 与 **handoff** 工程 skill 同名空间 | 参考语义，不 fork 英文名 |

**loop-me 设计哲学（文 2）：** **Push Right + Brief** — 把人介入点推到最晚；agent 备好决策就绪摘要再叫人。**完成标准：** workflow spec 须让 implementer **零追问**可构建 — 与 goal-pipeline handoff SSOT 同构目标。

---

## 5. TDD 要点（文 3）

- **调用：** `/tdd` 或 agent 在合适时自动选用；关键词 red-green-refactor。
- **边界：** 行为未清 → **to-spec**；问题是接口形态 → **codebase-design**。
- **主链（Matt 叙事）：** `grill-with-docs → to-spec → to-tickets → implement → code-review`；**tdd 在 implement 内部**，非独立 gate 阶段。
- **规则：**
  1. 测试描述**可观察行为**，非内部实现细节。
  2. 期望值来自**独立来源**（字面量、手算、spec），非同义反复。
  3. **仅全绿后重构**。
- **第一轮：** 最小端到端路径（如「能结账」）先绿，再扩展边界场景。

**goal-pipeline 映射：** R3 `goal-implement` + profile 可选 `engineering_pack` 扩展 **tdd** 子 skill；不新增 `gate --post tdd`。

---

## 6. Loop Engineering 模式（文 4 — Karpathy，非 Matt 官方）

与 Matt skill **互补**，用于理解 goal-pipeline 已有 **自修复环**（implement fix-input、review chain）：

| 概念 | 含义 | goal-pipeline 现物 |
|------|------|-------------------|
| **Verifier** | 自动判红/绿（测试、构建、指标） | `gate --post`、review chain、PQ |
| **State** | 跨轮记忆（试过什么、失败原因） | `evidence/*`、`handoff/*.json`、`decisions.json` |
| **Stop condition** | 达标或硬上限 N 轮 | review rounds cap、`blocked_stagnant` |
| **五积木** | Automation / Skill / Sub-agents / Connectors / Verifier | stage driver、goal-engineering pack、cross-provider review、GitHub issues、gate |

**四条件测试（是否值得重型 loop）：** 任务重复（≥周频）· 验证可自动 · token 预算可承受浪费 · agent 有真工具。  
**风险：** 理解债、认知投降 — 与 #55「软性 workflow」议题相关：loop 加速的是**已理解**的工作，非逃避思考。

---

## 7. 与 goal-pipeline 现状差距（post-v1.2）

| 能力 | v1.2 现状 | Phase-6 / #57 方向 |
|------|-----------|-------------------|
| grill | `goal-engineering/grill` **stub** | 完整简体 SKILL：一问一答、写 index、不交 gate |
| to-specs | `goal-engineering/to-specs` **stub** | 验收矩阵草稿 → `handoff/plan.json` 字段建议 |
| prototype | **无** | 新增 pack；Wayfinder session 类型对齐 |
| handoff | 仅有 kernel handoff JSON | 原型资产 + 设计决策段落规范 |
| tdd / code-review | implement/review stage 隐式 | 具名子 skill 或 stage 内 `skill_to_load` |
| wayfinder / to-tickets | out-of-band 文档 | 保持外置；可选 `wayfinder_map_url` 元数据 |
| loop-me | **无** | 不默认 fork；可文档引用个人自动化 |
| gate 入口名 | 仍 `gate-guazi-flow-stage.sh` | **#56 审计** → v1.3 解耦命名 |

**workflow 姿态（用户 #53 目标）：** 高保真 + 效率优先；**profile 软加载** Matt 链，**不以**五阶段硬性锁死为首要目标 — 与文 1「默认聊天、按保真度升级原型」一致。

---

## 8. 裁决汇总（供 #55 / #57 / #58）

| 类别 | Skills / 模式 | 裁决 |
|------|---------------|------|
| **out-of-band** | wayfinder、to-tickets、research、ask-matt、triage、loop-me | 用户命令或 GitHub map；不进 `gate --post` |
| **fork 进仓（简体 v2 pack）** | grill、to-specs、prototype、handoff、tdd（implement 子） | `engineering_pack` / Phase 1 `skill_to_load` |
| **stage 内核（已有）** | implement、code-review | 保持 `goal-implement` / `goal-review` + chain；Matt 名作为**内嵌策略** |
| **defer P2** | codebase-design、domain-modeling、improve-architecture | profile 扩展，非默认 XS |
| **模式借用** | Loop Engineering 四条件 + Verifier | 写入 v1.3 spec R3/R4 环叙述，非新 skill 名 |

---

## 9. 引用链接

- Matt skills 仓库：https://github.com/mattpocock/skills  
- Engineering 目录：https://github.com/mattpocock/skills/tree/main/skills/engineering  
- 安装：`npx skills@latest add mattpocock/skills`  
- aihero.dev 文档（文 3）：to-spec、implement、code-review、codebase-design、ask-matt  
- Shape Up（文 1 推荐）：https://basecamp.com/shapeup  
- autoresearch / Bilevel（文 4）：https://github.com/karpathy/autoresearch · arXiv:2603.23420  

---

## 10. 验收（#54）

- [x] 四篇微信正文已抓取并摘要  
- [x] 公开 `engineering/*` skill 清单与 R1–R4 / fork 裁决表  
- [x] 与 v1.2 gap 文档、Part K 对齐  
- [x] 产出路径：`docs/wayfinder/research/matt-engineering-skill-canon-phase6.md`
