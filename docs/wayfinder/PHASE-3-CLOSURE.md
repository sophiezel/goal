# Wayfinder Phase-3 工程收口（2026-08-01）

**父地图:** [Wayfinder #1](https://github.com/sophiezel/goal/issues/1)  
**规格 SSOT:** [optimization-spec-outline-v1.md](research/optimization-spec-outline-v1.md)  
**HITL ratification:** [phase-3-hitl-ratified.md](research/phase-3-hitl-ratified.md)  
**镜像导航:** [goal-delivery-quality-optimization.md](goal-delivery-quality-optimization.md)

## 结论

Wayfinder **Phase-3 / Phase-3b** 子工单 **#8–#23**（含 HITL **#12–#16、#20**）已在 `main` 上 **实质闭环**；父 issue **#1** 建议 **关闭**，后续增量工作记入 [tech-debt-p2.md](tech-debt-p2.md)，不再挂在开放父地图下。

## Commit 范围

| 锚点 | SHA | 说明 |
|------|-----|------|
| **起点** | [`4cc8e18`](https://github.com/sophiezel/goal/commit/4cc8e18) | Phase-3 Frontier 工单表扩展 |
| **终点** | [`f7b6ae4`](https://github.com/sophiezel/goal/commit/f7b6ae4) | fe-argus optional 依赖与安装说明 |

区间 `4cc8e18..f7b6ae4` 覆盖 Phase-3b HITL ratification、split handoff SSOT、four-planes tier、timing HTML v1、UX audit、W2 matrix、merge-review CLI parity、postmerge/complete、e2e profile、CTB §8 附录、fe-argus plan post 等落地提交。

## 已关闭子工单（#8–#23）

| # | 标题 | 状态 | 落地指针 |
|---|------|------|----------|
| 8 | fe-argus skill orchestration at plan post | closed | `8b47fd4` — `argus_plan_post_policy.py` |
| 9 | timing dashboard HTML v1 | closed | `ee1ef04` — `render-pipeline-timing-report.py --format html` |
| 10 | W2 L9 matrix satisfaction automation | closed | `af42c42` — `test-w2-matrix-leakage.sh` |
| 11 | implement D2/D5 auto-fix + audit contract | closed | `be2d7a8` — `ux-auto-fix-c1.md` |
| 12 | optimization-spec v1 formal | closed | [optimization-spec-outline-v1.md](research/optimization-spec-outline-v1.md) |
| 13 | lite profile 节点 skip 冻结表 HITL | closed C1 | [phase-3-hitl-ratified.md](research/phase-3-hitl-ratified.md) |
| 14 | split handoff SSOT | closed | `041b63b` / `df887b4` — `handoff_path_resolver.py`（历史双提交，语义等价） |
| 15 | PQ / IQ 重复校验分层 HITL | closed C1 | v1 Part D；gate 显式 `dedupe_key` → P2 |
| 16 | AM waive + separation W2 漏出口径 HITL | closed C1 | #10 + draft Part A |
| 17 | four_planes_doctor handoff tier 门禁 | closed | `649abae` |
| 18 | postmerge 与 complete 平面衔接 | closed | `96318b9` — [postmerge-complete-plane.md](research/postmerge-complete-plane.md) |
| 19 | goal-quality e2e profile × tier | closed | `8073a6c` — `goal_quality_e2e_policy.py` |
| 20 | Part A.1 北星对外措辞 W1 vs W2 | closed C1 | v1 Part A |
| 21 | v0.2 → v1 升格 | closed duplicate | 同 #12 |
| 22 | CTB-44243 平面归因附录 | closed | `a837ba3` — RCA §8 |
| 23 | merge-review kernel CLI parity | closed | `fd9fdf9` — `test-kernel-review-cli-parity.sh` |

Phase-1/2 前置（#2–#7、#3–#6 等）已在更早提交收口；见 [goal-delivery-quality-optimization.md](goal-delivery-quality-optimization.md) Decisions 表。

## 验证

在 goal 仓根目录执行：

```bash
goal-pipeline/scripts/fixtures/guazi-flow-gate/run-all-gate-tests.sh
```

收口会话须 **全绿**（与 `main` 门禁一致）。可选：`fe-argus` / Agent 质量扫描为 **recommend**，非阻塞。

## #1 关闭建议

| 选项 | 建议 |
|------|------|
| **关闭 #1** | **推荐** — 规格 v1、Phase-3 工程轨、HITL C1 均已落盘；父地图完成「产出优化规格 + goal 仓实现轨」的 Destination |
| 保持开放 | 仅当仍有未登记的 Phase-4 史诗；当前 P2 项已迁至 [tech-debt-p2.md](tech-debt-p2.md) |

关闭 #1 时的摘要话术：**Substantive Wayfinder complete**；ongoing P2 → tech-debt tracker；样本验收见 jian-h5 guazi-flow 任务（本地图不直接改业务仓）。

## 后续（P2，非 Phase-3 阻塞）

见 [tech-debt-p2.md](tech-debt-p2.md)。
