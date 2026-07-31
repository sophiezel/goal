# 优化规格大纲 v0（Research 合并稿）

**Status:** 草稿 v0.2 — P0/P1/P2 Wayfinder 实现项已回写（2026-08-01）；Part A 开放题（`matrix_row_unsatisfied` 等）仍阻塞正式规格升格。

**父地图:** [Wayfinder #1](https://github.com/sophiezel/goal/issues/1)

| 来源 | 文档 |
| --- | --- |
| [#3 RCA](https://github.com/sophiezel/goal/issues/3) | [ctb-44243-guazi-flow-goal-rca.md](ctb-44243-guazi-flow-goal-rca.md) |
| [#2 节点表](https://github.com/sophiezel/goal/issues/2) | [pipeline-node-catalog.md](pipeline-node-catalog.md) |
| [#6 review-chain](https://github.com/sophiezel/goal/issues/6) | [review-chain-bottlenecks.md](review-chain-bottlenecks.md) |
| [#4/#5 草案](https://github.com/sophiezel/goal/issues/4) | [draft-zero-leakage-and-ux-policy.md](draft-zero-leakage-and-ux-policy.md) |

---

## P0 — 数据面 + 控制面（阻断 CTB-44243 类 run）

1. **IQ-10 handoff SSOT 与 split layout 对齐** — **✅ 已验证**（goal `d9bf079`；CTB-44243 implement post gate exit 0；见 [iq10-handoff-fix-run-log.md](iq10-handoff-fix-run-log.md)）

2. **plan `write_set` 规范化** — **✅** `normalize_write_set_json` + `index_contract_hash.normalize_write_set`（plan post `plan.json`）。

3. **noop_fix 因果链** — **✅** gate fix-input 合并上轮 blocker 并排序（实质 blocker 优先于 G000）；见 `gate-guazi-flow-stage.sh` `check_noop_ratchet` / `write_gate_fix_input`。

**实现约束：** goal-pipeline / guazi-flow-goal 脚本与门禁须保持 **profile / 业务仓无关**——路径来自 `GOAL_TASK_DIR`、`GOAL_REPO_ROOT`、`GOAL_HANDOFF_DIR` 与 manifest/profile JSON；样本任务仅出现在 `docs/wayfinder/research/*`，不得被脚本 import 或硬编码。

---

## P0 — 质量面（漏出风险）

4. **声明缺陷类 silent pass** — **✅ 2026-08-01** `quality_plane_check.py`（L10 **hard/升级** 与 ux-scan **blocker**、`declared_defect_silent_pass`；默认 **soft+open 不拦 complete**）；complete / assert-complete 强制；review-pre 校验 UVO overall + IQ-10 `contract-conformance.json`。

5. **review preflight 不可跳过** — **✅ 2026-08-01** PKT-01–04 规格：`goal-pipeline/references/review-packet-hard-constraints.md`；`assemble-review-packet.sh`、`gate-lib/review.sh`、`goal-run-review-chain.sh` 硬断言。

6. **W1 + W2 漏出计数（#4 ratified）** — **✅ 2026-08-01（W1 记账）** `w1_leakage_bookkeeping.py` → `delivery-quality.json` `leakage.*`；complete post 与 `delivery_report.py` 汇总；W2/L9 仍宿主矩阵义务。

---

## P1 — UX 面（#4 A.8 B3 + #5 C1 硬约束）

> SSOT：[draft-zero-leakage-and-ux-policy.md](draft-zero-leakage-and-ux-policy.md) Part A §A.8、Part B C1；[goal-delivery-quality-optimization.md](../goal-delivery-quality-optimization.md) Frontier。

7. **Plan post — L10 Argus manifest（B3）** — **✅ v1 rule-based（非 fe-argus LLM）**  
   - 输入：`index.md`、`write_set`、页面域路径等 plan 已冻结工件；**v1** 由 `argus_enrich_plan.py` 路径/关键词启发式生成（**非** fe-argus Scenario Q INDEX on-demand；该检索留后续迭代）。  
   - 产物：`<task>/handoff/argus-scenario-manifest.json`（scenario id、默认 `soft`、关联路径、建议 verify）；SSOT 为 handoff，index 附录可选摘要。  
   - 下游：implement / review / complete **只读消费**，作 UX-D*、rubric、fix-input 指导清单；**不得**在无 manifest 行时凭空新增 L9 矩阵义务。  
   - 默认 **L10 = soft**：implement post 仅 warn / UX debt，**不因 L10 alone** hard-block implement post；complete 仅 **hard/升级** 行阻断。

8. **Implement post — UX 扫描 v1（双轨发现之二）** — **✅ v1 rule-based（`ux_scan_v1.py`）**  
   - **v1 覆盖 UX-D1 / D2 / D5**（write_set 内启发式）；产物 `evidence/ux-scan.json`，默认 **warn**，不替代 UVO。  
   - **非** fe-argus / LLM 视觉审查；**UX-D3 / D4 / D6 → v2 defer**，不纳入 v1 自动扫描闸门。  
   - 与 plan post L10 manifest **并列消费**；IQ-10 **不**覆盖骨架屏形态（UX-D* 非契约漂移，除非矩阵/decisions 声明）。

9. **Auto-fix 授权（C1 narrow）** — **✅ 规格**（草案 C1）；实现：`ux_scan_v1` + write_set 内 auto-fix 策略由宿主 skill 消费，Goal 不硬编码业务路由。

10. **Strict tier 与 fail 路由（review-first）** — **✅ 2026-08-01** `review_strict_ux.py` + `merge_review_core`：strict 下仅 **hard/escalated L10** 与 ux-scan **blocker/hard** 未处置 → review blocker；**soft/warn/info** 不 fail review（与 B3 L10 soft 一致）；implement post 不因 L10 alone 硬 block（既有）。

11. **Complete / W1 收口** — **✅ 2026-08-01** 见 P0 §6 + `quality_plane_check` complete 路径。

---

## P1 — 效率面

12. **timing 子步骤落盘** — **✅**（`record-pipeline-timing.py` / `sync_timing_substeps.py`；见 548d1f7 区域）。

13. **review 默认路径** — **✅ 2026-08-01** plan post 写入 `plan.json` `review_policy` + state persist；`review_track.py` XS/S + `plan_profile=lite` → `single`（`--auto-resolve-xs-s`）。

14. **gate 栈去重** — **✅ 2026-08-01** 存在 `handoff/quality.json` 时 `--stage smoke` 默认拒绝（`GOAL_ALLOW_LEGACY_SMOKE_STAGE=1` 逃逸）；advance 仍用 quality。

---

## P2 — 契约提取

15. **H5 `createRequest` 提取器** — **✅ 2026-08-01** `contract_parser.extract_h5_bindings` 第二遍 factory `req({ uri })`；fixture `contract-iq10-factory`。

---

## 未决（阻塞规格定稿）

- #4（残余）：`matrix_row_unsatisfied` **已入 failure-codes（W2 stub）**；AM waive 是否算漏出、Part A.1 北星措辞  
- #5：**C1 / B3 / Q11 已 ratify** — 本稿 §7–11 为硬约束摘要；实现落点见 goal-pipeline 规格迭代  
- #7：耗时看板 prototype（节点命名以 #2 catalog 为准）
