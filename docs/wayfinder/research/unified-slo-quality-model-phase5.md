# Phase-5：统一 SLO / 质量与效率模型（goal-pipeline 主轨）

**Status:** Research closure for [Wayfinder #41](https://github.com/sophiezel/goal/issues/41)  
**Parent map:** [Wayfinder #36 — Goal 全链路质量与效率（Phase-5）](https://github.com/sophiezel/goal/issues/36)  
**Upstream:** [optimization-spec-outline-v1.1.md](optimization-spec-outline-v1.1.md) Part F–I · [#40 final ratification](https://github.com/sophiezel/goal/issues/40#issuecomment-5152145886) · [guazi-flow-goal-node-io-audit-phase5.md](guazi-flow-goal-node-io-audit-phase5.md) · [goal-pipeline-external-patterns-gap-phase5.md](goal-pipeline-external-patterns-gap-phase5.md) · [generic-services-inventory-phase5.md](generic-services-inventory-phase5.md) §6 · [draft-zero-leakage-and-ux-policy.md](draft-zero-leakage-and-ux-policy.md) · [phase-4-layered-demand-and-slo-input.md](phase-4-layered-demand-and-slo-input.md)

**Normative stance:** **goal-pipeline breaking-first** — 本模型为 goal-pipeline 默认 profile 的验收与审计语言；**guazi-flow-goal** 可选用同一 kernel 契约（wrapper profile），**不**要求数值或阶段名 parity。

---

## 1. 统一模型：质量面 × 效率面 × 漏出面

### 1.1 正交轴

| 轴 | 问题 | 主 SSOT | goal-pipeline 默认 |
|----|------|---------|-------------------|
| **需求成熟度（R1–R4）** | 什么必须在哪一阶段被冻结/证明 | v1.1 Part F | profile 可重排 stage 名；**不变量** = R1–R4 + gate |
| **失败分型（DEM / LEAK）** | 根因与 owner | v1.1 Part G + draft L1–L10 | 同一 taxonomy；guazi-only 断点不进入默认 SLO 切片 |
| **漏出窗口（W1 / W2）** | 对谁承诺「0 漏出」 | v1 Part A + draft §A.3 | W1 = 单次 run；W2 = MR/矩阵窗口（须显式声明） |
| **SLO 指标（SLO-*）** | 可聚合、可切片、不绕过 hard gate | 本文 §3 + v1.1 Part I | 采集 **不得** 新增 silent pass（v1.1 I.2） |
| **独立审核（kernel B）** | 分离 provider + 工件图 | #40 轴 3 B；inventory §2.1 | `goal-review` 默认 single-track；timing + `review-run.json` |

### 1.2 与四平面的映射（度量 owner）

| 平面 | 质量相关 SLO | 效率相关 SLO | DEM 主责示例 |
|------|--------------|--------------|--------------|
| **Control** | — | SLO-E-01（stage 墙钟） | DEM-01 |
| **Data** | SLO-R-02 | handoff 解析耗时（审计） | DEM-05 |
| **Quality** | SLO-W1-01, SLO-W2-01, SLO-Q-01, SLO-Q-02, SLO-R-03（误拦/重复） | — | DEM-03–09, DEM-12, LEAK-* |
| **Efficiency** | —（仅审计，不替代质量 gate） | SLO-E-02/03, SLO-R-01, **DEM-13 / `sla_breach`** | DEM-10, DEM-11, DEM-13 |

**Efficiency owner（规格级）：** timing SSOT（`record-pipeline-timing`）、noop/duplicate_verify、**SLA breach 记账** — 与 Agent WO 协同，**不**用效率 SLO 放宽 R3 硬 gate。

---

## 2. DEM / LEAK → 可测信号（Part G 落地）

每个 DEM/LEAK 行在 goal-pipeline 上须能回答：**信号名、采集工件、聚合公式、切片维度、breach 行为**。

### 2.1 DEM 信号表（摘要 — 全表见 v1.1 Part G）

| ID | 可测信号（numerator / denominator 或事件） | 主采集面 | 切片 | Breach（默认） |
|----|---------------------------------------------|----------|------|----------------|
| DEM-01 | `failure_code=plan_code_order` 次数 / plan→implement 跃迁尝试 | gate JSON, `state` | tier, profile | **hard block**（既有） |
| DEM-02 | `empty_write_set` / plan+implement post | QC JSON | profile | hard block |
| DEM-03 | PQ fail 次数 / plan post | `plan-quality-gate` | dedupe_key | hard block |
| DEM-04 | `contract_stale`, IQ-10 / refresh 周期 | handoff + IQ JSON | unit | hard block（B7 normative） |
| DEM-05 | `handoff_missing`, doctor `handoff_ssot_drift` | chain validate, doctor | split tier | hard on complete 路径 |
| DEM-06 | `uvo_not_pass`, `verification_oracle_failed` | `verification-oracle.json` | write_set hash | hard block |
| DEM-07 | `am_ratchet_failed` | AM gate | matrix row id | hard block |
| DEM-08 | **纯误拦事件**：UVO fail 且全部失败用例路径 ∩ write_set 闭包 = ∅ | oracle steps + paths；`dem08_implement_warn` 标签 | fixture 标 | **政策层**：纯 DEM-08 + closure → implement warn-pass（#34）；**SLO-Q-01** 仍计量 |
| DEM-09 | `QG-01` / quality-gate fail | quality post | profile | hard block |
| DEM-10 | `noop_fix` / implement+review post 尝试 | `state`, fix-input | round | hard block（效率+质量） |
| DEM-11 | `duplicate_verify` / UVO 触发 | efficiency_plane | subject_hash | warn → 趋 0（SLO-R-03） |
| DEM-12 | `review_forged`, `review_degraded_as_pass` | review-chain, complete `quality_plane_check` | channel, provider | **hard on complete** |
| DEM-13 | 墙钟 > tier SLA 且 **无** `sla_breach` 或 timing 标记 | `pipeline-timing.json` stage/substep | tier, stage | **v1.2 前：warn + timing flag**；见 §4.3 |

### 2.2 LEAK（L1–L9 / L10）→ W1 / W2

| 漏出类 | W1 信号 | W2 信号 | 关联 stage（goal-pipeline 默认图） |
|--------|---------|---------|-----------------------------------|
| L1–L8 声明缺陷类 silent pass | `leakage.declared_defect_classes_silent_pass[]` 非空 | — | 全阶段 gate；**complete** 汇总 `quality_plane_check` |
| L9 矩阵语义 | W1 侧 rubric 软记账 | `matrix_rows_unsatisfied[]` / `delivery-quality.json` | **plan** 矩阵；**review** rubric；**complete** W2 记账 |
| L10 UX（B3 manifest） | manifest 行须 pass/waive/deferred；**禁止 silent pass** | 未 manifest 且未升 L9 → **不算** W2 L9 违约 | **plan post** manifest；**complete** W1 |

**SLO-W1-01 / SLO-W2-01** 定义与 v1.1 Part I 一致；目标 **0**（硬）— **本票 ratify**（结构 + 阈值，非新数字争议）。

---

## 3. SLO 注册表（ratified structure + breach behavior）

**切片（全指标）：** `task_tier` × `plan_profile` × `stage`（及 `substep` 若接线）× `fixture` 标签（如 `CTB-44243-260728`）。

**Wrapper 标注：** 同一 kernel 指标在 `review-run.json` 须带 `wrapper_profile`（`goal-review` | `guazi-flow-review` | adapter）；SLO 默认报表 **goal-pipeline 主轨** 过滤 `wrapper_profile=goal-review` 或 pure goal index 缺失时的 default single-track。

### 3.1 已 ratify（#41）— 数值或零目标

| ID | 定义（不变） | Ratified 目标 | Breach 行为 |
|----|--------------|---------------|-------------|
| **SLO-W1-01** | v1.1 I.1 | **0** | 不替代 gate；postmortem + leak panel |
| **SLO-W2-01** | v1.1 I.1 | **0**（无 separation waive） | complete / delivery-quality 审计 |
| **SLO-Q-02** | v1.1 I.1 | **0** | PQ/IQ dedupe 政策（Part H C1） |
| **SLO-R-02** | v1.1 I.1 | **0** on complete 路径 | chain validate + doctor |
| **SLO-E-01** | implement post 墙钟 p90 | **XS ≤25m, S ≤40m, M ≤70m, L ≤120m**（p90） | **warn** + timing；可选未来 **block** 仅当 profile `sla_enforce=hard`（v1.2） |

### 3.2 结构 ratify；**数值 → v1.2 校准票**（#41 resolution）

下列指标 **定义、采集面、owner、breach 默认** 在本研究稿 ratify；**具体 p90 带与比例阈值** 不在 Phase-5 地图 HITL 中强行数字，交由 **optimization-spec v1.2 校准子票**（见 §6）。

| ID | 结构 ratify | 校准方法（v1.2 须执行） | Breach（至 v1.2 数字落地前） |
|----|-------------|-------------------------|------------------------------|
| **SLO-Q-01** | DEM-08 误拦率 = 纯误拦次数 / UVO fail 次数（分母不含已 warn-pass 的纯 DEM-08 若 policy 标 `excluded_from_slo`） | ① 夹具 `260728-*` 回归集；② 生产 run `N≥30` / tier 分层；③ postmortem 标签 `dem08` 与 oracle 路径审计 | **审计 only**；不 block implement（与 #34 一致） |
| **SLO-E-02** | UVO 步耗时 p90 | `pipeline-timing` **substep=uvo**（B2 接线后）+ oracle `steps[].duration` 交叉校验 | warn |
| **SLO-E-03** | review 墙钟 p90 | `stage=review` + `review-run.json` `latency_ms` / `invocation_count` | warn |
| **SLO-R-01** | noop_fix 率 | 基线：goal-pipeline 主轨 30 run p90 | warn（提议带 **<10%** 写入 v1.2，#41 不 ratify 数字） |
| **SLO-R-03** | duplicate_verify 率 | UVO 触发 vs `duplicate_verify` code | warn；目标趋 0 |
| **SLO-B4-01**（新增注册） | degraded 通道 run 占比 / complete 拦截率 | 0-channel vs `separation=degraded` 分层；`review_degraded_as_pass` 在 complete 必须为 0 | 语义 **hard**；比例阈值 v1.2 |

**SLO-Q-01 与 v1.1 脚注：** v1.1 表中 **<5%** 保留为 **provisional hypothesis**，**非** Phase-5 地图 ratified 数字；#41 将数字显式 **defer 至 v1.2 校准**（夹具 + 生产样本）。政策验收仍跟踪 [#30](https://github.com/sophiezel/goal/issues/30)（implement post exit 0），与 SLO 带独立。

### 3.3 tier / profile 关系

- **lite（XS/S）：** SLO **质量类不降级**（W1/W2/Q-02/R-02）；**效率类** 可省略 doctor、dual review、部分 timing substep（profile 声明），但须在 `plan.json` / profile 显式列出 **skipped_slo_collectors**（避免 silent 无数据）。
- **strict：** 可启用 `sla_enforce`、goal-quality e2e BLOCK（#19）— v1.2 写 profile 键。
- **M/L/XL：** SLO-E-01 带适用；禁止压 tier 逃避墙钟（task-tier-matrix SSOT）。

---

## 4. B4 降级审核通道 · B2 timing · DEM-13

### 4.1 B4 — normative 语义（#40 ratified；数字 #41 → §3.2）

| 条件 | 通道状态 | review 轨 outcome | complete 护栏 |
|------|----------|-------------------|---------------|
| cross-provider 可用且 separation 满足 | `channel=full`（或 profile 等价） | 正常 pass/fail | `review_forged` 扫描 |
| **0 review channel**（detect 成功、列表为空） | `separation=degraded`；deterministic_scope_only | **非** full pass；产出 degraded 标记工件 | **`review_degraded_as_pass` 必须 fail** `quality_plane_check` |
| channel **不可达**（网络/配置） | blocked + Cursor hint（B6） | 不记为 degraded pass | 不 advance complete |

**可测信号（SLO-B4-01）：**

- `review-run.json`: `channel`, `separation`, `provider`, `invocation_count`, `latency_ms`
- `review-unified.json`: merge 结论与 separation 一致
- complete: `failure_code` 含 `review_degraded_as_pass` 计数 **= 0**（硬）

**Leakage：** degraded 轨 **不得** 计入 W1「独立审核已执行」的等价 full pass；若 matrix 要求 full review separation，degraded 仅当 profile **显式允许** 且 W2 记账 waive（separation），否则算 **LEAK / 流程漏出**（审计面，非 DEM-08）。

### 4.2 B2 — timing 全阶段 + substep（normative）

| 要求 | SSOT | SLO 挂钩 |
|------|------|----------|
| 每 stage pre/post 记录墙钟 | `record-pipeline-timing` → `pipeline-timing.json` | SLO-E-01（implement）、SLO-E-03（review） |
| **默认 substep（goal-pipeline v1.2 接线目标）** | `uvo`（implement post 内）、`review_chain`（review stage）、`quality_gate`（quality） | SLO-E-02、E-03 |
| smoke 阶段名 | **B1：** quality-only；timing 中 legacy `smoke` 阶段名 **deprecate**（删除时机 v1.2 文档票，inventory §6） | — |

### 4.3 DEM-13 / `sla_breach`

| 阶段 | 行为（#41 ratify） |
|------|-------------------|
| **v1.1 / Phase-5** | 超 SLO-E-01 带 → timing JSON `sla_warn=true`（或等价字段）；**不** 默认 block |
| **记账缺口闭合（实现轨）** | 引入 `failure_code=sla_breach`（P2 工程 + v1.2 spec）；与 DEM-13 一行对齐 catalog |
| **profile `sla_enforce=hard`（v1.2）** | 超带可 block complete 或 implement post（HITL 于 v1.2） |

**Owner：** Efficiency plane + timing scripts；Agent WO 不得跳过 timing gate 以规避 DEM-13 审计。

---

## 5. 独立审核 kernel 指标（跨 wrapper）

与 [#37](https://github.com/sophiezel/goal/issues/37) §3、inventory §2.1 对齐：

| 指标 | 定义 | 采集 |
|------|------|------|
| Review round 停滞 | 同 `subject_hash` 多轮 `invocation_count` 无进展 | `review-run.json` 序列 + `state` |
| Provider 分离违例 | implement provider == review provider（tier 要求分离时） | channel guard + run metadata |
| Review 墙钟 | review stage timing 与 chain sum 偏差 < ε（审计） | timing + `latency_ms` |
| Forged / degraded-as-pass | DEM-12 | complete `quality_plane_check` |

**goal-pipeline vs guazi：** 报表默认 **single-track + goal-review**；guazi dual 仅 **guazi 管线切片**，不进入 goal-pipeline 默认 SLO 达标定义（#40 B8）。

---

## 6. Part J / optimization-spec v1.2 输入（不合并全文）

**轴 1 B+C（#40）：** 规范正文在 **#41 闭合后** 开 **spec doc closure 票**（类 [#31](https://github.com/sophiezel/goal/issues/31)），将下列 bullets 写入 **v1.2 或 Part J append**。

### 6.1 Part J — add / borrow（来自 #38/#39/#41）

1. **add** — 本文 §3 SLO 注册表 + §2 信号表为 normative 附录。
2. **add** — B4 语义表（§4.1）+ complete 护栏；SLO-B4-01 注册。
3. **add** — B2 timing + 默认 substep 名（§4.2）。
4. **add** — DEM-13 / `sla_breach` 分阶段行为（§4.3）。
5. **add** — W1/W2 × stage 映射（§2.2）。
6. **add** — `wrapper_profile` 切片与 goal-pipeline 默认报表规则（§3）。
7. **borrow** — v1.1 Part F–I 全文；Part I 表用 §3 替换「TBD 行」的 ratification 状态。
8. **defer v1.2 校准票** — SLO-Q-01 带、SLO-E-02/03、SLO-R-01/03、SLO-B4-01 比例阈值；方法见 §3.2。

### 6.2 v1.2 校准票（建议标题，**不在 #41 开子票** unless map Notes 要求）

> **Task:** optimization-spec v1.2 — SLO numeric calibration + `sla_breach` code + timing substep default wiring

**输入：** 本文 §3.2、`pipeline-timing.json` 样本、`review-run.json` 样本、leak-rate-panel 输出。

### 6.3 reject（保持一致）

- goal-pipeline 默认 SLO 达标 **不** 包含 guazi dual-review 轨。
- SLO 聚合 **不得** 绕过既有 hard gate（v1.1 I.2）。

---

## 7. HITL 仍须用户确认的项（缩小范围）

| 项 | #41 处置 |
|----|----------|
| SLO-Q-01 **<5%** 是否保留为 v1.2 默认带 | **defer** — 校准票用数据定带 |
| `sla_enforce=hard` 是否进入默认 strict profile | **defer v1.2** |
| timing 删除 `smoke` 阶段名时间点 | **defer v1.2 文档**（方向 B1 已 normative） |
| Dashboard / 聚合脚本 | **P2**（tech-debt-p2） |

---

## 8. 结论

- **单一模型：** R1–R4 + DEM/LEAK + W1/W2 + SLO 注册表 + kernel B 审核指标，供 **goal-pipeline**  breaking-first 规格与实现图共用。
- **#41 ratify：** W1/W2/Q-02/R-02/E-01 零或 tier 带；**全体 breach 语义**；B4/B2/DEM-13 结构；**数值带**（含 Q-01、E-02/03、R-01/03、B4 比例）**explicit defer → v1.2 校准票**（§3.2、§6.2）。
- **下游：** map #36 在子票全闭合后建议开 **spec closure**（§6.1）；实现图从 Part J + [generic-services-inventory-phase5.md](generic-services-inventory-phase5.md) normative 行拆票。

---

## Changelog

| Date | Action |
|------|--------|
| 2026-08-02 | #41 research closure — unified SLO/quality model for goal-pipeline |

*Research asset — not implementation PR.*
