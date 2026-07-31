# Wayfinder 本地镜像

GitHub 主副本：[Wayfinder: Goal 交付质量与全链路效率优化（guazi-flow-goal 实战复盘）](https://github.com/sophiezel/goal/issues/1)

## Decisions so far（镜像）

- **Phase-1 engineering closure** — [`3ce9e6b`](https://github.com/sophiezel/goal/commit/3ce9e6b) Wayfinder P0/P1 bundle；[`c13431b`](https://github.com/sophiezel/goal/commit/c13431b) UVO `testPathPattern` 提示修复
- **Phase-2 C1 ratified (all axes)** — [phase-2-real-closure-grilling.md](research/phase-2-real-closure-grilling.md) Ratified 节；fe-argus hybrid、strict UX、matrix W2、P1-9 audit、节点 skip 原则
- **Phase-3b C1 ratified (2026-08-01)** — [#13](https://github.com/sophiezel/goal/issues/13) lite skip 冻结表、[#15](https://github.com/sophiezel/goal/issues/15) PQ/IQ 分层、[#16](https://github.com/sophiezel/goal/issues/16) AM waive/W2、[#20](https://github.com/sophiezel/goal/issues/20) W1 vs W2 对外、[#12](https://github.com/sophiezel/goal/issues/12) spec v1 文档收口 — [phase-3-hitl-ratified.md](research/phase-3-hitl-ratified.md)；规格 [optimization-spec-outline-v1.md](research/optimization-spec-outline-v1.md)
- **漏出计数 W1 + W2** — [#4](https://github.com/sophiezel/goal/issues/4#issuecomment-5145730400)（**closed**）
- **B3 L10 Argus manifest + L9 escalate-only** — [#4](https://github.com/sophiezel/goal/issues/4#issuecomment-5145856518)
- **UX 双轨发现 + C1 auto-fix / strict / a11y** — [#5](https://github.com/sophiezel/goal/issues/5)（**closed**；见 issue CONFIRM 评论）
- **Split handoff SSOT (#14)** — `handoff_path_resolver.py` + [handoff-path-resolution.md](../../goal-pipeline/references/handoff-path-resolution.md)；IQ-10 首验 `d9bf079` — [run log](research/iq10-handoff-fix-run-log.md)
- **Four-planes handoff tier (#17)** — `649abae`；[four-planes-handoff-tier.md](research/four-planes-handoff-tier.md) + `test-four-planes-handoff-tier.sh`
- **Pipeline timing HTML v1 (#9)** — `ee1ef04`；`pipeline_timing_report_core.py` + [pipeline-timing-report-input.md](../../goal-pipeline/references/pipeline-timing-report-input.md)
- **UX auto-fix audit (#11)** — `be2d7a8`；[ux-auto-fix-c1.md](../../goal-pipeline/references/ux-auto-fix-c1.md) + implement post fixtures
- **Merge-review CLI parity (#23)** — `fd9fdf9`；`test-kernel-review-cli-parity.sh` + review timing substep on CLI path
- **W2 matrix leakage (#10)** — `af42c42`；unsatisfied vs waived bookkeeping（#16 C1）

| 工单 | 文件 | GitHub |
| --- | --- | --- |
| [#3 CTB-44243 复盘](https://github.com/sophiezel/goal/issues/3) | [ctb-44243-guazi-flow-goal-rca.md](research/ctb-44243-guazi-flow-goal-rca.md) | **closed** — RCA + P0/P1 goal 修复已落地 |
| [#2 节点清单](https://github.com/sophiezel/goal/issues/2) | [pipeline-node-catalog.md](research/pipeline-node-catalog.md) | **closed** — 研究完成；节点裁剪 HITL → [#13](https://github.com/sophiezel/goal/issues/13) |
| [#6 review-chain](https://github.com/sophiezel/goal/issues/6) | [review-chain-bottlenecks.md](research/review-chain-bottlenecks.md) | **closed** — preflight / strict UX / `review_track` on `main` |
| [#7 timing 看板 v0](https://github.com/sophiezel/goal/issues/7) | [pipeline-timing-dashboard-v0.md](research/pipeline-timing-dashboard-v0.md) | **closed** — v0 规格；**HTML v1** → [`render-pipeline-timing-report.py`](../../goal-pipeline/scripts/render-pipeline-timing-report.py) `--format html` ([#9](https://github.com/sophiezel/goal/issues/9)) |
| [#4 0 漏出](https://github.com/sophiezel/goal/issues/4) | [draft-zero-leakage-and-ux-policy.md](research/draft-zero-leakage-and-ux-policy.md) Part A | **closed** — W1+W2、A.8 B3 ratified |
| [#5 UX 边界](https://github.com/sophiezel/goal/issues/5) | 同上 Part B | **closed** — C1 ratified（见 issue CONFIRM） |

## 当前 Frontier — Phase-3 实质闭环

**Phase-2 基线：** C1 ratified + T1–T5 on [`f91181b`](https://github.com/sophiezel/goal/commit/f91181b)。Grilling SSOT：[phase-2-real-closure-grilling.md](research/phase-2-real-closure-grilling.md)。

**Phase-3b HITL（ratified 2026-08-01）：** [#13](https://github.com/sophiezel/goal/issues/13)–[#16](https://github.com/sophiezel/goal/issues/16)、[#20](https://github.com/sophiezel/goal/issues/20)、[#12](https://github.com/sophiezel/goal/issues/12) 全 C1 — [phase-3-hitl-ratified.md](research/phase-3-hitl-ratified.md)。**工程顺序：** #14 → #17 → #23。

### Phase-3 / Phase-3b 工单（全表）

| # | 标题 | URL |
| --- | --- | --- |
| 8 | Phase-3: fe-argus skill orchestration at plan post | https://github.com/sophiezel/goal/issues/8 |
| 9 | Phase-3: #7 timing dashboard HTML v1 | https://github.com/sophiezel/goal/issues/9 |
| 10 | Phase-3: W2 L9 matrix satisfaction automation | https://github.com/sophiezel/goal/issues/10 |
| 11 | Phase-3: guazi-flow-implement D2/D5 auto-fix + audit contract | https://github.com/sophiezel/goal/issues/11 |
| 12 | Phase-3: optimization-spec v1 formal | https://github.com/sophiezel/goal/issues/12 | **doc closure 2026-08-01** → [v1 outline](research/optimization-spec-outline-v1.md) |
| 13 | Phase-3b: lite profile 节点 skip 冻结表 HITL | https://github.com/sophiezel/goal/issues/13 | **C1 ratified 2026-08-01** |
| 14 | Phase-3: split handoff SSOT（AM / UX / 全平面） | https://github.com/sophiezel/goal/issues/14 |
| 15 | Phase-3b: PQ / IQ 重复校验分层 HITL | https://github.com/sophiezel/goal/issues/15 | **C1 ratified 2026-08-01** |
| 16 | Phase-3b: AM waive + separation W2 漏出口径 HITL | https://github.com/sophiezel/goal/issues/16 | **C1 ratified 2026-08-01** |
| 17 | Phase-3: four_planes_doctor handoff tier 回归门禁 | https://github.com/sophiezel/goal/issues/17 |
| 18 | Phase-3: guazi-flow-postmerge 与 complete 平面衔接 | https://github.com/sophiezel/goal/issues/18 |
| 19 | Phase-3: goal-quality e2e profile 与 tier 对齐 | https://github.com/sophiezel/goal/issues/19 |
| 20 | Phase-3b: Part A.1 北星对外措辞（W1 vs W2） | https://github.com/sophiezel/goal/issues/20 | **C1 ratified 2026-08-01** |
| 21 | ~~optimization-spec v0.2 → v1 升格~~ | closed duplicate of #12 |
| 22 | Phase-3: CTB-44243 平面归因附录（#3 回写） | https://github.com/sophiezel/goal/issues/22 |
| 23 | Phase-3: review kernel CLI merge-review 持续 parity | https://github.com/sophiezel/goal/issues/23 |

| 阶段 | 状态 | 备注 |
| --- | --- | --- |
| **Phase-1** | **工程收口** | #2–#7 closed；P0/P1 在 `main` |
| **Phase-2** | **C1 + T1–T5 landed** | `f91181b` |
| **Phase-3** | **能力/规格真闭环** | 上表；父地图 [#1](https://github.com/sophiezel/goal/issues/1) |

**合并稿入口：** [optimization-spec-outline-v1.md](research/optimization-spec-outline-v1.md)（v1 决策收口，2026-08-01）；历史 [optimization-spec-outline-v0.md](research/optimization-spec-outline-v0.md)（v0.2 实现勾选）

### Research 交叉结论（简）

| 主题 | #3 RCA | #2 catalog | #6 review |
| --- | --- | --- | --- |
| 阻断 implement | IQ-10 未读 Tier-R handoff → **已修**；全平面 SSOT → [#14](https://github.com/sophiezel/goal/issues/14) | timing 仅 gate 边界 | merge-review parity → [#23](https://github.com/sophiezel/goal/issues/23) |
| 漏出/质量 | 平面归因附录 → [#22](https://github.com/sophiezel/goal/issues/22) | smoke vs quality 双轨 | preflight 必留；dual Agent 耗时 |
| 效率 | noop_fix 掩盖 IQ-10 → **已修** | 子步骤 timing → [#9](https://github.com/sophiezel/goal/issues/9) | single track + detect cache（P2） |
| UX (#5) | manifest L10 + ux-scan | implement post warn + **ux-autofix audit** | review-first strict；D2/D5 **#11** ✅ |
