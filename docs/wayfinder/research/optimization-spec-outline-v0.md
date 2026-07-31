# 优化规格大纲 v0（Research 合并稿）

**Status:** 草稿 — 待 [#4](https://github.com/sophiezel/goal/issues/4) / [#5](https://github.com/sophiezel/goal/issues/5) HITL 拍板后升格为正式规格。

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

2. **plan `write_set` 规范化**  
   gate post plan 写入 Tier-R `plan.json` 时剥离 API 路径、补全 `src/` 前缀（AM-07 / iter_write_set_files）。

3. **noop_fix 因果链**  
   implement post 失败时 fix-input 应优先暴露 **末位 blocker**（如 IQ-10），避免仅 G000 掩盖根因（RCA C-2）。

---

## P0 — 质量面（漏出风险）

4. **声明缺陷类 silent pass**  
   与草案 Part A 对齐：UVO pass + IQ-10 fail 仍算质量面未完成，不得进入 review（待 #4 confirm）。

5. **review preflight 不可跳过**  
   PKT-01–04 与 packet 截断策略（[#6](review-chain-bottlenecks.md)）写入 review 规格硬约束。

---

## P1 — 效率面

6. **timing 子步骤落盘**  
   生产路径接线 UVO steps、review attempt、cwiki（catalog § timing 缺口）；支撑 [#7](https://github.com/sophiezel/goal/issues/7) 看板。

7. **review 默认路径**  
   XS/S 优先 `review_track=single` + detect cache；dual Agent 仅 M+ 或显式配置（#6 P0 瓶颈）。

8. **gate 栈去重**  
   评估废弃独立 `--stage smoke` 调用路径，与 advance-only `quality` 单一事实（catalog 冗余项 1–3）。

---

## P2 — 契约提取

9. **H5 `createRequest` 提取器**  
   支持 `req({ uri })` 工厂模式，减少 `as never` 契约锚点（RCA §4 + #3）。

---

## 未决（阻塞规格定稿）

- #4：漏出计数 **W1+W2 已 ratify**；待定 `matrix_row_unsatisfied` failure_code、Part A.1 北星  
- #5：UX 扫描 tier、auto-fix 与 write_set  
- #7：耗时看板 prototype（节点命名以 #2 catalog 为准）
