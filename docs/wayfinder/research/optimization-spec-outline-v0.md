# 优化规格大纲 v0（Research 合并稿）

**Status:** 草稿 v0.1 — [#4](https://github.com/sophiezel/goal/issues/4) / [#5](https://github.com/sophiezel/goal/issues/5) 核心策略已 ratified（2026-08-01）；本稿已回写 UX/L10 硬约束，待 Part A 开放题（L9 `failure_code` 等）收尾后升格正式规格。

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

4. **声明缺陷类 silent pass**  
   与草案 Part A 对齐：UVO pass + IQ-10 fail 仍算质量面未完成，不得进入 review（待 #4 confirm）。

5. **review preflight 不可跳过**  
   PKT-01–04 与 packet 截断策略（[#6](review-chain-bottlenecks.md)）写入 review 规格硬约束。

6. **W1 + W2 漏出计数（#4 ratified）**  
   - **W1**（单次 run）：L1–L8 + **已声明 L10 manifest 行**须 pass / waive / deferred，**禁止 silent pass**；`leakage.declared_defect_classes_silent_pass[]` 为空 + `quality_plane_check` 为「0 漏出」必要条件。  
   - **W2**（MR 合入）：L9 / 验收矩阵 satisfied；Goal 只保证 W1 证据链完整。  
   - **Q11（closed）：** 未 manifest 且未升 L9 的 UX **不算 W2 L9 违约**；**已 manifest 的 L10 在 W1 仍须记账** — 与「未声明不计漏出」不矛盾（见 [draft](draft-zero-leakage-and-ux-policy.md) A.3、open Q11）。

---

## P1 — UX 面（#4 A.8 B3 + #5 C1 硬约束）

> SSOT：[draft-zero-leakage-and-ux-policy.md](draft-zero-leakage-and-ux-policy.md) Part A §A.8、Part B C1；[goal-delivery-quality-optimization.md](../goal-delivery-quality-optimization.md) Frontier。

7. **Plan post — L10 Argus manifest（B3）**  
   - 输入：`index.md`、`write_set`、页面域路径等 plan 已冻结工件；**fe-argus Scenario Q** INDEX on-demand（禁止全量 `scenarios/` 扫描）。  
   - 产物：`<task>/handoff/argus-scenario-manifest.json`（scenario id、默认 `soft`、关联路径、建议 verify）；SSOT 为 handoff，index 附录可选摘要。  
   - 下游：implement / review / complete **只读消费**，作 UX-D*、rubric、fix-input 指导清单；**不得**在无 manifest 行时凭空新增 L9 矩阵义务。  
   - 默认 **L10 = soft**：implement post 仅 warn / UX debt，**不因 L10 alone** hard-block implement post。

8. **Implement post — UX 扫描 v1（双轨发现之二）**  
   - **v1 覆盖 UX-D1 / D2 / D5**；产物 `evidence/ux-scan.json`，默认 **warn**，不替代 UVO。  
   - **UX-D3 / D4 / D6 → v2 defer**，不纳入 v1 自动扫描闸门。  
   - 与 plan post L10 manifest **并列消费**；IQ-10 **不**覆盖骨架屏形态（UX-D* 非契约漂移，除非矩阵/decisions 声明）。

9. **Auto-fix 授权（C1 narrow）**  
   - **仅 UX-D2、UX-D5**；diff **严格在 write_set 内**；禁止路由/新页/流程/API 语义变更。  
   - **UX-D1**（如 skeleton 内 footer CTA）：recommend only，**禁止默认 auto-fix** → review-fix-input。  
   - **Profile：** XS/S — D2/D5 auto-fix **无额外 HITL**；S+ / M+ 或显式配置可提高人工介入（见草案 B.5 表）。

10. **Strict tier 与 fail 路由（review-first）**  
    - `quality` tier=**strict**：UX tag / manifest / ux-scan 违反 → **review 必 fail**（review-first）。  
    - **禁止**仅凭 L10 或 manifest alone 在 implement post 硬 block。  
    - Review fail（UX/L10）：**fix-input** 或显式 **waive**（带 separation）；**禁止**引擎自动写入矩阵 **C#** 或静默升格 L9。  
    - **L9 阻断**仅人工升级：矩阵 C#/V# 行或 HITL confirm；未升级前按 L10 soft 路由。

11. **Complete / W1 收口**  
    - 已声明 **L10 行**在 complete 须 pass / waive / deferred 入账 measure / evidence（与 P0 §6 W1 对齐）。  
    - a11y（D5）：信号优先 **业务仓 write_set 路径**上 `eslint` + `eslint-plugin-jsx-a11y`；Goal **汇总**入 `ux-scan.json`，不在 pipeline 内维护平行规则表（B.8）。

---

## P1 — 效率面

12. **timing 子步骤落盘**  
   生产路径接线 UVO steps、review attempt、cwiki（catalog § timing 缺口）；支撑 [#7](https://github.com/sophiezel/goal/issues/7) 看板。

13. **review 默认路径**  
   XS/S 优先 `review_track=single` + detect cache；dual Agent 仅 M+ 或显式配置（#6 P0 瓶颈）。

14. **gate 栈去重**  
   评估废弃独立 `--stage smoke` 调用路径，与 advance-only `quality` 单一事实（catalog 冗余项 1–3）。

---

## P2 — 契约提取

15. **H5 `createRequest` 提取器**  
   支持 `req({ uri })` 工厂模式，减少 `as never` 契约锚点（RCA §4 + #3）。

---

## 未决（阻塞规格定稿）

- #4（残余）：`matrix_row_unsatisfied` 是否入 `failure-codes.json`、AM waive 是否算漏出、Part A.1 北星措辞  
- #5：**C1 / B3 / Q11 已 ratify** — 本稿 §7–11 为硬约束摘要；实现落点见 goal-pipeline 规格迭代  
- #7：耗时看板 prototype（节点命名以 #2 catalog 为准）
