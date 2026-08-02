# 优化规格大纲 v1.4（Phase-7：双管线完全独立 + review-kernel 公共服务）

**Status:** **v1.4 — 文档收口**（2026-08-03）；实现轨另开地图（Part W）。  
**Closes:** [#74](https://github.com/sophiezel/goal/issues/74)  
**扩展** [optimization-spec-outline-v1.3.md](optimization-spec-outline-v1.3.md) Part A–Q；**收紧** v1.3 Part O.4「adapter 内嵌 goal-pipeline」模型。  
**宪章 SSOT:** [two-pipeline-independence-ratification.md](two-pipeline-independence-ratification.md)（Q1=A Q2=B Q3=C Q4=A Q5=C）  
**父地图:** [Wayfinder #70](https://github.com/sophiezel/goal/issues/70)

| 来源 | 文档 |
| --- | --- |
| v1.3 Part A–Q | [optimization-spec-outline-v1.3.md](optimization-spec-outline-v1.3.md) |
| 双向耦合盘点 | [two-pipeline-bidirectional-coupling-inventory.md](two-pipeline-bidirectional-coupling-inventory.md) |
| 完全独立宪章 | [two-pipeline-independence-ratification.md](two-pipeline-independence-ratification.md) |
| Review kernel 清单 | [generic-services-inventory-phase5.md](generic-services-inventory-phase5.md) §2 |
| Skill 合入门槛 | [writing-great-skills-dual-pipeline-gate.md](writing-great-skills-dual-pipeline-gate.md) |

**原则：** goal-pipeline 与 guazi-flow-goal **双向零依赖**；共性 **仅** review-kernel 公共服务；**无 compat 窗**。

---

## Part R — 仓内拓扑与 ownership（normative add）

### R.1 三顶层目录

```
goal/                          # 本 monorepo
├── goal-pipeline/             # 管线 A：通用 goal 交付（零 guazi）
├── guazi-flow-goal/           # 管线 B：瓜子编排入口（零 goal-pipeline 脚本依赖）
├── shared/
│   ├── review-kernel/         # 公共服务：独立审核 loop + B schemas
│   └── review-schema/         # 可选：schema 单仓（@goal/review-schema@1.x）
└── docs/wayfinder/            # 规划与收口（不变）
```

| 目录 | Owner | 禁止 |
|------|-------|------|
| `goal-pipeline/` | goal 管线 | 任何 `guazi` 生产代码、compat wrapper、`--mode guazi` |
| `guazi-flow-goal/` | guazi 管线 | `import` / `exec` goal-pipeline scripts；读写 `~/.goal-pipeline/` |
| `shared/review-kernel/` | 公共服务 | 管线 stage 叙事、guazi index 仪式、goal gate |

### R.2 运行时三路径（Q3=C）

| 环境变量（建议） | 默认路径 | 内容 |
|------------------|----------|------|
| `GOAL_STATE_HOME` | `~/.goal-pipeline/` | goal state、scripts、Tier-R |
| `GUAZI_STATE_HOME` | `~/.guazi-flow/` | guazi state、scripts、Tier-R |
| `REVIEW_KERNEL_HOME` | `~/.goal-services/review-kernel/` | chain、CLI、Python kernel、schemas 安装副本 |

两管线 **只读** 引用 `REVIEW_KERNEL_HOME`；**禁止** 互写对方 home。

### R.3 两条管线（取代 v1.3 O.1）

| 管线 | 编排 SSOT | Gate SSOT | Review |
|------|-----------|-----------|--------|
| **goal-pipeline** | `goal-pipeline/stages/goal-*` + driver | `gate-goal-stage.sh`（**仅 goal**） | `goal-review` wrapper → **review-kernel** |
| **guazi-flow-goal** | `guazi-flow-*` marketplace + 本仓 SKILL | `guazi-gate-stage.sh`（fork 自 `9910d79` guazi 分支） | `guazi-flow-review` wrapper → **review-kernel** |

**共享：** `shared/review-kernel` + `shared/review-schema`（Q5=C）  
**不共享：** gate-lib 实现、stage driver、handoff 路径默认、install 脚本

### R.4 v1.3 废止项（normative）

| v1.3 条款 | v1.4 处置 |
|-----------|-----------|
| O.4 Adapter 保留（`--mode guazi`） | **废止** — 删除 |
| O.1「共享 gate-lib 语义」作为默认耦合 | **缩小** — 仅 review-kernel；gate 各管线自持 |
| Q.1 compat symlink 窗 | **废止** — Q4=A 立即分轨 |
| dual-track / `issues_gf` | **goal 侧删除**；guazi 侧 fork 后自管 |

---

## Part S — shared/review-kernel 边界（normative add）

### S.1 包内资产（从 `9910d79` 抽取）

| 资产 | 来源（baseline） | 管线无关 |
|------|------------------|----------|
| `run-review-chain.sh` | `goal-run-review-chain.sh` 语义 | ✓ |
| `assemble-review-packet.sh` | goal-pipeline/scripts | ✓（输入契约文档化） |
| `merge-review-issues.sh` / `merge.py` | kernel/review | ✓（**删除** `issues_gf` 于 goal 包；guazi fork 可加） |
| `run-independent-review.sh` | scripts | ✓ |
| `review_packet_preflight.py` | scripts | ✓ |
| `review-channel-guard.py` | scripts | ✓ |
| `kernel/review/*.py` | goal-pipeline/kernel/review | ✓ |
| B schemas | `schemas/review-*.schema.json` | → `shared/review-schema/` |

### S.2 留在各管线（不抽取）

| 资产 | goal-pipeline | guazi-flow-goal |
|------|---------------|-----------------|
| `gate-goal-stage.sh` / `guazi-gate-stage.sh` | goal-only | guazi fork |
| `gate-lib/*.sh` | goal-only | guazi fork |
| `goal-stage-driver.sh` | ✓ | ✗（guazi 自研 driver） |
| `resolve-artifact-paths.py` | goal 默认 `docs/goal/` | guazi 默认 `docs/guazi-flow/` |
| Stage SKILLs | `stages/goal-*` | guazi-flow-* + 本仓 SKILL |

### S.3 对外 API（normative）

| 入口 | 用途 |
|------|------|
| `$REVIEW_KERNEL_HOME/bin/run-review-chain.sh --task-dir …` | 完整链 |
| `python3 $REVIEW_KERNEL_HOME/kernel/review/cli.py run …` | CLI 快路径 |
| Schema 校验 | `@goal/review-schema@1.x` 路径或 env |

### S.4 Q5 退化（双 fork + 共享 schema）

- 实现可 fork：`shared/review-kernel` 主包 + `guazi-flow-goal/vendor/review-kernel`（仅当抽取阻塞）
- **schema 禁止分叉 major**：`shared/review-schema/` 为 SSOT；两实现同 major

---

## Part T — goal-pipeline 剥离义务（normative）

完整清单：[two-pipeline-bidirectional-coupling-inventory.md](two-pipeline-bidirectional-coupling-inventory.md) §2 + 宪章 §2。

**验收（实现轨）：**

```bash
# goal-pipeline 生产路径零 guazi（夹具删除后）
rg -l 'guazi' goal-pipeline --glob '!fixtures/**' --glob '!**/archive/**' 
# 期望：0 或仅 migration 历史文档（若保留 references/archive/）
```

**删除类：** `gate-guazi-flow-stage.sh`、`gate-gf-stage.sh`、`gf-stage-driver.sh`、`fixtures/guazi-*`、`guazi_flow_contract_enrich.py`、`platform_review_adapter*`、`issues_gf` / dual merge（goal 侧）

---

## Part U — guazi-flow-goal 独立义务（normative）

1. **SKILL.md** 改写：不再「加载 goal-pipeline」；改为加载 `guazi-gate` + `REVIEW_KERNEL_HOME`
2. **fork** @ `9910d79`：`guazi-gate-stage.sh`、guazi gate-lib 分支、`fixtures/guazi-gate/`（自 `guazi-adapter-gate`）
3. **install**：`guazi-install.sh` → `~/.guazi-flow/`
4. **evals**：删除 `path: ../goal-pipeline` 硬依赖；改为 review-kernel + guazi 自洽夹具
5. **禁止** `~/.goal-pipeline/state/scripts/` Pre-flight

---

## Part V — 业务仓迁移 playbook 纲要

### V.1 适用对象

使用 `/guazi-flow-goal` 或 `gate-guazi-flow-stage.sh` 的业务仓（如瓜子 monorepo）。

### V.2 迁移步骤（顺序）

| 步 | 动作 | 验收 |
|----|------|------|
| 1 | Pin goal 仓 tag **v1.4.0**（或实现收口 SHA） | `git describe` |
| 2 | 运行 **guazi-install.sh**（新）部署 `~/.guazi-flow/` + `~/.goal-services/review-kernel/` | `test -x ~/.guazi-flow/state/scripts/guazi-gate-stage.sh` |
| 3 | 更新 CI / 本地脚本：`GATE=~/.guazi-flow/...`；**删除** `gate-guazi-flow-stage` 引用 | grep 无 `goal-pipeline/state/scripts` |
| 4 | `REVIEW_KERNEL_HOME` 写入 env 或 `.env.local` | chain smoke 一条 |
| 5 | 跑 guazi 夹具套件（guazi 仓 CI） | exit 0 |
| 6 | 旧任务 `state.json`：可选 `guazi-migrate-state.sh`（P2） | 文档即可 |

### V.3 回滚

- 业务仓 pin **frozen `9910d79`** goal 仓 + 旧 install 文档（**goal 不提供运行时桥**）
- 回滚不依赖 goal main 恢复 guazi adapter

### V.4 沟通

- Breaking：v1.4 发布说明列「guazi 须独立 install」
- 不支持：goal-pipeline v1.4+ 上继续 `gate-guazi-flow-stage.sh`

---

## Part W — 建议实现地图拆分（子 effort 名称）

**建议新开实现地图：** `Wayfinder: goal-pipeline v1.4 双管线完全独立实现`

| 子票 ID | 标题 | 优先级 | 依赖 |
|---------|------|--------|------|
| V14-1 | 抽出 `shared/review-kernel` + `shared/review-schema` + install | P0 | — |
| V14-2 | goal-pipeline 删光 guazi（gate 核心、gate-lib、夹具） | P0 | V14-1 |
| V14-3 | goal-pipeline 改接 `REVIEW_KERNEL_HOME` | P0 | V14-1 |
| V14-4 | guazi fork gate @ `9910d79` + `guazi-install.sh` | P0 | V14-1 |
| V14-5 | guazi SKILL / refs 去 goal-pipeline 依赖 | P0 | V14-4 |
| V14-6 | guazi 夹具迁仓 + CI | P1 | V14-4 |
| V14-7 | goal / guazi eval 与 writing-great-skills 审计 | P1 | #75 |
| V14-8 | gate sweep + PHASE-7 收口 | P0 | V14-2–6 |

**建议顺序：** V14-1 → (V14-2 ∥ V14-4) → V14-3 ∥ V14-5 → V14-6 → V14-7 → V14-8

**成功标准：** `goal-gate/run-all-gate-tests.sh` exit 0；guazi 套件 exit 0；宪章验收 rg 通过；#75 skill 审计 pass。

---

## Part X — 与 v1.3 / Matt workflow 关系

- **保留：** v1.3 Part P（`workflow_profile`、`engineering_pack` v2、`goal_lite`）— **仅 goal-pipeline**
- **不变：** Wayfinder out-of-band；R1–R4 硬不变量（goal 侧）
- **guazi：** Matt pack 不适用除非 guazi 显式 fork；本 spec 不约束 guazi-flow-* 业务 skill 内容

---

## Reject（v1.4）

- goal-pipeline 内任何 guazi compat（含 DEPRECATED 窗）
- guazi-flow-goal 调用 goal-pipeline scripts
- review schema 双 major 漂移（Q5 reject B）
- 为等 review-kernel 阻塞 guazi 独立（Q5 reject A）

---

## Changelog

| Date | Version | Action |
|------|---------|--------|
| 2026-08-03 | v1.4.0 | **#74 HITL 全采纳** — Part R–W；取代 v1.3 O.4 adapter 模型 |
| 2026-08-02 | v1.3.0 | [#53](https://github.com/sophiezel/goal/issues/53) 规划轨 |

---

*v1.4 extends v1.3; two-pipeline zero coupling; review-kernel shared service only.*
