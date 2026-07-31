# Draft: 「0 漏出」度量 + UX 自动发现/修复边界

**Status:** **Part A**（#4）与 **Part B**（#5）核心策略已 ratified（2026-08-01, C1 defaults）；**Phase-3b HITL（#16 / #20 / #15）** 已 ratified 2026-08-01 — 见 [phase-3-hitl-ratified.md](phase-3-hitl-ratified.md)。**仍 open：** split handoff SSOT → [#14](https://github.com/sophiezel/goal/issues/14)。For [issue #4](https://github.com/sophiezel/goal/issues/4) / [issue #5](https://github.com/sophiezel/goal/issues/5) grilling record.

**Parent map:** [Wayfinder: Goal 交付质量与全链路效率优化](https://github.com/sophiezel/goal/issues/1)

**Sample run:** jian-h5 CTB-44243 / `docs/guazi-flow/2026-07-31-疑似车商收车审批申请`（split handoff、IQ-10、`createRequest` 绑定、UVO `build:beta`、noop_fix；quality/review/complete 未跑完）

**How to use:** Each section is labeled **Proposal**. Mark in issue comments: **confirm** / **reject** / **defer** + edits. Do not treat this file as closed ticket evidence until a human records decisions in issue #1 «Decisions so far».

---

## Part A — Issue #4: 「0 漏出」定义（草案）

### A.1 North star (align with goal-runtime)

**Ratified (2026-08-01, #4 + #20 C1):** 「0 漏出」在 Goal 语境下指：**在当次任务已声明的缺陷类集合上，不得出现 silent pass**（与 [`failure-code-dictionary.md`](../../goal-pipeline/references/failure-code-dictionary.md) 一致）。它不是「线上零 bug」，而是 **管线对声明覆盖类的漏检率 → 0**。

**对外措辞（#20 C1）：** 默认对工程/闸门说 **W1**（单次 run + `quality_plane_check`）；对产品/MR 说 **W2** 时须**显式声明**矩阵窗口，且区分 `matrix_rows_unsatisfied` vs 带 separation 的 waive。模板见 [phase-3-hitl-ratified.md](phase-3-hitl-ratified.md) §1.4 与 [optimization-spec-outline-v1.md](optimization-spec-outline-v1.md) Part A.1。

| 术语 | 草案定义 |
|------|----------|
| **声明缺陷类** | failure-codes.json `quality` + `control` 中与当次 profile 启用的闸门对应的子集；plan/index 额外声明的验收矩阵行（C#/V#/AC#） |
| **漏出 (leakage)** | 某声明缺陷类本应被对应闸门 **block**，却在当次窗口内以 full pass / 未记录 degraded 的方式通过，或缺陷事后可归因到该闸门未执行 |
| **非漏出** | 缺陷属于未声明类、宿主绕过 Kernel、或后端/产品契约在 plan 外变更 |

**Counterexample (counts as leakage):** implement post 跳过 UVO 仍 `gate --post implement` 通过 → `uvo_skipped_illegally` 类 silent pass。

**Counterexample (not Goal leakage):** 产品事后改口径但 index 未更新；merge 后后端字段变更导致页面错数——记 **business/backend contract drift**，见 A.4。

---

### A.2 Measurable leakage types (taxonomy)

**Proposal:** 漏出按 **可计数事件** 分型；每型绑定主责闸门与 failure_code。

| ID | 漏出类型 | 可观测信号 | 主闸门 / 工件 | failure_code (primary) |
|----|----------|------------|---------------|------------------------|
| L1 | **Scope / write_set 越界** | 合入 diff 含 write_set 外路径且无 separation | implement gate | `write_set_violation` |
| L2 | **Plan 契约未冻结或自相矛盾** | PQ-10..14 应拦未拦；API 表与伪代码矛盾 | plan gate | `plan_schema_incomplete`, PQ ids |
| L3 | **Plan–implement 语义漂移** | 映射表与 `src` 绑定不一致（含 split handoff 读错 handoff 根） | IQ-10 | `contract_drift` / IQ-10 |
| L4 | **验收矩阵未覆盖可验证行为** | 矩阵缺 verify 列或 AM ratchet 无对应 id | AM ratchet | `am_ratchet_failed` |
| L5 | **机器验证未执行或假通过** | 无 UVO 证据、tsc/test/build 失败仍 advance | UVO + implement post | `uvo_not_pass`, `verification_oracle_failed` |
| L6 | **Review 未独立或未拦声明类** | forged packet、degraded 当 full pass、通道缺失 | review-chain + complete | `review_forged`, `review_degraded_as_pass`, `review_undetermined` |
| L7 | **无效修复循环** | subject_hash 不变重跑 gate | implement ratchet | `noop_fix` |
| L8 | **交付证据缺失** | complete 无 review/evidence 链 | delivery gate | `delivery_evidence_missing`, `review_stale` |
| L9 | **需求/缺陷类（业务语义）** | 验收矩阵行写了「须展示 X」但实现无 X 且 review 未标 fail | AM + review rubric + 人工 | `matrix_row_unsatisfied`（**已入 failure-codes**，Phase-2 C1：`silent_pass_forbidden: false`）；W2 `leakage.matrix_rows_unsatisfied[]` |
| L10 | **隐藏 UX + Argus 场景债（见 A.8、Part B）** | fe-argus Scenario Q 在 plan post 写入 manifest 的行；默认 **软约束**，不升 L9 除非人工升级 | plan post → `handoff/argus-scenario-manifest.json`；implement/review/complete 消费 | 见 A.8（默认 warn/UX debt，**不**默认 block implement post） |

**CTB-44243 anchors:**

- **L3:** split `artifact_layout` 下 IQ-10 读 `task_dir/handoff` vs `artifacts/handoff` 不一致 → 契约扫描漏绑或误报。
- **L5:** UVO `build:beta` 耦合 `origin/<branch>` / 全仓 ESLint CI → 非任务缺陷被当成 pass/block 噪声（**效率误伤 ≠ 漏出**，但若因此 skip UVO 则回到 L5 漏出）。
- **L7:** noop_fix 后盲重试同一 gate。
- **Out of explicit matrix:** `viewingResults` 带看成功页 — README 已标 **非本页责任**；若产品把该行为写进矩阵而未实现 → L9，否则 **不算本任务漏出**。

---

### A.3 Counting window

**Ratified (2026-08-01, Wayfinder #4):** 漏出计数 **同时启用 W1 + W2** — W1 记账 L1–L8（及 W1 侧声明类 silent pass）；W2 记账 MR 合入窗口内的 L9 / 验收矩阵满足情况；二者并行、不互相替代。

**Proposal:** 三层窗口，**不混算**：

| 窗口 | 范围 | 用于 | 默认计数单位 |
|------|------|------|--------------|
| **W1 — 单次 goal run** | `init` → `complete`（或 aborted） | 闸门设计、noop、UVO 次数 | 每 failure_code 0/1 per run；记入 `measure-field-template.json` → `leakage.declared_defect_classes_silent_pass[]` |
| **W2 — MR 合入** | 业务仓 PR 从开分到 merge | 产品/工程验收「这单有没有漏」 | L9 事件 + 矩阵行 satisfied 率；Goal 只保证 W1 证据链完整 |
| **W3 — 发布后 N 天** | 可选运营复盘 | 漏出是否因声明类不全 | 仅作 **spec 反馈**，不反向惩罚单次 W1 pass |

**Rule:** 宣称「0 漏出」的**对外默认口径（#20 C1）** = **W1**：声明缺陷类 silent pass 列表为空 + complete 时 `quality_plane_check` 通过。**W2** 须在沟通中**单独声明**（MR + 验收矩阵行）；不得用 W1 pass 替代 W2 承诺。W3 仅运营复盘，非默认对外口径。W2「业务需求漏出」须显式写进验收矩阵（L9），否则不算 Goal 违约。

**W1 与 L10（B3）：** 凡 **A.8** 中 plan post 写入 `argus-scenario-manifest.json` 的 L10 行，在 W1 内与 L1–L8 一样须 **pass / waive / deferred** 记账，**禁止 silent pass**；默认处置为 **soft**（warn、UX debt），**不**构成 implement post 硬阻断，除非该行已按 A.8 升级为 L9。

**Counterexample:** W1 complete 成功，但 merge 后 PM 发现漏做「驳回原因二级联动」且矩阵从未有 C# 行 → **W2 产品/规划漏出**，不是 L1–L8；改进动作是 PQ/矩阵补行，不是改 IQ-10。

---

### A.8 B3 — L10 Argus manifest + L9 仅升级阻断（Ratified 2026-08-01, Wayfinder #4）

**North star（三层，不混层）：**

| 层 | 范围 | 职责 |
|----|------|------|
| **L1–L8** | Goal 管线治理漏出 | failure_code、闸门、UVO/review/complete 证据链（见 A.2） |
| **L9** | 产品验收矩阵 | index `## 验收矩阵` 中 **C# / V# / AC#** 等业务语义行；W2 主记账面 |
| **L10** | Plan post Argus 自动富化 | **fe-argus Scenario Q** 在 plan 阶段按任务信号生成场景清单，默认 UX/架构软债，**不**自动等同 L9 |

**Plan post（自动，只读宿主仓）：**

1. 输入信号：`docs/guazi-flow/<task>/index.md`、`write_set`、页面域路径（如 `src/pages/<domain>/`）等 plan 已冻结工件。
2. 调用 **fe-argus**：**INDEX on-demand**（按任务索引拉取相关 Scenario Q），**禁止**全量 `scenarios/` 扫描。
3. 产物：`<task>/handoff/argus-scenario-manifest.json`（L10 行：scenario id、严重度默认 `soft`、关联路径、建议 verify 钩子）；可选在 index 附录 `## Argus 场景清单（L10）` 摘要，**SSOT 仍为 handoff manifest**。

**下游消费（guidance，非替代闸门）：**

- **Implement / review / complete** 读取 manifest，作为 UX-D*、rubric、fix-input 的 **指导清单**；不得在无 manifest 行时凭空新增 L9 矩阵义务。
- 默认 **L10 = soft**：implement post 仅 warn / 记 UX debt，**不**因 L10  alone block implement post。

**W1 记账（与已 ratified W1+W2 对齐）：**

- W1 的「声明缺陷类」在 B3 下 **包含** manifest 中已声明的 **L10 行**（与 L1–L8 并列记账面，层语义仍分 L9/L10）。
- 每一 L10 行在当次 run 须 **pass / waive / deferred** 之一写入 measure / evidence；**禁止 silent pass**。
- **L9 阻断**仅当人工 **升级**：在验收矩阵写入对应 **C# / V#** 行，或 HITL 在 issue/decisions 中 **confirm 升级** 某 manifest 行为 L9；未升级前，即使 review 标 fail，也按 L10 soft 策略路由，**不**默认升格为 implement post 硬 block（**strict tier = review-first**，见 Part B **B.4** ratified）。

**与 #5 边界：** Part B 的 UX-D* 检测与自动修复授权不变；B3 解决的是 **plan 阶段如何把 Argus 场景债显式化**，避免「未声明 = 漏出口径不清」。UX 未写入 manifest 且未升 L9 → 仍 **不计 W2 L9 违约**（与 A.3 Rule 一致）。

---

### A.4 Responsibility split

**Proposal:**

| 责任域 | 负责什么 | 不负责什么 | 证据工件 |
|--------|----------|------------|----------|
| **Goal 管线** | L1–L8；执行声明闸门；honest degraded；fix-input 路由 | 未写入 index/矩阵的业务细节；宿主直接改盘 | gate logs, UVO, AM ratchet, review-run.json, measure template |
| **业务仓 (jian-h5 等)** | write_set 内实现；单测/RTL；遵守 handoff UI tags | 后端字段真值；跨 App 路由由别的页接入 | PR diff, `yarn test`, index 矩阵行 |
| **后端 / 跨端契约** | API 真值、环境数据 | H5 展示策略若未写入 plan | 接口文档、联调纪要；可选 `integration-manifest.json` |
| **产品 / HITL** | 矩阵行语义、scope 切割（如 viewingResults）、grill 冻结 | 闸门实现 | index `## 冻结决策`, decisions.json |

**Split handoff 补充:** 当 `artifact_layout=split` 时，**数据面 SSOT**（plan.json / handoff 路径）归 Goal + 任务文档约定；IQ-10 读错路径 → **Goal L3**；表本身写错 → **plan 作者（业务/HITL）**。

---

### A.5 Acceptance matrix ↔ AM ratchet ↔ review rubric

**Proposal:**

1. **验收矩阵**（index `## 验收矩阵`）= L9 的 **声明来源**。每行须含 `verify_command | data-testid | http_assert | display_assert` 之一（PQ-03/14；lite 可 warn）。
2. **AM ratchet** = 矩阵 id 集合的 **子集硬闸门**：ratchet 脚本要求的每个 id 必须在 evidence 中有 pass 记录或显式 `waived` + **有效 separation**（**#16 C1 ratified 2026-08-01**）：
   - **waive + 有效 separation** → **不算** `leakage.matrix_rows_unsatisfied[]`；可选记入 `leakage.matrix_rows_waived[]`（行 id、separation 指针、理由）。
   - **无 separation 的 waive** 或未满足行 → **算 W2 漏出**（入 `matrix_rows_unsatisfied`）。
3. **Review rubric** = 矩阵 **未机器化** 的行 + UX/视觉/a11y；ChannelPolicy 要求独立通道；rubric 项 fail → review outcome fail，**不得** degraded-as-pass。

**Mapping table (draft):**

| 矩阵行类型 | Plan (PQ) | Implement | AM ratchet | Review |
|------------|-----------|-----------|------------|--------|
| API/字段 (PQ-10 表) | PQ-10..11 | IQ-10 | 可选 display_assert 行 | 抽检 |
| 交互行为 (C#) | 伪代码 + 矩阵 | 单测/testid | 若绑定 verify_command → ratchet | rubric 行为项 |
| build:beta / 路由 | PQ 写集规则 | UVO | 常作为 V# 行 | — |
| UX loading 标签 | decisions `ui.loading[]` | 实现 | **不默认 ratchet** | checklist（Part B） |

**CTB-44243:** 骨架屏、按钮 loading 若 **未** 写入矩阵/decisions → 仅 review 软检；写入 `ui.loading[]` 或 C# 行后 → 纳入 L9 或 B 类检测。

---

### A.6 Anti-patterns (counterexamples for counting rules)

| 场景 | 算漏出？ | 类型 |
|------|----------|------|
| IQ-10 因 `as never` / 错误 adapter 锚点通过，实际 path 错 | 是 | L3 |
| 矩阵有 C05 但无 verify 列，implement 未做，review pass | 是（若 C05 可验证） | L9 + L6 |
| `am_ratchet_failed` 后人工 waive 无 separation 仍 complete | 是（#16 C1：W2 `matrix_rows_unsatisfied`） | L4/L8 + L9 |
| `am_ratchet_failed` 后 waive **带** separation 已记账 | 否（可选 `matrix_rows_waived`） | — |
| ESLint CI 红但任务 UVO 只跑 related tests 且通过 | 否（若 plan 未声明全仓 lint） | 噪声 → 效率面 |
| viewingResults 未做，scope 在 README/index 标 out-of-scope | 否 | scope |
| 骨架屏含 footer 主按钮（违反 `no_footer_cta_in_skeleton`）且 tag 已冻结 | 是（Part B 检测 + review） | L10 / L9 |

---

### A.7 Spec snippet ready for optimization doc (pending confirm)

> **漏出定义：** 当次 goal 运行（W1）中，凡已启用闸门对应的声明缺陷类，不得 silent pass。漏出事件分型 L1–L8 由 failure_code 记账；L9 由验收矩阵行满足情况在 W2 记账。Goal 不承诺 W3 业务零缺陷，除非矩阵与产品 scope 完整声明。
>
> **计数：** `leakage.declared_defect_classes_silent_pass` 为空且 `quality_plane_check` 通过为 W1「0 漏出」必要条件。

---

## Part B — Issue #5: UX 自动发现与自动修复（Ratified 2026-08-01, C1）

**North star:** **双轨发现** — (1) plan post **A.8 B3** `argus-scenario-manifest.json`（L10 记账面）；(2) implement post 可选 UX 扫描 **UX-D1 / D2 / D5**（v1）。**UX-D3 / D4 / D6 → v2 defer**。

### B.1 Scope boundary (CTB-44243)

**Ratified — in scope for detection (v1):**

- 列表/详情 **loading**：骨架屏 vs spinner；与 [`h5-loading-state-checklist.md`](../../goal-pipeline/references/h5-loading-state-checklist.md) 对齐。
- **按钮 async**：提交/审批类主按钮在请求进行中 disabled + loading，防重复提交。
- **空态 / 错误态**：接口失败是否有可理解文案（非空白页）。
- **a11y 基线**：主按钮可聚焦、图标按钮 `aria-label`（见 **B.2** D5 + **B.8** 业务仓 eslint）。

**Ratified — explicit out of scope:**

- **`viewingResults` / 带看成功页** 拦截与入口 — 样本任务 README 已划给其他页面；自动 UX 扫描 **不得** 为实现该路由开 write_set 外改动。
- 像素级视觉还原、文案润色、复杂动效。
- 改交互流程（新增步骤、改路由、改业务分支）— **永远 HITL + plan 变更**。

---

### B.2 Detection categories

| Cat | 检测目标 | 信号 | v1 扫描？ | 默认可自动化？ |
|-----|----------|------|-----------|----------------|
| **UX-D1 Loading shell** | 首屏/区块 skeleton | 有 async fetch 无 pending UI；违反 `ui.loading[]` tag | **yes** | 部分（静态启发式 + 单测快照） |
| **UX-D2 Button in-flight** | 主 CTA 重复点击 | 无 `loading`/`disabled` 绑定 mutation | **yes** | 部分（AST/testid 模式） |
| **UX-D3 Empty state** | 列表 0 条 | 无 Empty 组件/文案 | **v2 defer** | 弱（需路由上下文） |
| **UX-D4 Error surfacing** | API fail | catch 无 Toast/inline error | **v2 defer** | 弱 |
| **UX-D5 a11y baseline** | 可访问性 | 无 label 的 icon-only button | **yes** | 部分（宿主 `eslint-plugin-jsx-a11y`，见 B.8） |
| **UX-D6 Toast 一致性** | 错误提示口径 | 与仓库既有 Toast 模式不一致 | **v2 defer** | 人工/review 为主 |

**Ratified (C1 dual-track):** v1 implement post 扫描覆盖 **D1/D2/D5**，并与 plan post **L10 manifest**（A.8）并列消费；D3/D4/D6 不纳入 v1 自动扫描闸门。

**Note:** [`declarative-contract-gates.md`](../../goal-pipeline/references/declarative-contract-gates.md) 已明确 IQ-10 **不**覆盖骨架屏形态 → UX-D* 不属于契约漂移，除非矩阵/decisions 声明。

---

### B.3 Auto-fix vs HITL

**Ratified (C1 narrow) — decision table:**

| 类别 | 自动检测 | 自动修复 | 条件 |
|------|----------|----------|------|
| UX-D1 tag 违反（如 skeleton 内 footer CTA） | recommend | **禁止默认 auto-fix** | 改布局易越界；产出 review-fix-input |
| UX-D2 button loading 缺省 | recommend | **允许**（write_set 内） | 单文件、已有同类模式、不改 API 语义 |
| UX-D3 empty | v2 | HITL | 需产品文案 |
| UX-D4 error toast | v2 | HITL | |
| UX-D5 a11y label | recommend | **允许** 仅补 `aria-label` 字面量 | 不改 DOM 结构；write_set 内 |
| 交互流程变更 | — | **禁止** | 必须 plan + grill |

**自动修复白名单（C1）：** 仅 **UX-D2、UX-D5**，且 diff 严格在 **write_set** 内；禁止路由/新页/流程/API 语义变更。

**Profile 授权:**

| Profile | UX-D2/D5 auto-fix | 额外 HITL |
|---------|-------------------|-----------|
| **XS / S** | **允许** | **不需要** 额外 HITL checkbox |
| **S+**（M/L 等） | 允许（同上约束） | **须** review 证据留痕（谁改了什么、为何） |

**「规划不实现」:** 自动修复 **不得** 在 plan 阶段写入业务 `src`；仅允许在 **implement** 或 **review 回流 implement** 且 WO 明确 `mandatory_commands` 时执行。

**Review fail 路由（C1）：** UX/L10 项 review fail → **fix-input** 或显式 **waive**（带 separation）；**禁止** 引擎自动写入验收矩阵 **C#** 行或静默升格 L9。

---

### B.4 Plane placement

**Ratified:**

| 阶段 / 平面 | 做什么 | 不做什么 |
|-------------|--------|----------|
| **Plan post** | **A.8 B3** → `handoff/argus-scenario-manifest.json`（L10）；可选 `decisions.json` → `ui.loading[]`、矩阵 UX 行 | 不改业务 `src` |
| **Implement post (quality)** | 可选 **UX scan v1**（D1/D2/D5）：`evidence/ux-scan.json`，默认 **warn** | 不替代 UVO；**不因 L10/manifest  alone** hard-block implement post |
| **Quality gate tier=strict** | UX tag / manifest 违反 → **review 必 fail**（review-first） | **禁止** 仅凭 L10 在 implement post 硬 block |
| **Review packet** | rubric：checklist + ux-scan + manifest 行 | 独立通道判 fail；fail → fix-input/waive（B.3） |
| **Complete** | 消费 evidence；**已声明 L10 行**须 pass/waive/deferred（A.3） | W1 **禁止** 对已声明 L10 silent pass |

**与 #4 关系:** UX 漏出默认 **L10**（**A.8 B3**）；仅矩阵/decisions **人工升级** 后计入 **L9** 硬阻断。**未 manifest 且未升 L9 的 UX → 不算 W2 L9 违约**；**已 manifest 的 L10 → W1 须记账，禁止 silent pass**（与 A.3、open Q11 一致）。

---

### B.5 write_set constraints

**Proposal:**

- 自动修复 **仅允许** `touch` write_set 内路径；禁止为 UX 顺手改 `App.tsx`、全局样式、其他页面。
- 禁止新增路由、service 方法、API path — 属 plan 变更。
- 扫描可读全仓（只读）；修复 diff 必须在 write_set 内。
- split handoff：扫描根以 **SSOT handoff** 为准（与 IQ-10 同根因问题 — 待 #1 决策统一路径）。

---

### B.6 Default policy summary (ratified C1)

| 策略 | 推荐 | 禁止 |
|------|------|------|
| 发现双轨 | plan post L10 manifest + implement **D1/D2/D5** | v1 扫描 D3/D4/D6 |
| 默认 tier | UX scan = **warn** in implement post | 对已声明 L10 **silent pass**（W1） |
| 自动修复 | write_set 内 D2/D5；XS/S 无额外 HITL | 流程/路由/新页；viewingResults；自动写 C# |
| strict | **review-first** fail | implement post 仅凭 L10 硬 block |
| 证据 | `ux-scan.json` + manifest + review | 无 evidence 宣称 UX pass |

---

### B.7 Spec snippet ready for optimization doc (ratified)

> **UX 自动发现（双轨）：** plan post 写入 `argus-scenario-manifest.json`（L10，A.8）；implement 后可选扫描 **UX-D1/D2/D5**，产物 `evidence/ux-scan.json`，默认 warn。D3/D4/D6 留 v2。声明 `ui.loading[]`、manifest 行或矩阵 UX 行时，违反项进入 review 必查；strict = review fail，非 implement 硬拦。
>
> **自动修复：** 仅限 write_set 内 **D2/D5**；XS/S 可无额外 HITL；S+ 须 review 留痕。review fail → fix-input/waive，不自动升 C#。viewingResults 等 scope 外永不自动修复。
>
> **a11y：** 在 write_set 路径上 **消费宿主业务仓** 既有 `eslint` / `jsx-a11y` 配置（见 B.8），Goal 不另起全局 a11y 规则集。

---

### B.8 a11y — consume host ESLint (ratified)

**Decision:** **CONFIRM** — UX-D5 信号优先来自 **业务仓（如 jian-h5）** 在 **write_set 路径** 上已启用的 `eslint` + `eslint-plugin-jsx-a11y`（及同类 CI 规则），Goal UX scan **读取/汇总** 其结果写入 `ux-scan.json`，**不**在 goal-pipeline 内维护平行 a11y 规则表。扫描可读全仓；修复与 eslint 报告归因仍受 B.5 write_set 约束。

---

## Open questions (human answers required)

### From #4

1. ~~**L9 `matrix_row_unsatisfied`**~~ → **Ratified (Phase-2 C1):** 入 `failure-codes.json`（`silent_pass_forbidden: false`）+ W2 `matrix_rows_unsatisfied[]`。
2. ~~**AM ratchet `waived`**~~ → **Ratified (#16 C1, 2026-08-01):** 有效 separation 的 waive **不算** unsatisfied；无 separation = 漏出；可选 `matrix_rows_waived` 审计。
3. ~~**W1 vs W2 对外承诺**~~ → **Ratified (#20 C1, 2026-08-01):** 对外默认 **W1**；W2 须显式声明；模板见 [phase-3-hitl-ratified.md](phase-3-hitl-ratified.md) §1.4。
4. **split handoff SSOT：** IQ-10 与 AM/UX 扫描统一读 `task_dir/handoff` 还是 `artifacts/handoff`？ → **open，[#14](https://github.com/sophiezel/goal/issues/14)**
5. ~~**PQ 与 IQ 重复校验**~~ → **Ratified (#15 C1, 2026-08-01):** 分层（PQ 规划 hard / IQ 实现 hard）+ `dedupe_key`；PQ 同键不 double block；IQ 重复项 warn。见 [optimization-spec-outline-v1.md](optimization-spec-outline-v1.md) Part D。

### From #5

6. ~~**strict tier**~~ → **Ratified (C1):** **review-first**；不因 L10/manifest alone 在 implement post 硬 block。
7. ~~**XS/S 自动 UX 修复**~~ → **Ratified:** XS/S 允许 D2/D5 无额外 HITL；**S+** 须 review 留痕。
8. ~~**UX-D3/D4/D6**~~ → **Ratified:** **v2 defer**；v1 仅 D1/D2/D5 + L10 manifest。
9. **L10 与 L9：** **B3 已决（A.8）** + **#5 ratified：** plan post manifest 的 L10 在 W1 记账（pass/waive/deferred，**禁止 silent pass**）；未 manifest 且未升 L9 **不算 W2 L9 违约**。
10. ~~**eslint/a11y**~~ → **Ratified (B.8):** 消费业务仓 write_set 路径上既有 eslint/jsx-a11y。

### Cross-cutting

11. ~~**#5 blocked on #4**~~ → **CONFIRM (2026-08-01):** 接受 **未 manifest 且未升 L9 的 UX 不计 W2 L9 违约**；与 B3 一致。**已声明 L10（manifest）在 W1 禁止 silent pass** — 与「未声明不计漏出」不矛盾。
12. ~~**CTB-44243 复盘 (#3)**~~ → **CONFIRM (2026-08-01, [#22](https://github.com/sophiezel/goal/issues/22)):** 已回写 [ctb-44243-guazi-flow-goal-rca.md](ctb-44243-guazi-flow-goal-rca.md) **§8 平面归因附录**（PQ / IQ / UVO / Control / UX；IQ-10 handoff、noop_fix、UVO vs IQ；链 v0 P0/P1 与落地 commit）。

---

## Changelog

| Date | Action |
|------|--------|
| 2026-08-01 | Initial HITL draft for issues #4 and #5 |
| 2026-08-01 | Ratified A.8 B3（L10 Argus manifest + L9 escalate-only）；A.3 W1+W2 交叉引用 L10 W1 记账 |
| 2026-08-01 | Ratified Part B C1（#5）：双轨发现 D1/D2/D5 v1；D2/D5 narrow auto-fix；XS/S 无额外 HITL；strict review-first；review fail fix-input/waive；B.8 宿主 eslint；close open Q11 |
| 2026-08-01 | Phase-3b HITL：#16 AM waive / #20 W1 vs W2 对外 / #15 PQ-IQ 分层；close open Q1–3, Q5 |
| 2026-08-01 | #22：CTB-44243 §8 附录回写 #3 RCA；close open Q12 |
