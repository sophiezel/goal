# guazi-flow-goal 调度链节点 I/O 契约审计（Phase-5）

**Closes:** [GitHub #37](https://github.com/sophiezel/goal/issues/37)  
**Map:** [Phase-5 #36](https://github.com/sophiezel/goal/issues/36)  
**Baseline:** [pipeline-node-catalog.md](./pipeline-node-catalog.md) (Phase-3/4)  
**Authority:** `guazi-flow-goal/SKILL.md`, `goal-pipeline/SKILL.md`, `references/bridge-contract.md`, `references/stage-handoff-contract.md`, `goal-pipeline/scripts/goal-run-review-chain.sh`, `goal-stage-driver.sh`, `gate-guazi-flow-stage.sh`

**Scope ratification applied:** goal-pipeline **独立审核 parity** + **共享 review kernel 公共服务**（[#36 评论](https://github.com/sophiezel/goal/issues/36#issuecomment-5151795281), [#36 评论](https://github.com/sophiezel/goal/issues/36#issuecomment-5151812266)）。本稿在 review 平面 **分轨标注**：kernel 契约 vs workflow wrapper。

---

## 1. 调度链拓扑（guazi-flow-goal）

```
Phase 1 (goal_engineering)
  pre-flight → interview/fast-path → state.json → Phase 1 GATE → Phase 2

Phase 2 (per stage: plan → implement → quality → review → complete)
  kernel next → Lazy load stage SKILL → Agent/脚本执行
  → gate --pre → … → gate --post → goal-advance-stage → kernel next | complete
```

| 阶段 | GATE 模式 | Lazy SKILL（guazi 可用） | 降级（guazi_flow_available=false） |
|------|-----------|--------------------------|-------------------------------------|
| plan | `gate-lib/plan.sh` | `guazi-flow-plan/SKILL.md` | plan 卡片 + `gates/plan-*.sh` |
| implement | `gate-lib/implement.sh` + UVO/AM/IQ | `guazi-flow-implement/SKILL.md` | `gates/implement-*.sh` |
| quality | `gate-lib/quality.sh` | `goal-quality/SKILL.md` | 同左 |
| review | `gate-lib/review.sh` + chain | `guazi-flow-review` **或** `goal-review`（single） | `goal-review` + chain |
| complete | `gate-lib/complete.sh` | `guazi-flow-complete/SKILL.md` | `gates/complete-*.sh` |

**控制面 SSOT：** `goal-pipeline-kernel` → `goal-stage-driver.sh` 产出 `FrozenWorkOrder`（`mandatory_commands`, `code_writes_allowed`, `skill_to_load`）。  
**数据面 SSOT：** `resolve-artifact-paths.py` + `artifact_layout.split` → Tier-R `handoff/`、`evidence/` 在 `~/.goal-pipeline/state/projects/<pid>/<branch>/<task>/artifacts/`；Tier-G `index.md` 等在 `docs/guazi-flow/<task>/`。

---

## 2. 逐阶段 I/O 与 gate 钩子

### 2.1 Phase 1 / pre-pipeline

| 节点 | 输入 SSOT | 输出 | gate pre/post | fix-input |
|------|-----------|------|---------------|-----------|
| Pre-flight | kernel 脚本树、`failure-codes.json`、artifact schema | `pre-flight: scripts=OK\|MISSING` | — | — |
| Interview / Goal 卡片 | `interview-protocol.md`、用户 objective | 确认字段（Allowed Files、Stop Conditions） | — | — |
| `state.json` init | `git rev-parse`、task 路径 | `state.json` + `artifact_layout` + `guazi_flow_task` | Phase 1 GATE（逻辑） | — |

**断点：** Fast-path 可压缩访谈，**不可**跳过 `state.json`；`infra_missing` 阻断 Phase 2。

### 2.2 plan

| 节点 | 输入 SSOT | 输出 | gate | 回流 |
|------|-----------|------|------|------|
| `kernel next` | `state.json`、handoff 链 | WO：`skill_to_load=guazi-flow-plan` | — | `wrong_stage` |
| `assert-plan-before-code` | plan handoff、git diff | pass/block | plan pre 内 | `plan_code_order` |
| guazi-flow-plan（Agent） | 9 步 SKILL、需求 | `index.md`（Tier-G）、契约段 hash | — | — |
| plan gate --post | `index.md`、PQ 规则 | `handoff/plan.json`、`task_tier`、PQ JSON | **post 硬门禁** | `evidence/plan-gate-fix-input.json` |
| `review_track` persist | `plan.json`、`review_track.py` | `state.review_policy.track` | plan post 副作用 | — |

**上下游：** implement pre 依赖 `handoff/plan.json` + 非空 `write_set`；`index_contract_hash` 漂移 → `refresh-handoffs-after-index` / `contract_stale`。

### 2.3 implement

| 节点 | 输入 SSOT | 输出 | gate | 回流 |
|------|-----------|------|------|------|
| implement gate --pre | `plan.json`、`index.md`、API mapping hash | pass | pre | `handoff_missing`, `write_set_violation` |
| guazi-flow-implement | write_set、implement SKILL | `src/**` diff、index 执行记录 | — | Stop Conditions → blocked |
| UVO | `plan.json` write_set、`code_subject_hash` | `verification-oracle.json` | implement **post 内** | `uvo_not_pass`, `duplicate_verify` |
| acceptance-matrix-ratchet | 验收矩阵、diff | ratchet 结果 | post 内 | `am_ratchet_failed` |
| implement-qc-gate / IQ-10 | diff、tier、API 表 | IQ / contract JSON | post 内 | IQ issues |
| implement gate --post | 上述 + git HEAD | `handoff/implement.json` | **post** | `noop_fix`, `evidence/implement-gate-fix-input.json` |
| `validate-pipeline-chain` | handoff 链 | exit 0 | Stage Exit 推荐 | chain errors |

**自修复环：** implement 内 Dev loop；gate 失败 → Read fix-input → Executor 改产物 → **subject_hash 变** 才重跑 gate；`noop_fix` = 盲重试禁止。

### 2.4 quality

| 节点 | 输入 SSOT | 输出 | gate | 备注 |
|------|-----------|------|------|------|
| `runtime-smoke.sh` | UVO `smoke_required`、dev 推导 | `runtime-smoke.md` | quality post 消费 | 条件跳过（tier/pattern） |
| `quality-gate.sh` | implement handoff、smoke、链 | 汇总 L0/L1 | quality post | strict e2e 见 profile |
| quality gate --post | 链完整性 | `handoff/quality.json` | **post** | `quality_gate` |

**双轨：** 遗留 `gate --stage smoke` 可写 `handoff/smoke.json`，但 **advance 只认 quality**（catalog §冗余-1）。

### 2.5 review（三平面分轨 — 见 §3）

| 节点 | 输入 SSOT | 输出 | gate | 回流 |
|------|-----------|------|------|------|
| `refresh-handoffs-after-index` | index 契约 vs 执行尾 hash | 级联 refresh / demote | review 前条件 | `contract_stale` |
| review gate --pre | plan/implement handoff、packet（可预组）、UVO fresh | pass | pre | `packet_preflight_failed`, `uncommitted_write_set` |
| **共享 kernel 链** | 见 §3.1 | `review-packet.json`, `review-run.json`, `review-unified.json`, `review-fix-input.json` | chain + post | `review_forged`, `review_degraded_as_pass` |
| **wrapper：guazi-flow-review** | `guazi-flow-review/SKILL.md` | `issues_gf[]`（经 merge 进 unified） | —（Agent） | dual only |
| **wrapper：goal-review** | `goal-review/SKILL.md` | 编排说明 + Stage Exit 命令 | — | single 时唯一 SKILL |
| review gate --post | `review.md`, unified, handoff | `handoff/review.json` | **post** | `review_not_pass`, `review_rounds_exhausted`, `review_stagnant` |

**fix-input SSOT：** `evidence/review-fix-input.json`（禁止手改 unified / 直接解析 review.md 分流）。

### 2.6 complete

| 节点 | 输入 SSOT | 输出 | gate |
|------|-----------|------|------|
| complete gate --pre | `review.json` pass、index stage | pass | pre |
| guazi-flow-complete | complete SKILL、evidence fresh | `complete.md`、index 执行记录 | — |
| complete gate --post | review.md、handoff 链 | `complete.json`, `delivery-quality.json` | post + `quality_plane_check` |
| `kernel complete` | 同上 | `status=complete` | `--assert-complete` |

---

## 3. Review 平面：kernel vs wrappers

### 3.1 共享独立审核公共服务（**kernel 契约**）

| 能力 | 入口 | 消费工件 | 产出工件 | Gate 依赖 |
|------|------|----------|----------|-----------|
| Channel policy | `review-channel-guard.py` | `config.json`、detect cache | degraded JSON / hard fail | chain step 1 |
| Packet 组装 | `assemble-review-packet.sh` | index、handoff、diff、rubric | `handoff/review-packet.json` | preflight PKT-01..04 |
| Preflight | `review_packet_preflight.py` | packet + UVO | pass/fail | review pre + chain |
| Independent LLM | `run-independent-review.sh` **或** `kernel/review/cli.py` `invoke` | packet | `review-run.json` | post 需 provenance |
| Unified issues | 同上 `run` / merge 内嵌 | packet + channels | `review-unified.json` | post 必填 |
| Merge → fix-input | `merge-review-issues.sh` **或** `cli.py run`（含 merge） | unified (+ gf) | `review-fix-input.json` | 修复环 SSOT |
| 原子链 | `goal-run-review-chain.sh` | task_dir、state | 上述全集 | Agent Stage Exit |

**模型分离：** cross-provider 由 `run-independent-review` / channel guard 强制执行；0 channel → `separation=degraded`（deterministic_scope_only），**非** full pass（`review_degraded_as_pass` 在 complete 路径拦截）。

**CLI 快路径：** 存在 `kernel/review/cli.py` 时 chain 走 `cli run` 并 **提前 exit**（merge 已在 CLI 内），仍须 `gate --post review`。

### 3.2 goal-pipeline 原生 review（**wrapper**）

| 属性 | 说明 |
|------|------|
| SKILL | `goal-pipeline/stages/goal-review/SKILL.md` |
| 角色 | 进化轨 / **single-track** 时唯一 Agent 加载的 review skill |
| 行为 | 强制 unified LLM、测试充分性 rubric；**不替代** kernel 脚本 |
| I/O | 与 kernel **相同**工件；wrapper-only = Stage Exit 命令列表 + NEVER 规则 |
| 触发 | `review_track=single` 或 `GOAL_REVIEW_TRACK=single` 或 `state.review_policy.track=single`（`goal-stage-driver.sh` 设 `skill_to_load=goal-review`） |

### 3.3 guazi-flow-review（**wrapper，dual track**）

| 属性 | 说明 |
|------|------|
| SKILL | 仓外 `guazi-flow-review/SKILL.md`（lazy load，仅 review 阶段） |
| 角色 | Step 1.5：在确定性检查后、或与 unified 并行的 **专业审核 Agent 回合** |
| 产出 | `issues_gf[]` → `merge-review-issues` / unified `channel=guazi-flow-review` |
| 可跳过 | `review_track=single`（XS/S 默认 dual，lite 可 auto single 待 P2 flip） |
| 与 kernel | **不替代** `run-independent-review`；bridge-contract：冲突时以 goal 独立审核为准，gf issue 可 `discarded` |

### 3.4 对照表（I/O 不得混轨）

| 工件 / 行为 | Kernel 契约 | goal-review wrapper | guazi-flow-review wrapper |
|-------------|-------------|---------------------|---------------------------|
| `review-packet.json` | assemble + preflight | 消费（embedded rubric single） | 可选读 packet |
| `review-run.json` | **必须** kernel 写入 | 禁止自填 | 禁止自填 |
| `review-unified.json` | kernel/merge | 禁止自填 | issues 经 merge 进入 |
| `review-fix-input.json` | merge 输出 | **必须 Read** 修复 | 同左 |
| Agent lazy load | — | single 时 **仅** goal-review | dual 时 **额外** gf-review |
| `handoff/review.json` counts | 按 unified channel 计数 | — | `issues_gf_count` |

---

## 4. catalog delta（相对 pipeline-node-catalog §冗余/缺口）

Phase-4 后 catalog 仍准确；本审计 **确认 open** 并补充 guazi-flow-goal 视角。

| Catalog 条目 | Phase-5 状态 | guazi-flow-goal 备注 |
|--------------|--------------|----------------------|
| smoke vs quality 双轨 | **仍 open** | SKILL 强制 quality gate；遗留 smoke 仅直调 |
| `runtime_smoke` 别名 | **仍 open** | driver 与 advance 不一致 |
| `gates/*.sh` vs `gate-lib/*.sh` | **仍 open** | 降级路径文档两套；生产以 `gate-guazi-flow-stage` 为准 |
| verify-review 与 UVO 重叠 | **仍 open** | review pre 分层；裁减需防 silent pass |
| kernel CLI vs shell merge 双路径 | **仍 open** | chain 在 CLI 存在时跳过 shell merge 步但语义等价 |
| timing 仅 gate 边界 | **仍 open** | UVO/review substeps 无默认 `--substep` |
| `smoke` 不在 timing stage 列表 | **仍 open** | 与遗留 gate 一致 |
| Phase 1 无墙钟 SSOT | **仍 open** | pre-flight / interview 无 timing |
| task_tier SLA 无自动 breach code | **仍 open** | postmortem 与 matrix 未接线 |
| **新增 delta** | **open** | `bridge-contract.md` 写 `~/.goal-state/`，运行时 SSOT 为 `~/.goal-pipeline/state/` — 文档路径漂移 |
| **新增 delta** | **open** | 契约融入失败 **静默跳过**（`guazi_flow_contract_enriched=false`）— 与 index 契约消费存在 **静默降级** 风险 |
| **新增 delta** | **partial** | `review_track` plan post 写入 state；driver WO 注释 single-track — **已工程化**，catalog 行已列 dual 可 skip |
| **新增 delta** | **open** | pure `goal-pipeline` 入口无 guazi lazy load，但 review **仍走同一 kernel** — catalog 末行「纯 gates」未列 review chain 等价性（行为一致、脚本路径不同） |

---

## 5. 断点 / 双轨 / 静默降级清单

| ID | 类型 | 描述 | 影响 | Phase-5 建议 |
|----|------|------|------|--------------|
| B1 | 双轨 | smoke gate vs quality stage | 多余 `smoke.json`、timing 名不一致 | 规格： deprecate 直调 smoke 或 advance 对齐 |
| B2 | 断点 | 纯模式 `gates/` 无 `record-pipeline-timing` | 降级 run 缺效率 SSOT | #39 inventory；adapter 统一 |
| B3 | 静默降级 | 契约融入失败跳过 | index 缺 Goal 契约段仍可能进 implement | 考虑 WARN→BLOCK（profile 门控） |
| B4 | 静默降级 | 0 review channel → deterministic | `separation=degraded`；complete 有 forged/degraded 护栏 | SLO #41 纳入 degraded 口径 |
| B5 | 双轨 | review shell chain vs `cli.py run` | 运维/文档两套 step 编号 | 公开 API 冻结范围 #40 |
| B6 | 断点 | channel unreachable vs 0 channel | 前者 `blocked`+Cursor hint，后者 degraded | Agent 话术已在 chain stderr |
| B7 | 回流 | implement ↔ review | `contract_stale` / refresh-handoffs | 执行记录 vs 契约 hash 分离（已实现） |
| B8 | 双轨 | dual：gf-review Agent + unified LLM | `invocation_count`、channel 列表语义 | single-track 减 latency；dual 保留 gf 专业度 |
| B9 | 文档 | goal-state vs goal-pipeline state 路径 | 集成误读 | 统一 bridge-contract 路径表述 |

---

## 6. implement 后自修复环 vs review 独立轨（贯通）

```
implement post fail → implement-gate-fix-input → 改 src/证据 → hash 变 → re-gate
implement post pass → advance quality → review pre → kernel chain → review post
review not_pass → review-fix-input → implement 修复子循环（非降标准）→ 重进 review
review stagnant / rounds exhausted → blocked_user_decision（goal-pipeline NEVER）
```

**分离原则：** gate/Judge 与 implement Executor 分离；review LLM 与 implement Agent **provider 分离**；guazi-flow-review 仅 **增补** issues，不绕过 kernel 工件。

---

## 7. 结论与下游

- guazi-flow-goal 五阶段 I/O 与 catalog **主干一致**；Phase-5 增量重点是 **review 三平面标注** 与 **2 项文档/静默降级 delta**。
- [#38](https://github.com/sophiezel/goal/issues/38) 应引用本稿 §3 作 goal-pipeline 外部模式差距的 review 行。
- [#39](https://github.com/sophiezel/goal/issues/39) 应接管 kernel 公共 API / handoff resolver **ownership** 表。
- [#41](https://github.com/sophiezel/goal/issues/41) 应引用 §3.1 工件与 `review-run.json` metrics。

---

*Wayfinder research — 2026-08-01 — closes #37.*
