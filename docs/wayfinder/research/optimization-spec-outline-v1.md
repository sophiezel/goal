# 优化规格大纲 v1（决策收口）

**Status:** **v1.0 — 文档与 HITL 决策收口**（2026-08-01）；实现项以文中 **Deferred** 链到 Phase-3 子工单，不以本文冒充已落地代码。

**前身:** [optimization-spec-outline-v0.md](optimization-spec-outline-v0.md)（v0.2 工程合并稿）  
**Ratification SSOT:** [phase-3-hitl-ratified.md](phase-3-hitl-ratified.md)  
**父地图:** [Wayfinder #1](https://github.com/sophiezel/goal/issues/1)

| 来源 | 文档 |
| --- | --- |
| Phase-2 C1 | [phase-2-real-closure-grilling.md](phase-2-real-closure-grilling.md) Ratified 节 |
| Phase-3b C1 | [phase-3-hitl-ratified.md](phase-3-hitl-ratified.md) |
| 漏出 / UX | [draft-zero-leakage-and-ux-policy.md](draft-zero-leakage-and-ux-policy.md) |
| 节点 | [pipeline-node-catalog.md](pipeline-node-catalog.md) |

---

## Part A — 「0 漏出」与对外口径（#4 / #20）

### A.1 North star（对内）

与 [draft-zero-leakage-and-ux-policy.md](draft-zero-leakage-and-ux-policy.md) A.1 一致：**声明缺陷类 → no silent pass**；不是「线上零 bug」。

### A.1 对外措辞（#20 C1 ratified）

| 受众 | 默认窗口 | 模板 |
|------|----------|------|
| 工程 / 闸门 | **W1** | 本单 Goal run（W1）在已启用闸门对应的声明缺陷类上无 silent pass；`quality_plane_check` 与 W1 记账通过。 |
| 产品 / MR | **W2（须显式声明）** | 本 MR（W2）在 index 验收矩阵已声明行上：满足、或带 **separation** 的 waive 已记账；`matrix_rows_unsatisfied` 仅含无 separation 的未满足行。 |

禁止：用 W1 pass 代替 W2 矩阵承诺；对外「0 漏出」暗示生产零缺陷。

### A.2–A.8

见 draft Part A（L1–L10、B3 L10 manifest、W1+W2 并行计数）。**v0 P0/P1 实现状态**仍以 v0.2 勾选为准。

### W2 矩阵行记账（#16 C1 ratified）

| 字段 | 语义 |
|------|------|
| `leakage.matrix_rows_unsatisfied[]` | 矩阵行 id：**未满足**且 **无有效 separation 的 waive** |
| `leakage.matrix_rows_waived[]`（可选审计） | 行 id、separation 证据指针、waive 理由；**不计入 unsatisfied** |
| `matrix_row_unsatisfied`（failure-code） | Phase-2 C1：`silent_pass_forbidden: false`；**不**默认 block implement/complete |

**Deferred 实现:** [#10](https://github.com/sophiezel/goal/issues/10) W2 L9 自动化、`measure-field-template.json` 字段与脚本对齐。

---

## Part B — UX（#5）

见 draft Part B C1（双轨 D1/D2/D5、L10 manifest、strict review-first、D2/D5 narrow auto-fix）。

**Deferred 实现:** [#11](https://github.com/sophiezel/goal/issues/11) implement D2/D5 audit；[#8](https://github.com/sophiezel/goal/issues/8) fe-argus skill orchestration（standard/strict plan post）。

---

## Part C — Profile 与节点 skip（#13 C1 ratified）

**SSOT 三档表:** [pipeline-node-catalog.md](pipeline-node-catalog.md) §「Profile：lite | standard | strict」。

要点：lite **不**降级 ratchet、**不**跳过 merge-review / complete `quality_plane_check`；lite plan post **仅 rule v1** Argus；遗留 smoke **默认 hard-disable**。

---

## Part D — PQ / IQ 分层（#15 C1 ratified）

| 平面 | 职责 | 默认严重度 |
|------|------|------------|
| **PQ** | 冻结契约：index 结构、API 表、write_set、矩阵列头（PQ-01..14 子集） | 应拦则 **hard**（plan post block） |
| **IQ** | 实现绑定：IQ-10、`contract-conformance`、structural QC | 契约漂移 **hard**（implement post block） |

**Dedupe（同 `dedupe_key`）：**

1. PQ 已 **fail** → IQ **不二次 block**（单键单次 W1 hard 记账）。
2. PQ 已 **pass** 且 IQ 对同一键 fail → implement **block**。
3. PQ 已覆盖、IQ 重复探测 → **warn** + `dedupe_key` 写入 IQ/PQ 留痕（避免 warn storm 升级为双 hard）。

**lite:** PQ-01/02/05/07 **不降级**；IQ `--skip-test-lint` 为与 UVO 分工，**非** PQ 契约重复项 skip。

**Deferred 实现:** `plan-quality-gate.py` / `implement-qc-gate.py` 显式 `dedupe_key` 字段与 fixture（无 issue 单开时可挂在 #15 或 #14 后续 PR）。

---

## Part E — Phase-2 C1 轴（已 ratified，v0 已部分落地）

| 轴 | 规格 | 实现备注 |
|----|------|----------|
| fe-argus v2 hybrid | 规则 manifest + 条件 fe-argus merge | rule v1 ✅；skill ② → **#8** |
| strict UX 分层 | hard/blocker L10 + ux-scan blocker only | ✅ `review_strict_ux.py` |
| matrix W2 | `matrix_rows_unsatisfied` + codes | 记账部分 ✅；waive 口径 **#16 已决**；自动化 **#10** |
| P1-9 auto-fix | skill 执行 + gate audit | audit → **#11** |
| split handoff | IQ / AM / UX 同根 — [handoff-path-resolution.md](../../../goal-pipeline/references/handoff-path-resolution.md) | **#14** ✅ |
| merge-review parity | kernel CLI ≡ shell chain | **#23** |
| four_planes_doctor + handoff tier | [four-planes-handoff-tier.md](four-planes-handoff-tier.md) | **#17** ✅ |
| timing HTML v1 | [pipeline-timing-report-input.md](../../../goal-pipeline/references/pipeline-timing-report-input.md) + `render-pipeline-timing-report.py --format html` | **#9** ✅ |
| postmerge ↔ complete | 平面衔接 | **#18** |
| goal-quality e2e profile | tier 对齐 | **#19** |
| CTB 附录 | #3 回写 | **#22** |

---

## Changelog

| Date | Version | Action |
|------|---------|--------|
| 2026-08-01 | v1.0 | Phase-3b HITL 全 C1 收口；关闭 v0 §未决；实现 deferred 链 Phase-3 表 |
| 2026-08-01 | v0.2 | 见 [optimization-spec-outline-v0.md](optimization-spec-outline-v0.md) |

---

*Formal spec outline v1 — issue [#12](https://github.com/sophiezel/goal/issues/12) doc closure; code follows child issues.*
