# Wayfinder 本地镜像

GitHub 主副本：[Wayfinder: Goal 交付质量与全链路效率优化（guazi-flow-goal 实战复盘）](https://github.com/sophiezel/goal/issues/1)

## Decisions so far（镜像）

- **Phase-1 engineering closure** — [`3ce9e6b`](https://github.com/sophiezel/goal/commit/3ce9e6b) Wayfinder P0/P1 bundle；[`c13431b`](https://github.com/sophiezel/goal/commit/c13431b) UVO `testPathPattern` 提示修复
- **Phase-2 C1 ratified (all axes)** — [phase-2-real-closure-grilling.md](research/phase-2-real-closure-grilling.md) Ratified 节；fe-argus hybrid、strict UX、matrix W2、P1-9 audit、节点 skip 原则
- **漏出计数 W1 + W2** — [#4](https://github.com/sophiezel/goal/issues/4#issuecomment-5145730400)（**closed**）
- **B3 L10 Argus manifest + L9 escalate-only** — [#4](https://github.com/sophiezel/goal/issues/4#issuecomment-5145856518)
- **UX 双轨发现 + C1 auto-fix / strict / a11y** — [#5](https://github.com/sophiezel/goal/issues/5)（**closed**；见 issue CONFIRM 评论）
- **IQ-10 handoff SSOT** — goal `d9bf079` 起 + implement 路径；jian-h5 CTB-44243 implement post **pass** — [run log](research/iq10-handoff-fix-run-log.md)

## 研究产物（已落盘）

| 工单 | 文件 | GitHub |
| --- | --- | --- |
| [#3 CTB-44243 复盘](https://github.com/sophiezel/goal/issues/3) | [ctb-44243-guazi-flow-goal-rca.md](research/ctb-44243-guazi-flow-goal-rca.md) | **closed** — RCA + P0/P1 goal 修复已落地 |
| [#2 节点清单](https://github.com/sophiezel/goal/issues/2) | [pipeline-node-catalog.md](research/pipeline-node-catalog.md) | **closed** — 研究完成；节点裁剪 HITL defer → 规格 v1 |
| [#6 review-chain](https://github.com/sophiezel/goal/issues/6) | [review-chain-bottlenecks.md](research/review-chain-bottlenecks.md) | **closed** — preflight / strict UX / `review_track` on `main` |
| [#7 timing 看板 v0](https://github.com/sophiezel/goal/issues/7) | [pipeline-timing-dashboard-v0.md](research/pipeline-timing-dashboard-v0.md) | **closed** — v0 规格采纳；HTML v1 defer |
| [#4 0 漏出](https://github.com/sophiezel/goal/issues/4) | [draft-zero-leakage-and-ux-policy.md](research/draft-zero-leakage-and-ux-policy.md) Part A | **closed** — W1+W2、A.8 B3 ratified |
| [#5 UX 边界](https://github.com/sophiezel/goal/issues/5) | 同上 Part B | **closed** — C1 ratified（见 issue CONFIRM） |

## 当前 Frontier — Phase-3 实质闭环

**Phase-2 基线：** C1 ratified + T1–T5 on [`f91181b`](https://github.com/sophiezel/goal/commit/f91181b)。Grilling SSOT：[phase-2-real-closure-grilling.md](research/phase-2-real-closure-grilling.md)。

| 轨道 | 工单 | 状态 |
| --- | --- | --- |
| fe-argus plan post 强制 skill 编排 | [#8](https://github.com/sophiezel/goal/issues/8) | open |
| #7 timing 看板 HTML v1 | [#9](https://github.com/sophiezel/goal/issues/9) | open |
| W2 L9 matrix satisfaction 自动化 | [#10](https://github.com/sophiezel/goal/issues/10) | open |
| guazi-flow-implement D2/D5 auto-fix + audit 契约 | [#11](https://github.com/sophiezel/goal/issues/11) | open |
| optimization-spec v1 正式稿 | [#12](https://github.com/sophiezel/goal/issues/12) | open |

| 阶段 | 状态 | 备注 |
| --- | --- | --- |
| **Phase-1** | **工程收口** | #2–#7 closed；P0/P1 在 `main` |
| **Phase-2** | **C1 + T1–T5 landed** | `f91181b` |
| **Phase-3** | **能力/规格真闭环** | 上表五轨；父地图 [#1](https://github.com/sophiezel/goal/issues/1) |

**合并稿入口：** [optimization-spec-outline-v0.md](research/optimization-spec-outline-v0.md)（草稿 v0.2；P1-7/8 为 rule-based v1，非 fe-argus LLM）

### Research 交叉结论（简）

| 主题 | #3 RCA | #2 catalog | #6 review |
| --- | --- | --- | --- |
| 阻断 implement | IQ-10 未读 Tier-R handoff → **已修** | timing 仅 gate 边界 | — |
| 漏出/质量 | UVO pass 但 IQ fail → **收紧** | smoke vs quality 双轨 | preflight 必留；dual Agent 耗时 |
| 效率 | noop_fix 掩盖 IQ-10 → **已修** | 子步骤 timing 已部分接线 | single track + detect cache（P2） |
| UX (#5) | manifest L10 + ux-scan | implement post warn | review-first strict；D2/D5 auto-fix |
