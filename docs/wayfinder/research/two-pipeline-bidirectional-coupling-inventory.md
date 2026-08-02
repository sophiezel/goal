# goal-pipeline ↔ guazi-flow-goal 双向耦合面盘点（post-v1.3）

**Closes:** [GitHub #71](https://github.com/sophiezel/goal/issues/71)  
**Map:** [#70](https://github.com/sophiezel/goal/issues/70)  
**Baseline:** `main` @ `9910d79`（v1.3 合入）  
**方法：** 全仓 `guazi` / `goal-pipeline` 检索 + 入口脚本人工读码（2026-08-03）

---

## 1. 结论摘要

| 方向 | 生产代码耦合（不含夹具/历史） | 默认路径影响 |
|------|------------------------------|--------------|
| **goal-pipeline → guazi** | ~35 脚本/内核/契约项 + 3 套夹具目录 | 默认 `goal` 模式已干净；**adapter 层仍内嵌** |
| **guazi-flow-goal → goal-pipeline** | **硬依赖**（SKILL 必读、eval、kernel/gate/chain 路径） | guazi 无法脱离 goal-pipeline 运行 |
| **可抽取公共服务** | 审核 kernel（`kernel/review/*` + chain + B schemas）为主；gate-lib **语义**次之 | 两管线若共用，须独立包 + 清晰 semver |

**规模：** `goal-pipeline/` 约 **400+** 文件含 `guazi` 字符串；其中 **~70%** 为 `fixtures/guazi-adapter-gate/`、`fixtures/guazi-flow-gate/` 及 `goal-gate` 内 guazi 样本。

---

## 2. goal-pipeline → guazi（须从 goal-pipeline 剥离）

### P0 — 入口与 adapter（阻塞「零 guazi 仓内」）

| ID | 路径 / 符号 | 现状 | 目标态候选 |
|----|-------------|------|------------|
| G→P0-01 | `scripts/gate-guazi-flow-stage.sh` | compat wrapper → `gate-goal-stage.sh --mode guazi` | **删除或迁出**至 guazi-flow-goal |
| G→P0-02 | `scripts/gate-gf-stage.sh` | guazi 薄 gate | 迁出 |
| G→P0-03 | `scripts/gf-stage-driver.sh` | guazi 专用 driver | 迁出 |
| G→P0-04 | `scripts/gate-goal-stage.sh` | `--mode guazi` 分支 | **删除 guazi 分支** |
| G→P0-05 | `scripts/goal-stage-driver.sh` | `pipeline_track=compatibility\|guazi` | 删除 guazi 默认映射 |
| G→P0-06 | `scripts/goal-advance-stage.sh` | guazi skill / gate 名 | 仅 goal 叙事 |
| G→P0-07 | `scripts/goal-pipeline-kernel.sh` | `pipeline_track: compatibility` 默认 | 仅 `evolution` / goal |
| G→P0-08 | `kernel/review/merge.py` | `issues_gf[]` dual merge | 迁出或删字段 |
| G→P0-09 | `scripts/review_track.py` | `dual` → guazi-flow-review | 迁出至 guazi |
| G→P0-10 | `scripts/guazi_flow_contract_enrich.py` | guazi index enrich | 迁出 |
| G→P0-11 | `scripts/platform_review_adapter*.py` | guazi rubric 注入 | 迁出 |
| G→P0-12 | `references/guazi-flow-artifact-schema/` | fallback schema | 删除 fallback；guazi 自持副本 |

### P1 — schema / 文档 / 叙事

| ID | 路径 | 说明 |
|----|------|------|
| G→P1-01 | `SKILL.md` | Guazi adapter appendix、`pipeline_track=guazi` |
| G→P1-02 | `references/dual-track-contract.md` | dual 规格 | 迁出或 archive |
| G→P1-03 | `references/profile-contract-adapters.md` | adapter 模式 | 缩减为 goal-only |
| G→P1-04 | `schemas/review-*.schema.json` | `guazi_flow_rubric` optional 字段 | goal 侧删；guazi 或 shared 保留 |
| G→P1-05 | `stages/goal-review/SKILL.md` | dual / guazi-flow-review 指针 | goal single-track only |
| G→P1-06 | `scripts/goal-pipeline-recover.sh` | `--mode guazi` 恢复路径 | 删 guazi 分支 |
| G→P1-07 | `scripts/sync-install-repo.sh` / `deploy-skills.sh` | guazi consumer 分轨未完成 | 仅 goal consumer |

### P2 — 夹具（须迁出或删）

| 目录 | 文件量级 | 说明 |
|------|----------|------|
| `fixtures/guazi-adapter-gate/` | ~173 | v1.3 从 guazi-flow-gate 拆出；**应整体迁至 guazi-flow-goal** |
| `fixtures/guazi-flow-gate/` | 遗留 | 历史套件；合并进 guazi 仓或删除 |
| `fixtures/goal-gate/` 内 guazi 样本 | 部分 | 清理 guazi 命名样本 |

---

## 3. guazi-flow-goal → goal-pipeline（须断开或改为公共服务）

### P0 — 编排硬依赖

| ID | 引用 | 耦合类型 |
|----|------|----------|
| P→G0-01 | `SKILL.md` L3–7 | **「加载 goal-pipeline 管线引擎」** — 编排前提 |
| P→G0-02 | `evals/eval.yaml` | `path: ../goal-pipeline` **硬依赖** |
| P→G0-03 | `references/guazi-flow-integration.md` | 调用 `gate-guazi-flow-stage.sh`、`goal-run-review-chain.sh`、`goal-pipeline-kernel` |
| P→G0-04 | `references/bridge-contract.md` | goal state 基础字段、降级叙事绑定 goal-pipeline |
| P→G0-05 | `~/.goal-pipeline/state/scripts/` | Pre-flight **必须**部署 goal-pipeline scripts |
| P→G0-06 | `goal-stage-driver.sh` / `goal-advance-stage.sh` | 进化轨与兼容轨共用 goal 脚本 |
| P→G0-07 | `goal-run-review-chain.sh` + `kernel/review` | 独立审核 **实现在 goal-pipeline 树内** |
| P→G0-08 | `resolve-artifact-paths.py` 等 | handoff/Tier-R 路径 SSOT 在 goal-pipeline |
| P→G0-09 | `references/guazi-flow-state-schema.md` | 扩展 `guazi_flow_stages` 挂 goal gate 元数据 |
| P→G0-10 | `references/artifact-tier-policy.md` | Tier-R 路径 `~/.goal-pipeline/state/...` |

### P1 — 文档指针（易改，但证明概念未独立）

| 路径 | 指向 goal-pipeline 的只读引用数（约） |
|------|--------------------------------------|
| `guazi-flow-goal/SKILL.md` | 62 处 `goal-pipeline` |
| `references/task-tier-matrix.md` | 转发 goal-pipeline SSOT |
| `references/stage-handoff-contract.md` | handoff 形状来自 goal |
| eval cases | 降级叙事假设「纯 goal-pipeline」 |

---

## 4. 可抽取为公共服务（两管线潜在共用）

依据 [#39 generic-services](../generic-services-inventory-phase5.md) 与 v1.3 实现态：

| 优先级 | 服务面 | 当前位置 | 抽取难度 | 备注 |
|--------|--------|----------|----------|------|
| **P0** | 独立审核 loop | `kernel/review/*`、`goal-run-review-chain.sh`、review B schemas | 中 | 用户首选共用；须管线无关 I/O |
| **P1** | Gate-lib **语义**（plan/implement/review/quality） | `scripts/gate-lib/*.sh` | 高 | guazi index 仪式与 goal_lite 分叉大 |
| **P1** | Handoff / artifact path resolver | `resolve-artifact-paths.py`、`handoff_path_resolver.py` | 中 | state 形状可共享；task_docs_root 各管线配置 |
| **P2** | Timing / doctor / failure-codes | `scripts/*` + `references/failure-codes.json` | 低–中 | 可各复制一份，共用收益较小 |
| **不共用** | Stage SKILL 叙事、engineering_pack、guazi index 规则 | 各管线目录 | — | 保持独立 |

**若审核 loop 无法共用：** guazi 可复制 `kernel/review` + chain（双 fork），schema 须各自 semver，合流成本在 #75 writing-great-skills 门槛定义。

---

## 5. 雾区 → #72 待裁决决策（索引）

| 雾区（地图 #70） | 依赖事实 | 裁决票 |
|------------------|----------|--------|
| adapter 迁出/废弃 | §2 P0 | #72 Q1 |
| guazi 自建 gate/chain vs 仅共享审核包 | §3–§4 | #72 Q2 |
| `~/.goal-pipeline/` vs guazi state home | §3 P→G0-10 | #72 Q3 |
| install/deploy/CI + compat 窗 | §2 G→P1-07 | #72 Q4 |
| 业务仓迁移 playbook | 实现后 | #74 或单独 task 票 |
| 审核双 fork semver | §4 | #72 Q5 |
| 实现地图拆分 | 宪章后 | #74 产出 |

---

## 6. 与 v1.3 inventory（#56）差异

| 项 | #56 / v1.3 | 本盘点（#70 目标） |
|----|------------|-------------------|
| adapter | **保留在 goal-pipeline**（`--mode guazi`） | **须迁出或删除** |
| guazi-flow-goal | 不改造 | **须断开对 goal-pipeline 的硬依赖** |
| review kernel | goal-pipeline owner | **提升为可选公共服务** |
| 夹具 | `guazi-adapter-gate` opt-in CI | **迁至 guazi 仓** |
