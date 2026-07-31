# Wayfinder Phase-3b：HITL 冻结（Grilling + Ratified C1）

**基准提交：** `4cc8e18`（`origin/main`）  
**Ratified：** 2026-08-01（用户拍板 **全部 Phase-3b grilling 项采用 C1**）  
**事实来源：** [phase-2-real-closure-grilling.md](phase-2-real-closure-grilling.md) §2.5 残余、`optimization-spec-outline-v0.md` §未决、GitHub [#13](https://github.com/sophiezel/goal/issues/13)–[#16](https://github.com/sophiezel/goal/issues/16)、[#20](https://github.com/sophiezel/goal/issues/20)、[#12](https://github.com/sophiezel/goal/issues/12)

**工程优先级（ratified）：** [#14](https://github.com/sophiezel/goal/issues/14) split handoff SSOT → [#17](https://github.com/sophiezel/goal/issues/17) four_planes_doctor handoff tier → [#23](https://github.com/sophiezel/goal/issues/23) review kernel CLI merge-review parity

---

## Ratified C1（2026-08-01，#1）

| 工单 | C1 摘要 | SSOT 落点 |
|------|---------|-----------|
| **#13** lite profile 节点 skip 冻结表 | **ratchet 不可 skip**（拒绝 C2 warn-only）；**lite argus 仅 rule v1**（不调 fe-argus skill ②）；**遗留 `gate stage smoke` 默认 hard-disable**（仅 `GOAL_ALLOW_LEGACY_SMOKE_STAGE=1` 逃逸）；**review `single`**（XS/S + `plan_profile=lite`）；**doctor / timing substep 可选**；**`merge-review-issues` 不可 skip**；**complete 路径 `quality_plane_check` 不可 skip** | [pipeline-node-catalog.md](pipeline-node-catalog.md) Profile 三档表 |
| **#15** PQ / IQ 重复校验 | **分层 + dedupe：** PQ **规划面** hard（冻结契约）；IQ **实现面** hard（`src` 绑定）；同一契约键 **PQ 已 block 则 IQ 不二次 block**（同 `dedupe_key` 仅记一次 W1 hard）；IQ 对 PQ 已覆盖项 **warn + `dedupe_key`** 留痕 | [optimization-spec-outline-v1.md](optimization-spec-outline-v1.md) §PQ/IQ；[draft-zero-leakage-and-ux-policy.md](draft-zero-leakage-and-ux-policy.md) open Q5 **closed** |
| **#16** AM waive + W2 漏出 | **有效 separation 的 waive 不计入** `leakage.matrix_rows_unsatisfied[]`；可选审计面 **`leakage.matrix_rows_waived[]`**（行 id、separation 指针、waive 理由）；**无 separation 的 waive / 未满足行 → W2 漏出**（入 `matrix_rows_unsatisfied`） | [draft-zero-leakage-and-ux-policy.md](draft-zero-leakage-and-ux-policy.md) A.5、open Q1–2 **closed**；v1 spec §W2 |
| **#20** Part A.1 北星对外措辞 | **对内北星不变：** 声明缺陷类 → no silent pass（非「零生产 bug」）；**对外默认 W1** 一句话；**W2 须显式声明**（矩阵 / MR 窗口） | [draft-zero-leakage-and-ux-policy.md](draft-zero-leakage-and-ux-policy.md) A.1、A.3；v1 spec Part A.1 |
| **#12** optimization-spec v1 formal | **v1 = 文档与决策收口**（关闭 §未决）；**实现 deferred** 链到 Phase-3 子工单（#8–#11、#14、#17、#23 等），不在本 ratification 包内冒充已落地 | [optimization-spec-outline-v1.md](optimization-spec-outline-v1.md) |

---

## 1. Phase-3b Grilling Pack（归档）

格式：**C1 = ratified**；**C2 = 未采纳**；供 issue 评论与后续实现引用。

---

### 1.1 [#13] lite profile 节点 skip 冻结表

| 节点 | **C1（ratified）** | C2（未采纳） |
|------|-------------------|--------------|
| `acceptance-matrix-ratchet` | **不可 skip**（lite 与 standard 同硬闸门） | lite warn-only ratchet |
| plan post Argus | **lite：仅 `argus_enrich_plan.py` rule v1**；standard/strict：Phase-2 hybrid v2（规则 + 条件 fe-argus） | lite 完全跳过 manifest |
| `gate stage smoke`（遗留） | **默认 hard-disable**；`handoff/quality.json` 存在时拒绝直调 smoke（已有）；逃逸 `GOAL_ALLOW_LEGACY_SMOKE_STAGE=1` | 默认可直调 smoke |
| `guazi-flow-review` dual track | **`review_track=single`**（XS/S + `plan_profile=lite` 默认；与 `review_track.py` 一致） | dual 为 lite 默认 |
| `four_planes_doctor` | **可选**（Wave / meta） | complete 强制 doctor |
| timing `substep` | **可选**（#9 HTML v1 不阻塞） | 强制 substep + SLA breach code |
| `merge-review-issues` | **不可 skip**（kernel CLI 路径须 parity → #23） | CLI 路径可 bypass merge |
| `quality_plane_check` | **complete 路径不可 skip** | lite complete 跳过平面检查 |

**C1 裁剪原则（延续 Phase-2）：** 仅效率面（遗留 smoke、doctor、timing substep）可 skip；质量面节点不因 lite 默认跳过。

---

### 1.2 [#15] PQ / IQ 重复校验分层

| | **C1（ratified）** | C2 | C3 |
|---|-------------------|-----|-----|
| **方案** | PQ hard on **冻结契约**（index / API 表 / write_set / 矩阵列头）；IQ hard on **实现绑定**（IQ-10、`contract-conformance`）；重复键共享 **`dedupe_key`**（如 `api:POST:/path`、矩阵 `C#` id） | 单一平面负责，另一平面 skip | 双 hard，重复失败双记 W1 |
| **重复时行为** | PQ fail → plan post block；IQ 见同键且 PQ 已 fail → **不二次 block**；PQ pass + IQ fail → implement block；PQ 已覆盖字段 IQ 仅 **warn** + dedupe 留痕 | — | — |
| **lite** | PQ-01/02/05/07 **不降级**；IQ `--skip-test-lint` 仍为效率分工（非 PQ 重复项） | — | — |

---

### 1.3 [#16] AM waive + separation ↔ W2

| | **C1（ratified）** | C2 |
|---|-------------------|-----|
| **waive + 有效 separation** | **不算** `leakage.matrix_rows_unsatisfied[]`；记入可选 **`leakage.matrix_rows_waived[]`** | waive 一律算 W2 漏出 |
| **无 separation 的 waive** | **算 W2 漏出**（与 L4/L8 silent pass 同类叙事） | — |
| **complete 闸门** | 仍仅 **ratchet verify 绑定行** fail → `am_ratchet_failed`；纯语义 L9 / W2 记账不新增 complete 硬拦（延续 Phase-2 matrix C1） | complete 因任意 matrix 未满足硬 block |

**separation 最低要求（C1）：** index / decisions / PR 评论 / `evidence/` 中可解析的 **scope 切割或 out-of-scope 声明** + 指向 waive 的矩阵行 id。

---

### 1.4 [#20] Part A.1 北星 — 对外措辞（W1 vs W2）

**对内北星（不变）：** Goal 语境「0 漏出」= 当次 **已声明缺陷类** 上 **no silent pass**（[`failure-code-dictionary`](../../../goal-pipeline/references/failure-code-dictionary.md)）；**不是**线上零 bug。

**对外模板（ratified C1）：**

| 场景 | 默认窗口 | 一句话（可复制） |
|------|----------|------------------|
| **工程 / 闸门** | **W1**（单次 `init`→`complete`） | 「本单 Goal run（W1）在已启用闸门对应的**声明缺陷类**上无 silent pass；`quality_plane_check` 与 W1 记账通过。」 |
| **产品 / MR 验收** | **W2**（须**显式写出**） | 「本 MR（W2）在 index **验收矩阵已声明行**上：满足、或 **带 separation 的 waive** 已记账；`matrix_rows_unsatisfied` 仅含**无 separation** 的未满足行。」 |
| **禁止混说** | — | 不得用 W1 pass 代替 W2 矩阵承诺；不得用「0 漏出」暗示生产零缺陷。 |

**W3（发布后 N 天）：** 仅运营复盘反馈 spec，**不**作为对外默认「0 漏出」口径。

---

### 1.5 [#12] optimization-spec v1 formal

| | **C1（ratified）** |
|---|-------------------|
| **范围** | 关闭 v0 §未决；合并 Phase-2 + Phase-3b ratified 轴进 **v1 大纲** |
| **非范围** | fe-argus skill orchestration（#8）、W2 自动化（#10）、D2/D5 audit（#11）、split handoff（#14）、doctor tier（#17）、merge-review parity（#23）等 **实现** — 仅 v1 文内 deferred 链接 |
| **产物** | [optimization-spec-outline-v1.md](optimization-spec-outline-v1.md)；v0.2 保留历史并指向 v1 |

---

## 2. Draft：GitHub Issue #1 评论（Decisions so far 增补）

```markdown
## Phase-3b HITL — all C1 ratified (2026-08-01)

- **#13** lite skip 冻结表：ratchet 不 skip；lite argus rule-only；legacy smoke hard-disable；review single；doctor/timing 可选；merge-review / quality_plane_check 不 skip → [pipeline-node-catalog.md](https://github.com/sophiezel/goal/blob/main/docs/wayfinder/research/pipeline-node-catalog.md)
- **#15** PQ/IQ 分层 + dedupe_key warn；IQ hard 实现面；PQ 同键不 double block
- **#16** AM waive + separation：有效 waive 不进 `matrix_rows_unsatisfied`；可选 `matrix_rows_waived`；无 separation = 漏出
- **#20** 对外默认 W1 措辞；W2 须显式；北星非零生产 bug
- **#12** optimization-spec **v1 文档收口**（实现 → Phase-3 子 issue）

**工程顺序：** #14 → #17 → #23

Ref: [phase-3-hitl-ratified.md](https://github.com/sophiezel/goal/blob/main/docs/wayfinder/research/phase-3-hitl-ratified.md)
```

---

## 3. 仍 open（不在本包 ratification 内）

| 主题 | 工单 |
|------|------|
| split handoff SSOT（`task_dir/handoff` vs `artifacts/handoff`） | [#14](https://github.com/sophiezel/goal/issues/14) |
| W2 L9 矩阵满足度自动化 | [#10](https://github.com/sophiezel/goal/issues/10) |
| fe-argus skill @ plan post | [#8](https://github.com/sophiezel/goal/issues/8) |
| ~~CTB-44243 附录回写~~ | **done** — [#22](https://github.com/sophiezel/goal/issues/22) → [ctb-44243-guazi-flow-goal-rca.md](ctb-44243-guazi-flow-goal-rca.md) §8 |

---

*Phase-3b Wayfinder HITL ratification pack；父地图 [#1](https://github.com/sophiezel/goal/issues/1)。*
