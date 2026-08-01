# goal 仓跨平面 Generic Services 清单与边界（Phase-5）

**Closes:** [GitHub #39](https://github.com/sophiezel/goal/issues/39)  
**Map:** [Phase-5 #36](https://github.com/sophiezel/goal/issues/36)  
**Ratification:** [#40 final B1–B9](https://github.com/sophiezel/goal/issues/40#issuecomment-5152145886) · **goal-pipeline breaking-first**（非 guazi-compat 盘点）  
**Upstream:** [guazi-flow-goal-node-io-audit-phase5.md](./guazi-flow-goal-node-io-audit-phase5.md) §3 · [goal-pipeline-external-patterns-gap-phase5.md](./goal-pipeline-external-patterns-gap-phase5.md) §5 Part J  
**Runtime planes:** [goal-runtime.md](../../architecture/goal-runtime.md)

---

## 1. 范围与裁决原则

| 原则 | 说明 |
|------|------|
| **消费者视角** | 以 **goal-pipeline** 默认 profile（single-track review、quality-only advance）为主；guazi-flow-goal = 独立管线，仅标注 wrapper/可选 dual |
| **Kernel vs wrapper** | 机读工件与 gate 依赖 = **kernel 契约**；Agent SKILL / 编排话术 = **wrapper**（不得自填 `review-run` / `review-unified`） |
| **规格动作** | **normative** = v1.2/Part J 须写清；**P2** = 文档或实现图可后移；**impl-only** = 行为已有、规格不扩义务 |
| **#41 边界** | 本表 **不** ratify SLO 数字、`sla_breach` 阈值、timing substep 默认集、leakage 量化口径 — 见 §6 |

---

## 2. 一等公民：独立审核 Kernel（B schema + chain SSOT）

依据 #40 **B5/B6** 与 audit §3.1；goal-pipeline **默认** 仅 `goal-review` wrapper + 本 kernel（**B8** 拒 dual 为默认）。

### 2.1 编排 SSOT

| 服务 | 平面 | 入口脚本 / API | I/O 工件 | goal-pipeline owner | kernel vs wrapper | Phase-5 spec |
|------|------|----------------|----------|---------------------|-------------------|--------------|
| **Review chain（原子链）** | quality | `goal-pipeline/scripts/goal-run-review-chain.sh` | 读：`state.json`、handoff 链、index；写：`handoff/review-packet.json`、`evidence/review-run.json`、`evidence/review-unified.json`、`evidence/review-fix-input.json` | `goal-pipeline` scripts + `kernel/review` | **kernel** | **normative** — 编排 SSOT（B5）；Stage Exit 须跑链 + `gate --post review` |
| **Independent LLM invoke** | quality | `run-independent-review.sh`；快路径 `kernel/review/cli.py` `invoke` | 读 packet；写 `review-run.json`（provenance 必填） | `kernel/review`（Python）+ shell 薄封装 | **kernel** | **normative** — provenance；cross-provider 由 channel guard 强制 |
| **Full run（invoke+merge）** | quality | `kernel/review/cli.py` `run` | 同上 + merge 内嵌 → fix-input | `kernel/review` | **kernel** | **normative** — CLI 存在时 chain 可跳过 shell merge 步（语义等价，B5 delta） |
| **Packet 组装** | quality | `assemble-review-packet.sh` | 读 index、handoff、diff、rubric；写 `review-packet.json` | scripts | **kernel** | **normative** — PKT-01..04 与 preflight 对齐 |
| **Packet preflight** | quality | `review_packet_preflight.py` | 读 packet + `verification-oracle.json` | scripts | **kernel** | **normative** — review pre + chain 内 |
| **Channel policy** | quality | `review-channel-guard.py`；`review_channel_detect_cache.py` | config / detect cache → degraded JSON 或 hard fail | scripts | **kernel** | **normative** — 0 channel → `separation=degraded`（B4 语义 normative，数字 #41） |
| **Unified merge → fix-input** | quality | `merge-review-issues.sh`；`kernel/review/merge.py` | 读 unified（+ 可选 `issues_gf`）；写 `review-fix-input.json` | `kernel/review` + scripts | **kernel** | **normative** — 修复环 SSOT（B6）；禁止手改 unified / 解析 review.md 分流 |
| **Review gate 壳** | quality | `gate-lib/review.sh`（经 `gate-guazi-flow-stage.sh`） | pre/post 消费上述工件 + `handoff/review.json` | scripts `gate-lib` | **kernel**（gate 消费契约） | **normative** — `review_not_pass`、`review_forged`、`review_degraded_as_pass` 等 |
| **Deterministic review aux** | quality | `verify-review.sh`；`review_strict_ux.py`；`review_packet_shard.py` | 读 diff/handoff；辅助 deterministic 层 | scripts | **kernel** 辅助（非 LLM） | **impl-only** — 与 UVO 重叠裁减待 P2（catalog） |
| **Schemas（B 级）** | data/quality | `schemas/review-run.schema.json`、`review-unified.schema.json`、`review-fix-input.schema.json`；`references/review-packet-schema.md` | 校验 chain 产出 | `goal-pipeline/schemas` | **kernel 契约面** | **normative** — Part J **add**（#38 §5.3） |
| **goal-review SKILL** | control | `stages/goal-review/SKILL.md` | 消费 kernel 工件；Stage Exit 命令列表 | `goal-pipeline` stage skill | **wrapper** | **normative** — goal-pipeline **默认唯一** review Agent（B8） |
| **guazi-flow-review SKILL** | control | 仓外 lazy load | `issues_gf[]` → merge | guazi-flow-goal | **wrapper**（dual only） | **reject** goal-pipeline 默认；guazi 管线 **impl-only** |

### 2.2 implement ↔ review 标准契约（goal-pipeline）

| 契约面 | 内容 | 规格动作 |
|--------|------|----------|
| Packet | `assemble` + preflight 后 `review-packet.json` | normative |
| 独立模型输出 | 仅 kernel 写 `review-run.json` / `review-unified.json` | normative |
| 修复回流 | `review-fix-input.json` → implement 子环；`noop_fix` / stagnant / rounds cap | normative（B6） |
| 契约漂移 | `refresh-handoffs-after-index` + `contract_stale` | normative（B7） |
| Cross-provider | channel guard + NEVER（同 provider → 降级） | normative |
| Dual + gf-review | 并行 Agent 回合 + merge channel | guazi-only（B8） |

### 2.3 非 goal-pipeline 流程接入（可扩展性）

| 接入方式 | 稳定面 | 限制 |
|----------|--------|------|
| **CLI** | `python3 …/kernel/review/cli.py run --task-dir …` | 须自备 task_dir + handoff 链与 index 契约 |
| **Chain only** | `goal-run-review-chain.sh --task-dir …` | 同左；仍须本地 `gate --post review` 若要走 complete |
| **Adapter** | `platform-review-adapter.sh` / `platform_review_adapter_core.py` | Host 可选；不替代 kernel 工件 |
| **Semver API v1** | — | **defer P2**（#40 轴 3） |

---

## 3. 跨平面 Generic Services 总表

**列说明：** `goal-pipeline owner` = 维护/契约主责；`impl-only` 表示实现已存在、Part J 不新增对外义务。

| 服务名 | 平面 | 入口脚本 | I/O 工件 | goal-pipeline owner | kernel vs wrapper | Phase-5 spec |
|--------|------|----------|----------|---------------------|-------------------|--------------|
| **Pipeline kernel（控制 CLI）** | control | `goal-pipeline-kernel.sh` | `state.json`、FrozenWorkOrder JSON | goal-pipeline | **kernel** facade | **normative** — Turn Protocol（goal-runtime） |
| **Stage driver** | control | `goal-stage-driver.sh` | WO：`mandatory_commands`、`skill_to_load`、`code_writes_allowed` | scripts | kernel 内部 | **impl-only** — 经 kernel 暴露 |
| **Advance stage** | control | `goal-advance-stage.sh` | 更新 `state.json` stage；认 quality 非 smoke（B1） | scripts | kernel 内部 | **normative**（B1 quality-only advance） |
| **Review track policy** | control | `review_track.py`；plan post 写 `state.review_policy` | `state.json` | scripts | kernel 策略 | **normative** — default **single**（B8） |
| **Artifact path resolver** | data | `resolve-artifact-paths.py` | Tier-R `handoff/`、`evidence/` 路径；`artifact_layout` | scripts | **kernel** | **normative** — 数据面 SSOT |
| **Handoff path resolver** | data | `handoff_path_resolver.py` | gate 消费 handoff 目录 | scripts | **kernel** 辅助 | **normative**（B7 级联 refresh 依赖） |
| **Refresh handoffs cascade** | data | `refresh-handoffs-after-index.sh`；`index_contract_hash.py` | 级联 refresh / demote handoff | scripts | **kernel** | **normative**（B7） |
| **Pipeline chain validate** | data | `validate-pipeline-chain.py` / `.sh` | handoff 链完整性 | scripts | **kernel** | **impl-only** |
| **Artifact migrate** | data | `migrate-artifacts.py`；doctor `--migrate-artifacts` | 布局迁移 | scripts | kernel 运维 | **P2** |
| **Handoff / state schemas** | data | `schemas/*.schema.json`；`references/goal-state-schema.md` | plan/implement/quality/review/complete JSON | goal-pipeline/schemas | **kernel 契约** | **normative** — stage handoff 与 Part J 对齐 |
| **Gate orchestrator** | quality | `gate-guazi-flow-stage.sh` | `--pre`/`--post`；fix-input 路径 | scripts | **kernel** | **normative** |
| **Stage gate libs** | quality | `gate-lib/plan.sh`、`implement.sh`、`quality.sh`、`review.sh`、`complete.sh` | 各 stage handoff + `evidence/*-gate-fix-input.json` | scripts | **kernel** | **normative** — R1–R4 硬门禁 |
| **Legacy smoke gate** | quality | `gate-lib/smoke.sh`；`runtime-smoke.sh` | `handoff/smoke.json`（遗留） | scripts | kernel 遗留 | **normative deprecate**（B1 — quality only） |
| **Plan before code** | quality | `assert_plan_before_code.py`；plan pre | plan handoff vs diff | scripts | kernel | **impl-only** |
| **Verification oracle（UVO）** | quality | `verification-oracle.sh`；`verification_oracle_core.py` | `evidence/verification-oracle.json` | scripts | **kernel** | **impl-only** |
| **Acceptance matrix ratchet** | quality | `acceptance-matrix-ratchet.py` | ratchet JSON | scripts | kernel | **impl-only**；矩阵漏出度量 **#41** |
| **Implement QC / IQ** | quality | `implement-qc-gate.py`；`contract-conformance-check.py` | IQ / contract evidence | scripts | kernel | **impl-only** |
| **Quality stage gate** | quality | `quality-gate.sh`；`goal_quality_e2e_policy.py` | `handoff/quality.json` | scripts | kernel | **normative**（B1 — 主 verify 轨） |
| **Quality plane check** | quality | `quality_plane_check.py` | complete 路径 delivery 护栏 | scripts | kernel | **normative** 语义；阈值 **#41** |
| **Data plane check** | data | `data_plane_check.py` | state/handoff hash policy | scripts | kernel | **impl-only** |
| **Delivery quality** | quality | `write-delivery-quality.sh`；`schemas/delivery-quality.schema.json` | `delivery-quality.json` | scripts | kernel | **impl-only**；leakage 字段 **#41** |
| **Contract enrich（guazi）** | data | `argus_enrich_plan.py`；`argus-enrich-plan.sh` | index 契约段 | scripts | guazi 可选 | **normative** WARN→BLOCK（B3） |
| **Postmerge policy** | quality | `resolve_postmerge_policy.py` | complete / quality profile | scripts | kernel 策略 | **impl-only** |
| **Failure codes** | quality | `references/failure-codes.json`；`failure-code-dictionary.md` | 全平面 exit 语义 | goal-pipeline/references | **kernel 契约** | **normative**；新码 Part J |
| **Four planes checklist** | control | `references/four-planes-checklist.json` | doctor 对照 | references | kernel | **impl-only** |
| **Pipeline timing record** | efficiency | `record-pipeline-timing.py` | `evidence/pipeline-timing.json` | scripts | **kernel** | **normative** — 全阶段 timing（B2）；substep 默认 **#41** |
| **Timing HTML report** | efficiency | `generate-pipeline-timing-report.sh`；`render-pipeline-timing-report.py`；`pipeline_timing_report_core.py` | HTML / 汇总 | scripts | kernel 报告 | **P2** dashboard |
| **Timing substep sync** | efficiency | `sync_timing_substeps.py` | timing JSON 子步 | scripts | kernel | **#41** — UVO/review substeps |
| **Efficiency plane check** | efficiency | `efficiency_plane_check.py` | timing / benchmark 护栏 | scripts | kernel | 语义 **#41** |
| **Postmortem / benchmark** | efficiency | `pipeline-postmortem.py`；`benchmark-pipeline-replay.sh`；`benchmark-ci.sh` | 度量模板 | scripts | kernel 运维 | **P2** |
| **Leak / W1/W2 bookkeeping** | efficiency | `leak-rate-panel.py`；`w1_leakage_bookkeeping.py`；`w2_matrix_bookkeeping.py` | delivery-quality / measure | scripts | kernel 度量 | **#41** |
| **Four planes doctor** | control | `four_planes_doctor.py` | 四平面体检输出 | scripts | **kernel** 对外诊断 | **impl-only** |
| **Pipeline doctor** | control | `goal-pipeline-doctor.sh` | infra + migrate 钩子 | scripts | kernel facade | **impl-only** |
| **Goal install / sync** | control | `goal-install.sh`；`sync-install-repo.sh`；`source-goal-install-paths.sh` | `~/.goal-pipeline/state/scripts` | scripts | 分发层 | **P2** — 非管线语义 |
| **Platform detect / review adapter** | control/quality | `detect-platform`；`platform-review-adapter.sh` | Host WO.capability | scripts | **adapter** | **impl-only** — Host 可选（goal-runtime） |
| **Recover / hooks** | control | `goal-pipeline-recover.sh`；`goal-pipeline-stop-hook.sh`；session-start-hook | state 恢复 | scripts | 运维 | **P2** |
| **Pure gates 降级路径** | control/efficiency | `gates/*.sh`（无 guazi index） | 同 gate-lib 语义 | scripts 遗留 | wrapper 路径 | **normative** — timing 对齐（B2 delta）；**impl-only** 路径等价性 |
| **Bridge state 文档** | data | `references/bridge-contract.md` vs 运行时 `~/.goal-pipeline/state/` | — | docs | — | **P2**（B9 doc-only） |

---

## 4. Ownership 汇总（kernel vs 管线 vs 文档）

| 层级 | 职责 | 代表资产 |
|------|------|----------|
| **Review kernel** | 独立审核机读契约 + chain + B schemas | `goal-run-review-chain.sh`、`kernel/review/*`、`review-*.schema.json` |
| **goal-pipeline（normative SSOT）** | 默认 profile、stage skills（goal-review）、SKILL.md、Part J 条目 | `goal-pipeline/SKILL.md`、`stages/goal-*` |
| **goal-pipeline scripts（实现 SSOT）** | gate、handoff、timing、doctor 脚本树 | `goal-pipeline/scripts/*` |
| **guazi-flow-goal** | 独立编排；可选 dual + `guazi-flow-review`；lazy guazi-flow-* | `guazi-flow-goal/SKILL.md`（**不**约束 goal-pipeline 默认） |
| **docs-only / P2** | 安装说明、bridge 路径措辞、semver review API | B9、goal-install 用户文档 |

---

## 5. 与 #38 Part J 候选交叉引用

| #38 §5 条目 | 本 inventory 落点 |
|-------------|-------------------|
| add — `stage_graph` / profile | §3 kernel + advance；非独立服务名 |
| add — `engineering_pack` grill/to-specs | Phase 1 软加载；**非** generic gate 服务 |
| add — Review kernel B + single default | §2 全表 |
| add — B1/B3/B7 normative | §3 smoke deprecate、contract enrich、refresh cascade |
| borrow — 简体 Matt pack | out-of-band / Phase 1；不在 §3 服务表 |
| reject — guazi parity / dual default | §2.1 guazi-flow-review 行 |
| defer P2 — Wayfinder ticket API、review semver | §2.3、§3 install/recover |

**一致性：** Part J 不应要求 guazi-compat 双轨服务为 goal-pipeline 默认消费者。

---

## 6. #41 边界（SLO / timing — 本票不闭合）

| 主题 | 本 inventory 提供 | #41 须 ratify |
|------|-------------------|---------------|
| **B4 degraded** | `separation=degraded`、0 channel、`review_degraded_as_pass` 语义锚点 | 数值阈值、complete 护栏量化、leakage 口径 |
| **Timing B2** | `record-pipeline-timing` 为效率 SSOT；全阶段名列表 | `sla_breach`、task_tier SLA、默认 `--substep`（UVO/review） |
| **Metrics** | `review-run.json` 字段、`pipeline-timing.json`、W1/W2 脚本存在 | 统一 SLO-Q 模型、面板契约 |
| **Smoke 遗留** | B1 deprecate 方向 | timing 中 `smoke` 阶段名是否删除 |

---

## 7. 结论

- **一等公民**独立审核：**goal-run-review-chain** + **kernel/review** + **review B schemas** 为 goal-pipeline normative 公共服务；`goal-review` = 默认 wrapper；`guazi-flow-review` = guazi 管线 wrapper。
- **跨平面** handoff resolver、gates、timing、doctor、failure-codes 已入表；goal-pipeline **breaking-first** 处置对齐 #40 B1–B9（非 guazi 历史 inventory）。
- **下游：** [#41](https://github.com/sophiezel/goal/issues/41) 读取 §2.1 工件与 §6；实现图从 Part J + 本表 **normative** 行拆票。

---

*Wayfinder research — 2026-08-01 — closes #39.*
