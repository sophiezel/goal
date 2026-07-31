# Wayfinder 本地镜像

GitHub 主副本：[Wayfinder: Goal 交付质量与全链路效率优化（guazi-flow-goal 实战复盘）](https://github.com/sophiezel/goal/issues/1)

## Decisions so far（镜像）

- **漏出计数 W1 + W2** — [#4](https://github.com/sophiezel/goal/issues/4#issuecomment-5145730400)
- **B3 L10 Argus manifest + L9 escalate-only** — [#4](https://github.com/sophiezel/goal/issues/4#issuecomment-5145856518)
- **UX 双轨发现 + C1 auto-fix / strict / a11y** — [#5](https://github.com/sophiezel/goal/issues/5)（见 issue CONFIRM 评论）
- **IQ-10 handoff SSOT** — goal `d9bf079`；jian-h5 CTB-44243 implement post **pass** — [run log](research/iq10-handoff-fix-run-log.md)

## 研究产物（已落盘）

| 工单 | 文件 | GitHub |
| --- | --- | --- |
| [#3 CTB-44243 复盘](https://github.com/sophiezel/goal/issues/3) | [ctb-44243-guazi-flow-goal-rca.md](research/ctb-44243-guazi-flow-goal-rca.md) | issue 有评论，**未 close** |
| [#2 节点清单](https://github.com/sophiezel/goal/issues/2) | [pipeline-node-catalog.md](research/pipeline-node-catalog.md) | [#2 评论](https://github.com/sophiezel/goal/issues/2#issuecomment-5145681202) |
| [#6 review-chain](https://github.com/sophiezel/goal/issues/6) | [review-chain-bottlenecks.md](research/review-chain-bottlenecks.md) | issue 有评论 |
| [#4 0 漏出](https://github.com/sophiezel/goal/issues/4) | [draft-zero-leakage-and-ux-policy.md](research/draft-zero-leakage-and-ux-policy.md) Part A | **closed** — W1+W2、A.8 B3 ratified |
| [#5 UX 边界](https://github.com/sophiezel/goal/issues/5) | 同上 Part B | **closed** — C1 ratified（见 issue CONFIRM） |

## 当前 Frontier

| 工单 | 状态 | 下一步 |
| --- | --- | --- |
| #4 Grilling 0 漏出 | **closed**（核心 ratify ✓） | Part A 开放题（L9 failure_code、AM waive 等）随规格 v1 收尾 |
| #5 Grilling UX 边界 | **closed**（C1 ratified） | 回写 `optimization-spec-outline-v0.md` UX 硬约束 |
| [#7 耗时看板](https://github.com/sophiezel/goal/issues/7) | 可开工 | 依赖 #2 节点命名；可引用 `pipeline-timing` + UVO steps |

## 建议合并顺序（写优化规格前）

1. 以 **#3 RCA** + **#2 节点表** 定「改哪里、裁不裁」。
2. **#4/#5** 已拍板 → 写入规格硬约束（`optimization-spec-outline-v0.md` 升格）。
3. **#6** 与 review 规格章节合并；**#7** 做效率面验收原型。

**合并稿入口：** [optimization-spec-outline-v0.md](research/optimization-spec-outline-v0.md)（P0/P1 来自 #2/#3/#6；#4/#5 ratified 待回写）

### Research 交叉结论（简）

| 主题 | #3 RCA | #2 catalog | #6 review |
| --- | --- | --- | --- |
| 阻断 implement | IQ-10 未读 Tier-R handoff | timing 仅 gate 边界 | — |
| 漏出/质量 | UVO pass 但 IQ fail | smoke vs quality 双轨 | preflight 必留；dual Agent 耗时 |
| 效率 | noop_fix 掩盖 IQ-10 | 子步骤 timing 未接线 | single track + detect cache |
| UX (#5) | manifest L10 + ux-scan | implement post warn | review-first strict；D2/D5 auto-fix |
