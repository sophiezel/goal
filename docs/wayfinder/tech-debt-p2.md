# Wayfinder P2 / 待优化跟踪

**上下文:** [PHASE-3-CLOSURE.md](PHASE-3-CLOSURE.md) — Phase-3 工程轨已收口；下列为 **不阻塞** 父地图 #1 关闭的增量项。

| 项 | 说明 | 来源 |
|----|------|------|
| PQ/IQ `dedupe_key` in gates | v1 Part D / #15 C1 已 ratified；`plan-quality-gate.py` / `implement-qc-gate.py` 显式字段 + fixture 对齐 | [optimization-spec-outline-v1.md](research/optimization-spec-outline-v1.md) §Part D |
| lite profile JSON | lite 档位与节点 skip 冻结表已 C1；profile 产物 JSON 与 doctor 展示一致性可再抛光 | #13、[pipeline-node-catalog.md](research/pipeline-node-catalog.md) |
| fe-argus Agent 质量 | hybrid 规则 + plan post WO 已落地（#8）；**Agent 侧** fe-argus 深度扫描与 eval 门禁为 recommend | [argus-v2-hybrid.md](../../docs/goal-pipeline/argus-v2-hybrid.md)、`f7b6ae4` optional 依赖 |
| jian-h5 E2E pipeline smoke | goal-quality e2e **profile/tier** 已在 goal 仓 SSOT（#19）；业务仓 **Playwright/device** 管线冒烟与 goal 闸门联动待单独 effort | [goal-quality-e2e-profile.md](../../goal-pipeline/references/goal-quality-e2e-profile.md) |
| review P2 效率 | single track 默认、adaptive depth、detect cache、kernel CLI 少分叉 — 见 review-chain §P2 | [review-chain-bottlenecks.md](research/review-chain-bottlenecks.md) §7–8 |
| git history #14 双提交 | `041b63b` 与 `df887b4` 同为 split handoff SSOT；**cosmetic** 重复，无功能分叉 | PHASE-3 工程笔记 |

*更新约定：实现 PR 可在对应条目下追加 commit 指针；跨仓项在业务仓 guazi-flow `tech-debt-tracker.md` 镜像链接即可。*
