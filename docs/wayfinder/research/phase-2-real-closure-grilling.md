# Wayfinder Phase-2：实质闭环（Grilling + Backlog）

**基准提交：** `df4caf2`（`origin/main` + 运行时 `git_rev` 已对齐）  
**事实来源：** `draft-zero-leakage-and-ux-policy.md` 开放题、`optimization-spec-outline-v0.md` §未决、`review_strict_ux.py` 行为、post-df4caf2 代码与 fixture

---

## Ratified C1（2026-08-01，#1）

用户已拍板 **全部 Phase-2 grilling 项采用 C1**。实现落点：

| 轴 | C1 摘要 | 落点 |
|----|---------|------|
| fe-argus v2 | 规则 manifest 必填 + 条件 fe-argus skill merge（`source: rule\|argus`）；partial → `argus_enrich_status: partial` | [argus-v2-hybrid.md](../../goal-pipeline/argus-v2-hybrid.md)、`argus_enrich_plan.py`、`gate-lib/plan.sh` |
| strict tier | 仅 hard/blocker L10 + ux-scan blocker 升 review blocker；warn/soft → issues 警告，不 alone `not_pass` | `review_strict_ux.py`、`merge_review_core` |
| matrix_row_unsatisfied | failure-codes（`silent_pass_forbidden: false`）；W2 `leakage.matrix_rows_unsatisfied[]`；complete 不新增硬拦 | `failure-codes.json`、`w1_leakage_bookkeeping.py`、`quality_plane_check.py` |
| P1-9 auto-fix | skill 执行 D2/D5；`ux-auto-fix-audit.py` implement post | `gate-lib/implement.sh` |
| #2 节点 skip | 仅效率面可 skip；质量面节点不可 lite 默认跳过 | [pipeline-node-catalog.md](../pipeline-node-catalog.md) 文首 C1 原则 |

**工程 backlog T1–T5：** T1 W1 记账 ✅；T2 B.8 eslint D5 ✅；T3 kernel CLI merge parity ✅；T4 strict UX 分层 ✅；T5 timing substep/report ✅。

---

## 1. 三条审计痛点 vs post-df4caf2 对账

| # | 审计痛点（用户口径） | post-df4caf2 状态 | 证据 / 残余风险 |
|---|----------------------|-------------------|-----------------|
| **A** | **Argus manifest 默认 `open` → complete 被 `quality_plane_check` 全拦**（与 B3「L10 soft 不硬 block implement/complete」冲突） | **已修复** | `l10_row_blocks_complete()`：仅 `hard/blocker/critical` 或 `escalated_to_l9` 拦 complete；`soft+open` 放行。`test-quality-plane-l10-soft.sh` 覆盖 hard vs soft。 |
| **B** | **P1-7/8 标 ✅ 但实为规则占位，非 fe-argus / 真 Argus；strict 下 UX warn 噪音大** | **部分修复** | spec v0.2 已诚实标注 **rule-based v1**（`argus_enrich_plan.py` / `ux_scan_v1.py`）。`test-ux-scan-v1` + `test-review-strict-ux` 已入库。**仍破：** strict 下 **L10 soft+open** 与 **ux-scan `severity: warn`** 一律进 `review_strict_ux` → merge 为 **blocker**（与 ratified「implement post 不因 L10 alone 硬 block」一致，但 **warn 在 strict=review fail** 未按严重度分层）。fe-argus Scenario Q **未接**。 |
| **C** | **形式收口（GitHub CLOSED / spec ✅）≠ 能力闭环** | **仍破（流程面已澄清，能力面未闭环）** | #2–#7 已 CLOSED 仅代表 Phase-1 研究/实现包；**#1 OPEN** 合理。§未决仍阻塞 **规格 v1**：`matrix_row_unsatisfied`、AM waive、W2 对外口径、split handoff 统一、PQ/IQ 分层、P1-9 auto-fix 落点、#2 节点可跳过表、fe-argus v2。 |

**与 ratified 政策的交叉核对：**

| 政策点 | df4caf2 实现 | 缺口 |
|--------|--------------|------|
| B3 complete：soft L10 不 silent-pass 拦 complete | ✅ `quality_plane_check` | `w1_leakage_bookkeeping.py` 仍把 **任意 open L10** 记入 `declared_defect_classes_silent_pass`（未复用 `l10_row_blocks_complete`）→ **delivery-quality 指标与 complete 闸门不一致** |
| B3 W1 记账：L10 须 pass/waive/deferred | ⚠️ 记账有，语义分裂 | bookkeeping「silent」≠ complete「block」；需在 Phase-2 统一口径或分字段（`w1_open_soft_debt` vs `silent_pass`） |
| strict = review-first | ✅ implement 不因 L10 alone 硬 block | strict 把 **warn** 当 review blocker（见 §2 grilling） |
| B.8 宿主 eslint 消费 D5 | ❌ 未实现 | `ux_scan_v1` D5 仍为 AST 启发式，**未**读宿主 `eslint` / `jsx-a11y` 报告 |

---

## 2. Phase-2 Grilling Pack（C1 / C2）

格式：**C1 = 默认推荐（与现有 ratified 尽量一致）**；**C2 = 备选**；**需 HITL 冻结项**标出。

---

### 2.1 fe-argus v2：plan post 是否 **必须** 调 fe-argus skill

| | **C1（推荐）Hybrid v2** | **C2** |
|---|-------------------------|--------|
| **方案** | plan post **固定两步**：① `argus_enrich_plan.py`（规则 v1，零 LLM、可复现）→ ② **条件触发** fe-argus：`write_set` 含页面域 / index 关键词命中 / profile≥S 时，Agent **必须** 加载 `fe-argus` skill，**INDEX on-demand** 拉 Scenario Q，**merge** 进 manifest（去重 by scenario id，保留 `source: rule|argus`）。 | **C2a 强制 skill：** 凡 guazi-flow plan post，WO/skill_to_load **硬绑定** fe-argus，规则脚本仅作 fallback。**C2b 仅 enriched rules：** 扩展 `PATH_SCENARIO_RULES` + index 正则，**禁止** LLM/skill 依赖（与 A.8「fe-argus INDEX」原文冲突，仅适合 XS/lite）。 |
| **门禁** | manifest 缺失 = plan post fail；argus 步骤失败 = **degraded manifest**（`argus_enrich_status: partial`）+ PQ warn，**不** silent pass。 | C2a：argus 失败 = plan post block。C2b：无 argus 依赖。 |
| **HITL** | 确认 **lite/XS** 是否豁免步骤 ②；确认 merge 冲突时 **rule 优先还是 argus 优先**。 | C2a 需确认 CI/无网环境降级策略。 |

---

### 2.2 strict tier：ux-scan **warn** 在 strict 下 → fail 还是 warn only

| | **C1（推荐）** | **C2** |
|---|----------------|--------|
| **方案** | **严重度分层（与 complete 对齐）：** `review_strict_ux` 仅把 **L10 非 closed** 与 ux-scan **`blocker/block/hard`** 未处置项升为 review blocker；**`warn/info/soft`** 在 strict 下写入 unified issues 但 **`severity: warn`**（或 `degraded` 通道），**不** 单独导致 `merged_result=not_pass`。L10 manifest：**仅非 soft 或已 escalated** 行走 strict blocker（与 `l10_row_blocks_complete` 同逻辑）。 | **C2a 全量 strict：** 凡 manifest/ux-scan 有 open 项（含 warn）→ review blocker（**当前代码行为**，与 ratified「review-first」一致但 **吵**）。**C2b strict 仅 L10：** manifest open 拦 review，ux-scan 永远 warn-only（削弱 strict 语义）。 |
| **HITL** | 确认 strict 产品承诺：「UX debt 必须在 review 清零」是否 **仅指已 manifest 的 hard/升级行**。 | C2a 需用户接受 warn 噪音；C2b 需接受 ux-scan 在 strict 下无 teeth。 |

**当前代码事实（供 grill 引用）：** `collect_strict_ux_issues` 对 ux-scan **不读 `severity`**，open 即 blocker；suggestion 文案仍写「do not hard-block implement post on L10 alone in **standard** tier」。

---

### 2.3 `matrix_row_unsatisfied`：failure-codes + W2 度量 vs review-only

| | **C1（推荐）** | **C2** |
|---|----------------|--------|
| **方案** | **双轨记账、单轨闸门：** 在 `failure-codes.json` **新增** `matrix_row_unsatisfied`（plane=quality，**`silent_pass_forbidden: false`**，**不** 默认 block implement/complete）。W2：`delivery-quality.json` / measure 模板增加 `leakage.matrix_rows_unsatisfied[]`（行 id、verify 类型、证据指针），由 **AM ratchet 失败** + **review rubric 矩阵项 fail** + **可选** `acceptance-matrix-ratchet` 输出汇总。**complete** 仅在矩阵行已绑定 **ratchet verify** 且 ratchet fail 时用 `am_ratchet_failed`；纯语义 L9 仅 W2 + review fail。 | **C2 review-only：** 不入 failure-codes；W2 人工在 index/PR 勾选；Goal 只保证 review rubric 引矩阵行。**C2 硬码：** `matrix_row_unsatisfied` 入 failure-codes 且 **complete 硬 block**（易与「未机器化矩阵行」冲突）。 |
| **HITL** | AM **`waived` + separation** 算不算 W2 漏出（开放题 #2）。 | C2 需产品接受 Goal 不计量 L9。 |

---

### 2.4 P1-9 auto-fix：goal gate allowlist vs 仅 guazi-flow-implement skill

| | **C1（推荐）** | **C2** |
|---|----------------|--------|
| **方案** | **Skill 执行、Gate 审计：** D2/D5 自动修复 **只** 在 `guazi-flow-implement`（或 review 回流 WO）内由 Agent 改 diff；Goal **不** 内置 codemod。implement post 增加 **可选** `ux-auto-fix-audit.py`：diff 仅 write_set、仅 D2/D5 模式（loading/disabled、`aria-label` 字面量）、无路由/service 变更 → pass；否则 `write_set_violation` 或 warn。XS/S 无额外 HITL；S+ 要求 `evidence/ux-autofix.json` 留痕。 | **C2 gate allowlist：** `gate-lib/implement.sh` 内嵌白名单脚本可自动 patch（确定性、难覆盖复杂 JSX）。**C2 纯 skill：** 无 gate 审计，仅靠 review（与 C1 narrow 授权弱一致）。 |
| **HITL** | 自动修复失败是否 **noop_fix** 还是仅 fix-input。 | C2 gate 脚本维护成本与 profile 无关性。 |

**现状：** 规格 C1 narrow 已 ratified；gate 侧 **`ux-auto-fix-audit.py`** + `implement.sh` post 已落地（[#11](https://github.com/sophiezel/goal/issues/11)）；执行仍 **skill-only**（无 codemod）。

---

### 2.5 #2 节点裁剪：哪些可 skip（HITL）

基于 `pipeline-node-catalog.md`「Necessity」列 + 冗余段，**建议 grill 冻结表**：

| 节点 | C1 可跳过？ | C2 / 条件 | HITL 要点 |
|------|-------------|-----------|-----------|
| `kernel init` / `state.json` | **否** | — | 无 canonical state = 数据面分裂 |
| Phase 1 Interview | **压缩**（fast-path） | **否** 跳过 state 创建 | 与「Goal 卡片」字段最小集 |
| `guazi-flow-plan` Agent | **否** | Index-lite 仍 full gate | — |
| UVO | **否** | — | L5 漏出口径 |
| `acceptance-matrix-ratchet` | **否**（默认） | lite：**warn-only ratchet**（C2） | 与 L9 度量绑定 |
| `runtime-smoke` | **条件跳过** | tier/pattern 已支持 | 与 quality 合并叙事 |
| `gate stage smoke`（遗留） | **是**（推荐废弃直调） | `GOAL_ALLOW_LEGACY_SMOKE_STAGE=1` | 与 quality 双轨 |
| `guazi-flow-review` Step 1.5 | **是** | `review_track=single`（XS/S + lite 已默认） | dual vs single 产品承诺 |
| `four_planes_doctor` / plane checks | **可选**（meta） | complete 路径上 **quality_plane_check 不可跳过** | Wave 验收 vs 日常 run |
| `merge-review-issues`（kernel CLI 路径） | **不应跳过** | 当前实现可能 bypass（**bug/缺口**） | 修 CLI 路径 vs 强制 shell merge |
| timing `substep` | **可选** | 无 SLA breach code | #7 看板依赖 |

**C1 裁剪原则：** 仅 **效率面**（smoke 遗留、review dual track、doctor、timing substep）可 skip；**质量面 silent-pass 风险** 节点不可 skip。  
**C2 原则：** lite profile **显式降级表**（IQ skip-test-lint 已有；ratchet warn-only；argus 仅 rule v1）。

---

## 3. Draft：GitHub Issue #1 评论

```markdown
## Phase-2 REAL closure backlog（post-df4caf2）

形式收口（#2–#7 CLOSED）≠ 能力闭环。`df4caf2` 已修复：**B3 soft L10 不再误拦 complete**（`quality_plane_check` + fixture），并补齐 verify nested complete 解析与 UX 相关 gate tests。P1-7/8 文档已改为 **rule-based v1（非 fe-argus LLM）**。

### 仍 open 的实质项（阻塞规格 v1 / 真闭环）

1. **fe-argus v2（A.8 原文）** — plan post INDEX on-demand Scenario Q vs 规则 manifest；lite 是否豁免。
2. **strict tier 严重度** — `review_strict_ux` 当前 strict 下 **ux-scan warn** 亦作 review blocker；需冻结：warn only vs 全量 open 拦截（与 complete 侧 blocker-only 对齐）。
3. **W1 记账一致性** — `w1_leakage_bookkeeping` 仍将 **soft L10 open** 记入 silent_pass 列表，与 complete 闸门不一致。
4. **L9 `matrix_row_unsatisfied`** — failure-codes vs W2-only；AM waive 是否算漏出。
5. **P1-9 auto-fix 落点** — skill-only + gate audit vs gate 内 codemod。
6. **B.8** — D5 消费宿主 eslint/jsx-a11y（ratified 未实现）。
7. **#2 节点裁剪表** — smoke 遗留 / review dual / merge-review CLI 路径等待 HITL 冻结。

### Phase-2 工程 backlog（本仓）

| ID | 任务 | 状态 |
|----|------|------|
| T1 | `w1_leakage_bookkeeping` 与 `l10_row_blocks_complete` 对齐 | 进行中 |
| T2 | B.8：ux-scan D5 消费宿主 eslint | 待 grill |
| T3 | kernel review CLI 路径 `merge-review-issues` 等价 | 待 |
| T4 | `review_strict_ux` ux-scan severity 分层（C1 默认） | 待 grill |
| T5 | timing substep（UVO / review-chain） | 待 |

### Decisions 待写入（grill 后回填 #1 «Decisions so far»）

- fe-argus v2: C1 hybrid / C2 mandatory / rules-only
- strict: warn 在 strict 下是否 fail review
- matrix_row_unsatisfied: codes + W2 vs review-only
- auto-fix: skill+audit vs gate codemod
- node skip 冻结表（lite vs standard vs strict）

Ref: [phase-2-real-closure-grilling.md](https://github.com/sophiezel/goal/blob/main/docs/wayfinder/research/phase-2-real-closure-grilling.md)；`optimization-spec-outline-v0.md` §未决；commit `df4caf2`.
```

---

## 4. 无需 grilling 即可开工的代码任务（T1–T5）

| # | 任务 | 理由 |
|---|------|------|
| **T1** | **`w1_leakage_bookkeeping.py` 与 `l10_row_blocks_complete` 对齐** | 纯一致性：soft+open L10 不应进入 `declared_defect_classes_silent_pass`；可增字段区分「open soft debt」vs「须拦 complete」。不触碰 fe-argus / L9 政策。 |
| **T2** | **B.8：ux-scan D5 消费宿主 eslint** | `draft` **已 ratified CONFIRM**；在 write_set 路径跑 `eslint`（或读 CI 缓存 JSON），结果 merge 进 `ux-scan.json`，保留启发式 fallback。 |
| **T3** | **kernel review CLI 路径保证 `merge-review-issues` 等价** | `pipeline-node-catalog` 已标缺口；行为修复 + fixture，不涉及节点 skip 政策。 |
| **T4** | **`review_strict_ux` 对 ux-scan 读取 `severity`**（仅 `blocker/block` 进 strict blockers） | 与 `quality_plane_check` complete 路径一致；若产品后续 C2a「全量 strict」可在 tier 配置开关，默认实现 C1 分层。 |
| **T5** | **timing substep 接线（UVO steps / review-chain）** | #7 研究已就绪；纯效率面，不改变闸门 pass/fail 语义。 |

**不宜无 grill 开工：** fe-argus v2 强制策略、 `matrix_row_unsatisfied` 入码表、auto-fix gate codemod、lite profile 全局 skip 表、W1 vs W2 对外「0 漏出」口径。

---

## 附录：§未决 × 开放题索引

| optimization-spec §未决 | draft 开放题 # |
|--------------------------|----------------|
| `matrix_row_unsatisfied`、AM waive、A.1 北星 | #4 1–3 |
| （#5 C1/B3/Q11 已 ratified，实现仍 v1 规则） | #5 6–11 已决 |
| #7 耗时看板 | cross #12 CTB 附录 |
| split handoff SSOT、PQ/IQ | #4 4–5 |

---

*Phase-2 Wayfinder grilling pack；父地图 [#1](https://github.com/sophiezel/goal/issues/1)。*
