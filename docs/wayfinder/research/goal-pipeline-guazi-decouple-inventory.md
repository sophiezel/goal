# goal-pipeline 与 guazi-flow-* 耦合面审计（post-v1.2）

**Closes:** [GitHub #56](https://github.com/sophiezel/goal/issues/56)  
**Map:** [#53](https://github.com/sophiezel/goal/issues/53)  
**Baseline:** `main` @ v1.2 合入（`20e51ac`）· [#55 ratification](./goal-pipeline-decouple-matt-ratification.md) C1  
**审计方法：** 全仓 `goal-pipeline/**` 对 `guazi-flow`、`guazi_flow`、`docs/guazi-flow` 检索 + 关键入口脚本人工读码（2026-08-02）

---

## 1. 结论摘要

| 分类 | 条目约数 | 默认路径影响 |
|------|----------|--------------|
| **必须剥离** | 28 项（P0: 12 / P1: 10 / P2: 6） | goal-pipeline **默认**执行时不应隐式依赖 guazi 命名/上游 skill |
| **adapter 保留** | 18 项 | `--mode guazi`、dual review、guazi-flow-goal 编排显式 opt-in |
| **文档/历史仅** | 14 项 | 迁移说明、Fork 记录、已关闭 Phase 研究；可延后重命名 |

**命中规模：** `goal-pipeline/` 内 **~170 文件** 含 guazi 相关字符串；其中 **~60%** 为 `fixtures/guazi-flow-gate/` 夹具与测试（应拆分而非删除）。

---

## 2. 必须剥离（goal-pipeline 默认路径）

### P0 — 入口与编排（阻塞「零 guazi 默认」）

| ID | 路径 / 符号 | 现状 | 目标态 | 建议实现票 |
|----|-------------|------|--------|------------|
| D-01 | `scripts/gate-guazi-flow-stage.sh` | 主 gate 入口；注释写 guazi-flow-goal | `gate-goal-stage.sh`（或等价）；默认 `--mode goal` | **Impl-1** gate 重命名 + symlink 兼容窗 |
| D-02 | `gates/{plan,implement,review,smoke}-*.sh` | `exec gate-guazi-flow-stage.sh` | 指向新 gate 名 | Impl-1 |
| D-03 | `scripts/goal-stage-driver.sh` | `STAGE_SKILL_COMPAT` 默认 `guazi-flow-plan/implement/review` | 默认 `goal-plan` / `goal-implement` / `goal-review`；guazi 名仅 `--mode guazi` | **Impl-2** driver + advance 去 guazi 默认 |
| D-04 | `scripts/goal-advance-stage.sh` | `required_commands` 大量 `guazi-flow-*`、`gate-guazi-flow-stage.sh` | 默认 WO 用 goal stage 名；guazi 串仅在 mode=guazi | Impl-2 |
| D-05 | `scripts/goal-pipeline-kernel.sh` | 引用 gate-guazi-flow-stage | 同 D-01 | Impl-1 |
| D-06 | `stages/goal-plan/SKILL.md` | Fork 自 `guazi-flow-plan`；必读上游 | SSOT 本仓；移除上游必读 | **Impl-3** stage skill 去 Fork（5 文件） |
| D-07 | `stages/goal-implement/SKILL.md` | 同上 → guazi-flow-implement | 同上 | Impl-3 |
| D-08 | `stages/goal-review/SKILL.md` | 同上 → guazi-flow-review | 同上；保留 dual 文档指针 | Impl-3 |
| D-09 | `stages/goal-complete/SKILL.md` | 同上 → guazi-flow-complete | 同上 | Impl-3 |
| D-10 | `SKILL.md`（根） | 多处 guazi-flow-goal 叙事为默认 | goal-pipeline 一等；guazi 为 adapter 附录 | **Impl-4** 根 SKILL + 文档默认叙事 |
| D-11 | `skills/goal-engineering/grill/SKILL.md` | 写入 `docs/guazi-flow/<task>/index.md` | `docs/goal/<task>/` 或 profile `task_docs_root` | **Impl-5** pack v2 + 任务目录抽象 |
| D-12 | `scripts/resolve-artifact-paths.py` | 默认 task 路径含 `docs/guazi-flow` | profile 解析 `task_dir`；默认 `docs/goal` | Impl-5 |

### P1 — schema / 规则 / 内核默认

| ID | 路径 | 现状 | 目标态 | 建议实现票 |
|----|------|------|--------|------------|
| D-13 | `references/guazi-flow-artifact-schema/` | 目录名 + `plan-index-rules.json` 映射 guazi-flow-* skill | 重命名 `goal-artifact-schema/`；skill 映射表分 default/guazi | **Impl-6** schema 目录重命名 |
| D-14 | `scripts/resolve_plan_index_rules.py` | 硬编码 schema 路径 | 读新目录 + profile | Impl-6 |
| D-15 | `references/interview-protocol.md` | Phase 1 绑定 guazi index 段 | Matt grill + 可选轻量 goal brief | Impl-5 |
| D-16 | `references/plan-before-code.md` | guazi-flow-plan 步骤 | goal-plan 步骤 | Impl-4 |
| D-17 | `references/handoff-path-resolution.md` | guazi-flow task 示例 | 双示例 default + guazi | Impl-4 |
| D-18 | `references/fork-manifest.yaml` | 记录 Fork 关系 | 移至 `references/archive/` 或标 deprecated | P2 文档 |
| D-19 | `kernel/profile/engineering_pack.py` | 仅 v1.2 四枚举 | 扩展 + `workflow_profile` 解析（#57 草案） | **Impl-7** profile 字段 v1.3 |
| D-20 | `scripts/gate-lib/plan.sh` | index / fe-argus guazi 仪式 | `plan_profile: goal_lite` 跳过 index 硬依赖 | Impl-5 |
| D-21 | `scripts/gate-lib/implement.sh` | guazi-flow-implement 话术 | goal-implement | Impl-3 |
| D-22 | `scripts/gate-lib/complete.sh` | postmerge guazi 路径 | profile 条件 postmerge | Impl-2 |

### P2 — 夹具与测试默认叙事

| ID | 路径 | 现状 | 目标态 | 建议实现票 |
|----|------|------|--------|------------|
| D-23 | `scripts/fixtures/guazi-flow-gate/` | 全量默认夹具目录名 | 拆为 `fixtures/goal-gate/` + `fixtures/guazi-adapter-gate/` | **Impl-8** 夹具拆分 |
| D-24 | `scripts/fixtures/guazi-flow-gate/run-gate-tests.sh` | 路径硬编码 | 双套件入口 | Impl-8 |
| D-25 | `scripts/deploy-skills.sh` | 同步 guazi-flow-* | 仅 goal stages + engineering pack | Impl-9 |
| D-26 | `scripts/sync-install-repo.sh` | guazi-flow 依赖检查 | 分 consumer 安装 | Impl-9 |
| D-27 | `evals/cases/xs-review-single-track.yaml` | 文案 guazi-flow-review | goal-review only 叙事 | Impl-4 |
| D-28 | `references/guazi-flow-artifact-schema/README.md` | guazi 来源声明 | goal SSOT + guazi delta 附录 | Impl-6 |

---

## 3. adapter 保留（显式 opt-in）

| ID | 路径 / 机制 | 保留理由 | 挂载方式 |
|----|-------------|----------|----------|
| A-01 | `gate-guazi-flow-stage.sh --mode guazi` | guazi-flow-goal 业务仓 | 兼容别名 → 新 gate；mode 分支保留 |
| A-02 | `scripts/gf-stage-driver.sh` | guazi 专用 driver | `consumer: guazi` profile |
| A-03 | `scripts/gate-gf-stage.sh` | guazi 薄 gate | 同上 |
| A-04 | `scripts/review_track.py` | `dual` → `guazi-flow-review` | env/state `review_track=dual` |
| A-05 | `kernel/review/merge.py` | `issues_gf[]` | dual track only |
| A-06 | `schemas/review-*.schema.json` | `guazi_flow_rubric` 字段 | optional；single-track 不填 |
| A-07 | `scripts/guazi_flow_contract_enrich.py` | guazi index 契约 enrich | `--mode guazi` plan post |
| A-08 | `scripts/platform_review_adapter_core.py` | guazi rubric 注入 | dual / guazi consumer |
| A-09 | `scripts/resolve_verification_commands.py` | 查找 `guazi-flow-core` | guazi profile 验证命令 |
| A-10 | `scripts/resolve_postmerge_policy.py` | guazi postmerge | profile `postmerge: required` |
| A-11 | `references/dual-track-contract.md` | dual 规格 | guazi 管线文档 |
| A-12 | `references/profile-contract-adapters.md` | adapter 模式 | 扩展为 v1.3 SSOT |
| A-13 | `quality_plane_check.py` | `guazi_flow_stages` state | guazi state.json 形状 |
| A-14 | `efficiency_plane_check.py` | guazi stage 键 | 同上 |
| A-15 | `data_plane_check.py` | guazi task 路径校验 | mode=guazi |
| A-16 | `kernel/metrics/delivery_report.py` | guazi_flow_task 字段 | 向后兼容 state |
| A-17 | `scripts/refresh-handoffs-after-index.sh` | index 刷新（guazi index） | guazi / index-heavy profile |
| A-18 | `references/postmerge-complete-evidence.md` | guazi postmerge 证据 | guazi consumer only |

---

## 4. 文档 / 历史仅（可延后）

| 路径 | 说明 |
|------|------|
| `references/migration-compat.md` | v1.1→v1.2 迁移；v1.3 追加节即可 |
| `references/fork-sync-policy.md` | Fork 同步政策；解耦后标 legacy |
| `scripts/fixtures/guazi-flow-gate/V1.2-SWEEP.md` | v1.2 扫尾边界；历史快照 |
| `references/rca-plan-closeout-checklist.md` | guazi 实战 checklist |
| `references/multi-goal-orchestration.md` | guazi 多 goal 叙事 |
| `references/auto-continue-policy.md` | guazi-flow-goal 自动继续 |
| `references/unified-review-prompt.md` | 含 guazi 字段说明 |
| `references/goal-core/README.md` | guazi-flow-core 子集说明 |
| `references/issue-board-enhancement-draft.md` | 草案 |
| `references/release-channel.md` | 渠道说明 |
| `references/wall-clock-xs-replay.md` | 回放 guazi 夹具路径 |
| `references/p2-eval-runbook.md` | 指向 guazi-flow-gate 测试 |
| `stages/README.md` | Fork 说明 |
| `kernel/tests/test_guazi_flow_contract_enrich.py` | adapter 单测；保留 |

---

## 5. 建议实现地图子票（本图不实现）

| 票粒度 | 标题 | 范围 | 依赖 |
|--------|------|------|------|
| **Impl-1** | Gate 重命名与兼容窗 | D-01, D-02, D-05 | — |
| **Impl-2** | Driver / advance 默认 goal 叙事 | D-03, D-04, D-22 | Impl-1 |
| **Impl-3** | Stage SKILL 去 Fork（5 stages） | D-06–D-09, D-21 | Impl-1 |
| **Impl-4** | 根 SKILL + references 默认叙事 | D-10, D-16–D-17, D-27 | Impl-3 |
| **Impl-5** | 任务目录 + goal_lite plan 路径 | D-11, D-12, D-15, D-20 | Impl-3 |
| **Impl-6** | Artifact schema 重命名 | D-13, D-14, D-28 | Impl-1 |
| **Impl-7** | profile：`engineering_pack` + `workflow_profile` | D-19 + #57 原型 | Impl-3 |
| **Impl-8** | 夹具拆分 goal-gate / guazi-adapter | D-23, D-24 | Impl-1 |
| **Impl-9** | 安装/部署脚本分 consumer | D-25, D-26 | Impl-1, Impl-8 |

**建议顺序：** Impl-1 → Impl-2 ∥ Impl-6 → Impl-3 → Impl-4 ∥ Impl-5 → Impl-7 → Impl-8 → Impl-9

---

## 6. 验收（#56）

- [x] 三类分类表 + 文件路径
- [x] P0/P1/P2 优先级
- [x] 建议实现票粒度（9 张）
- [x] 未改生产代码
