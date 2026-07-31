# Goal 五阶段全链路节点清单

> **SSOT 来源**：`docs/architecture/goal-runtime.md`、`goal-pipeline/SKILL.md`、`guazi-flow-goal/SKILL.md`、  
> `goal-pipeline/scripts/goal-pipeline-kernel.sh`、`gate-guazi-flow-stage.sh`、`goal-run-review-chain.sh`、  
> `goal-advance-stage.sh`、`goal-stage-driver.sh`、四平面 `*_plane_check.py` / `four_planes_doctor.py`。  
> **用途**：Wayfinder #2 — 交付质量与效率优化的节点级规格骨架。

**Ratified C1 裁剪原则（Phase-2 #1）：** 仅 **效率面** 节点可 skip（遗留 `gate stage smoke`、review `dual` track、`four_planes_doctor`、timing `substep`）。**不可** 因 lite 默认跳过：`quality_plane_check`、`IQ-10`、**UVO**、review preflight、`merge-review-issues`（`kernel.review.cli run` 内含 merge，与 shell chain 等价），除非 profile 显式降级 flag（如 `GOAL_ALLOW_LEGACY_SMOKE_STAGE=1`）。

**Phase-3b #13 C1 ratified（2026-08-01）：** [phase-3-hitl-ratified.md](phase-3-hitl-ratified.md) — lite **显式**降级表见下表（**非**质量面 skip）。

### Profile：lite | standard | strict

`lite` = `plan_profile: lite`（通常 XS/S）；`standard` = 默认 full index + hybrid Argus；`strict` = `quality` tier strict（review-first UX/L10 分层，见 Phase-2 C1）。

| 节点 / 策略 | lite | standard | strict |
|-------------|------|----------|--------|
| `acceptance-matrix-ratchet` | **不可 skip** | **不可 skip** | **不可 skip** |
| plan post Argus | **rule v1 only**（`argus_enrich_plan.py`；**无** fe-argus skill ②） | hybrid v2（规则 + 条件 fe-argus） | 同 standard |
| `gate stage smoke`（遗留直调） | **hard-disable**（默认拒绝；`GOAL_ALLOW_LEGACY_SMOKE_STAGE=1`） | 同左 | 同左 |
| `guazi-flow-review` dual track | **`review_track=single`** | XS/S 默认 single；M+ 可 dual | 同 standard |
| `four_planes_doctor` | 可选（meta） | 可选；Wave 推荐 | 可选；Wave 推荐 |
| timing `substep` | 可选 | 可选 | 可选 |
| `merge-review-issues` | **不可 skip** | **不可 skip** | **不可 skip** |
| `quality_plane_check`（complete） | **不可 skip** | **不可 skip** | **不可 skip** |
| PQ plan gate（PQ-01/02/05/07） | **不降级** | full PQ | full PQ |
| `implement-qc-gate` `--skip-test-lint` | 是（与 UVO 分工） | 是 | 是 |
| UVO / IQ-10 / review preflight | **不可 skip** | **不可 skip** | **不可 skip** |

---

## 阶段序（控制面真相）

`goal-advance-stage.sh` 对外五段：**plan → implement → quality → review → complete**（`next_stage=done` 当 verify/complete handoff 满足）。  
`gate-guazi-flow-stage.sh` 仍接受 **`smoke`** 阶段名（与 **quality** 并列实现），但 advance **不单独推进 smoke**（smoke 并入 quality 编排）。

Agent 回合协议：`kernel next` → 执行 `FrozenWorkOrder.mandatory_commands` → `kernel gate --post` → `kernel next` / `kernel complete`。

---

## 节点总表

| Node name | Stage | Plane | Inputs SSOT | Outputs | Gate script | Timing hooks | Necessity (can skip?) | Known failure codes |
|-----------|-------|-------|-------------|---------|-------------|--------------|----------------------|---------------------|
| `kernel init` | (pre-pipeline) | Control | `project_root`, `task_dir`, git `branch` | `~/.goal-pipeline/state/projects/<pid>/<branch>/<task>/state.json`, `artifacts/handoff|evidence` | — | — | No — 无 canonical state 则 data 面 SSOT 分裂 | `state_dir_creation_failed`, `state_json_unwritable`, `project_id_mismatch` |
| Phase 1 Pre-flight | goal_engineering | Control | `goal-pipeline-kernel.sh`, `gate-guazi-flow-stage.sh`, `failure-codes.json`, `four-planes-checklist.json`, artifact schema | `pre-flight: scripts=OK|MISSING` | — | — | No — `infra_missing` 阻断 Phase 2 | `infra_missing` |
| Phase 1 Interview / Goal 卡片 | goal_engineering | Control | `interview-protocol.md`, 用户 objective | 用户确认的 Goal 摘要字段（Allowed Files / Stop Conditions 等） | — | — | Fast-path 可压缩追问，**不可**整段跳过 state 创建 | — |
| Phase 1 `state.json` 初始化 | goal_engineering | Data | 确认后的 goal 元数据, `git rev-parse` | `state.json`（`project_id`, `guazi_flow_task`, `artifact_layout.split`） | — | — | No | `state_dir_creation_failed`, `state_json_unwritable`, `project_id_mismatch` |
| `kernel next` / `goal-stage-driver` | per-stage | Control | `state.json`, `goal-advance-stage` JSON | `FrozenWorkOrder`（`mandatory_commands`, `code_writes_allowed`, `skill_to_load`） | `goal-stage-driver.sh`（内部） | — | No — 旁路写代码不替代 WO | `wrong_stage`, `plan_code_order` |
| `assert-plan-before-code` | plan / implement-pre | Control | `state.json`, `handoff/plan.json`, git diff | JSON pass/block | `assert-plan-before-code.sh` / `assert_plan_before_code.py` | — | No — plan gate 前禁止 src | `plan_code_order` |
| `validate-state-path` | any (kernel next) | Data | `state.json`, `project_root` | exit 0/2 | `validate-state-path.sh` | — | No（kernel next 硬调） | `project_id_mismatch` |
| `resolve-artifact-paths` | all gates | Data | `task_dir`, `state.json`, `artifact_layout` | `HANDOFF_DIR`, `GOAL_EVIDENCE_DIR`, `REPO_EVIDENCE_DIR` | `resolve-artifact-paths.py` | — | No | `state_ambiguous`, `handoff_missing` |
| **plan gate --pre** | plan | Control | `index.md`（可无）, git tree | pass / BLOCK | `gate-guazi-flow-stage.sh` → `gate-lib/plan.sh` | `record-pipeline-timing` **start** (`stage=plan`) | No | `plan_code_order` |
| **guazi-flow-plan**（Agent） | plan | Control | `guazi-flow-plan/SKILL.md`, 需求输入 | `docs/guazi-flow/<task>/index.md`（Tier-G） | —（Agent） | 可选 Agent 调 `record-pipeline-timing --substep cwiki|write_index`（**未默认接线**） | No — Index-Lite 仍须 full gate | `plan_artifact_missing`, `plan_schema_incomplete`, `empty_write_set` |
| **plan gate --post** | plan | Quality+Data | `index.md`, `plan-index-rules` / `resolve_plan_index_rules.py` | `handoff/plan.json`, `task_tier`, PQ 结果 | `gate-lib/plan.sh` + `plan-quality-gate.py` | `record-pipeline-timing` **end** on `update_state_gate` | No | `plan_gate_missing`, PQ-* → `plan_schema_incomplete`, `contract_stale`, `execution_cascade_plan_rejected` |
| `goal-advance-stage`（plan 后） | plan→implement | Control | handoff chain + `state.guazi_flow_stages` | `next_stage=implement` | `goal-advance-stage.sh` | — | No | `plan_code_order`（blocked） |
| **implement gate --pre** | implement | Control | `handoff/plan.json`, `index.md`, API mapping hash | pass | `gate-lib/implement.sh` | timing **start** `implement` | No | `plan_gate_missing`, `write_set_violation`, `handoff_missing` |
| **guazi-flow-implement**（Agent） | implement | Control | `index.md` write_set, implement SKILL | `src/**` diff, index 执行记录 | — | Dev loop 禁止全量 `build:beta` | No | `write_set_violation`, Stop Conditions → blocked |
| **verification-oracle (UVO)** | implement | Quality | `plan.json` write_set, `code_subject_hash`, `task_tier` | `evidence/verification-oracle.json` | `verification-oracle.sh` / `verification_oracle_core.py` | UVO `steps[]` 内 step 输出/耗时（oracle JSON） | No — implement post 硬依赖 | `uvo_not_pass`, `verification_oracle_failed`, `uvo_skipped_illegally`, `duplicate_verify` |
| **acceptance-matrix-ratchet** | implement | Quality | index 验收矩阵, diff, UVO evidence | ratchet pass/fail | `acceptance-matrix-ratchet.py` | — | No（guazi implement post） | `am_ratchet_failed` |
| **implement-qc-gate (IQ)** | implement | Quality | repo diff, tier | structural IQ JSON | `implement-qc-gate.py`（`--skip-test-lint`） | — | No — 与 UVO 分工（IQ 不重复跑 test） | implement_qc issues |
| **contract-conformance (IQ10)** | implement | Quality | index API 映射, src | `contract-conformance.json` | `contract-conformance-check.py` | — | No（wired in implement post） | contract issues |
| **implement gate --post** | implement | Quality+Data | 上述 + git HEAD | `handoff/implement.json` | `gate-lib/implement.sh` | timing **end** | No | `noop_fix`, UVO/AM/IQ/CC 失败码 |
| `validate-pipeline-chain` | implement exit | Data | handoff 链 | exit 0 | `validate-pipeline-chain.py` | — | 推荐（guazi Stage Exit） | chain validation errors |
| **runtime-smoke** | quality | Efficiency | `verification_oracle_core.smoke_required`, dev 命令推导 | `evidence/runtime-smoke.md` | `runtime-smoke.sh` | `runtime-smoke.md` frontmatter `duration_ms` | 条件跳过（pattern / tier） | smoke `not_pass` → quality BLOCK |
| **quality gate --post** | quality | Quality | `implement.json`, `runtime-smoke.md`, handoff 链 | `handoff/quality.json` | `gate-lib/quality.sh` + `quality-gate.sh` | timing start/end `quality` | No | `quality_gate` (QG-01), `missing_state_file_context` |
| `gate stage smoke`（遗留） | smoke | Quality | 同 smoke evidence | `handoff/smoke.json` | `gate-lib/smoke.sh` | 同 quality 阶段名可记录为 `smoke` | **可跳过** — advance 用 `quality`；仅直调 `--stage smoke` 时 | 同 smoke |
| `refresh-handoffs-after-index` | review（前） | Data | `index.md` contract vs execution tail hash | 级联 refresh handoff / demote | `refresh-handoffs-after-index.sh` | — | 条件（index 漂移） | `contract_stale`, `execution_cascade_plan_rejected` |
| **review gate --pre** | review | Quality | `plan.json`, `implement.json`, `review-packet.json`, UVO fresh | pass | `gate-lib/review.sh` + `verify-review.sh` + `review_packet_preflight.py` + `check_commit_before_review.py` | timing **start** `review` | No | `contract_stale`, `packet_preflight_failed`, `uncommitted_write_set`, `review_stale`, `uvo_skipped_illegally` |
| **review-channel-guard** | review | Quality | `~/.goal-pipeline/state/config.json`, detect cache | channel JSON / degraded | `review-channel-guard.py` | — | No（chain 第一步） | `review_channel_missing`, `review_channel_timeout_storm` |
| **assemble-review-packet** | review | Data | index, handoff, diff, rubric | `handoff/review-packet.json` | `assemble-review-packet.sh` | — | No | `packet_preflight_failed` |
| **run-independent-review** / `kernel.review.cli` | review | Quality | packet, 验收标准 | `review-run.json`, `review-unified.json` | `run-independent-review.sh` / `kernel/review/cli.py` | `review-run.json` latency / `invocation_count` | 0 channel 可 degraded（非 full pass） | `review_forged`, `review_undetermined`, `review_degraded_as_pass` |
| **guazi-flow-review**（Step 1.5，dual track） | review | Control | `guazi-flow-review/SKILL.md` | `issues_gf[]` → merge | —（Agent） | — | **可跳过** — `review_track=single` | — |
| **merge-review-issues** | review | Data | unified + gf issues | `evidence/review-fix-input.json` | `merge-review-issues.sh` / `kernel.review.cli run` | — | No | — |
| **review gate --post** | review | Quality | `review.md`, `review-unified.json`, `review.json` handoff | `handoff/review.json` | `gate-lib/review.sh` | timing **end** | No | `review_forged`, `noop_fix`, `review_not_pass`, `review_rounds_exhausted`, `review_stagnant` |
| **complete gate --pre** | complete | Control | `handoff/review.json` pass, index `current_stage` | pass | `gate-lib/complete.sh` | timing **start** `complete` | No | review not pass（除非 waiver） |
| **guazi-flow-complete**（Agent） | complete | Control | complete SKILL, evidence fresh | index 执行记录, `evidence/complete.md` | — | — | No | `delivery_evidence_missing` |
| **complete gate --post** | complete | Quality+Efficiency | review.md, handoff 链 | `handoff/complete.json`, `delivery-quality.json` | `gate-lib/complete.sh` + `write-delivery-quality.sh` + `quality_plane_check.py` | timing **end** | No | `review_forged`, `uvo_skipped_illegally`, `delivery_evidence_missing` |
| `kernel complete` | complete | Quality | 同上 | exit 0 | `quality_plane_check.py` + `gate --assert-complete` | — | No | 同上 |
| `gate --assert-complete` | complete | Control | `state.json`, handoff 链 | `status=complete` 写回 | `gate-guazi-flow-stage.sh --assert-complete` | — | No | pipeline incomplete → exit 2 |
| `four_planes_doctor` | meta | All | repo scripts + 可选 state | doctor JSON | `four_planes_doctor.py` | — | 推荐（Wave 验收） | install drift（meta） |
| `data_plane_check` | meta | Data | task, project_root, state | JSON | `data_plane_check.py` | — | 可选（kernel doctor 附带） | `project_id_mismatch`, `contract_stale`, `execution_cascade_plan_rejected` |
| `quality_plane_check` | complete / audit | Quality | evidence review + UVO | JSON | `quality_plane_check.py` | — | No on complete 路径 | `review_forged`, `review_degraded_as_pass`, `uvo_skipped_illegally` |
| `efficiency_plane_check` | meta | Efficiency | scripts 静态 + 可选 `pipeline-timing.json` | JSON | `efficiency_plane_check.py` | 校验 `timezone==UTC` | 可选（doctor） | `duplicate_verify`, `missing_state_file_context`, `noop_fix` |
| `pipeline-postmortem` | blocked / retro | Efficiency | `state.failure_code`, timing | 建议 JSON | `pipeline-postmortem.py` | 读 `pipeline-timing.json` | 可选 | — |
| **纯 goal-pipeline `gates/*.sh`** | plan…complete | Control | 无 guazi index 契约 | 纯模式 handoff | `gates/plan-pre.sh` 等 | **未**接 `record-pipeline-timing` | 仅 `guazi_flow_available=false` 降级 | 同语义 failure codes |

---

## 平面检查与门禁映射（摘要）

| 平面 | 运行入口 | 节点级代表 |
|------|----------|------------|
| 控制 | `goal-pipeline-kernel` | WO、`assert-plan-before-code`、`goal-advance-stage`、stage gate pre/post |
| 数据 | `resolve-artifact-paths` + `validate-state` + refresh | handoff 链、`index_contract_hash`、`artifact_layout.split` |
| 质量 | gate post + UVO + review-chain + `quality_plane_check` | PQ/IQ/UVO/AM/preflight/ChannelPolicy |
| 效率 | WO 约束 + timing/postmortem/benchmark | noop_failfast、UVO 同 hash 跳过 build、review 0-channel fail-fast |

---

## 耗时 SSOT 与钩子现状

| 产物 | 记录内容 | 谁写入 | 默认是否齐全 |
|------|----------|--------|--------------|
| `evidence/pipeline-timing.json` | per-stage `start`/`end`/`mark`, `substeps`, UTC | `record-pipeline-timing.py`，由 **`gate-guazi-flow-stage.sh` 仅 start + post-pass end** | 每阶段 gate 有 start/end；**substep（cwiki/uvo/attempt）无默认接线** |
| `evidence/runtime-smoke.md` | `duration_ms`, `dev_cmd` | `runtime-smoke.sh` | 条件必填 |
| `evidence/verification-oracle.json` | per-step pass + output tail | UVO | implement post 必填 |
| `evidence/review-run.json` | provider, latency, invocation | independent review / kernel CLI | review 必填（否则 `review_forged`） |
| `evidence/review-unified.json` | issues[] | review chain | review post 必填 |
| `handoff/*.json` `gate.passed_at` | 阶段完成时间 | gate post | 必填 |

`efficiency_plane_check.py` 要求：`record-pipeline-timing.py`、`pipeline-postmortem.py`、`benchmark-pipeline-replay.sh` 存在；task 级检查 `pipeline-timing.json` 的 `timezone=UTC`。

---

## 冗余 / 缺口（优化 Frontier）

### 冗余或双轨节点

1. **`smoke` gate 阶段 vs `quality` 阶段**：`gate-guazi-flow-stage.sh` 与 `gate-lib/smoke.sh` 仍独立；`goal-advance-stage` / WO 只推进 **quality**（内部 `runtime-smoke.sh` + `quality-gate.sh`）。直调 `--stage smoke` 可产生多余 `handoff/smoke.json`。
2. **`runtime_smoke` next_stage 别名**：`goal-stage-driver` 将 `runtime_smoke` 与 `quality` 互别名，与 advance 仅输出 `quality` 并存。
3. **纯模式 `goal-pipeline/gates/*.sh`** vs **guazi `gate-lib/*.sh`**：SKILL 文档两套门禁路径；guazi 生产路径以 `gate-guazi-flow-stage` 为准。
4. **review-pre `verify-review.sh`** 与 **quality-gate / UVO**：scope/secret 分层重复（确定性 0-cost + 深度检查）；裁减需证明不增 silent pass。
5. **`goal-run-review-chain.sh` kernel CLI 分支**：`kernel.review.cli run` **已包含** `merge-review-issues`（与 shell Step 3 等价）；chain 在 CLI 成功路径提前 exit 前会 sync review timing substep。

### 耗时钩子缺口

1. **仅 gate 边界记录 timing**：`runtime-smoke.sh`、UVO 各 step、`goal-run-review-chain` 子步骤 **未** 默认调用 `record-pipeline-timing --substep`（fixture `test-pipeline-timing-sla.sh` 展示期望形态，非生产自动接线）。
2. **`record-pipeline-timing.py` stage 列表** 文档含 `plan|implement|quality|review|complete`，**不含 `smoke`**，与遗留 smoke gate 不一致。
3. **Phase 1 / Agent turn** 无墙钟 SSOT（仅可选 postmortem 推断）。
4. **task_tier SLA** 在 `task-tier-matrix.md` 与 postmortem，**未**与 `pipeline-timing.json` 自动对账（无统一 SLA breach failure_code）。

---

## 源码索引（绝对路径）

| 路径 |
|------|
| `/Users/xuwei/Profession/goal/docs/architecture/goal-runtime.md` |
| `/Users/xuwei/Profession/goal/goal-pipeline/SKILL.md` |
| `/Users/xuwei/Profession/goal/guazi-flow-goal/SKILL.md` |
| `/Users/xuwei/Profession/goal/goal-pipeline/scripts/goal-pipeline-kernel.sh` |
| `/Users/xuwei/Profession/goal/goal-pipeline/scripts/gate-guazi-flow-stage.sh` |
| `/Users/xuwei/Profession/goal/goal-pipeline/scripts/goal-run-review-chain.sh` |
| `/Users/xuwei/Profession/goal/goal-pipeline/scripts/goal-advance-stage.sh` |
| `/Users/xuwei/Profession/goal/goal-pipeline/scripts/goal-stage-driver.sh` |
| `/Users/xuwei/Profession/goal/goal-pipeline/scripts/gate-lib/{plan,implement,quality,smoke,review,complete}.sh` |
| `/Users/xuwei/Profession/goal/goal-pipeline/scripts/four_planes_doctor.py` |
| `/Users/xuwei/Profession/goal/goal-pipeline/scripts/data_plane_check.py` |
| `/Users/xuwei/Profession/goal/goal-pipeline/scripts/quality_plane_check.py` |
| `/Users/xuwei/Profession/goal/goal-pipeline/scripts/efficiency_plane_check.py` |
| `/Users/xuwei/Profession/goal/goal-pipeline/references/failure-codes.json` |

---

*Generated for Wayfinder issue #2 — 2026-08-01.*
