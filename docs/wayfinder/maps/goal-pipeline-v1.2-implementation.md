# Wayfinder 本地镜像：goal-pipeline v1.2 破坏性实现（Phase-5 落地）

**Status:** **open** — 实现轨  
**GitHub 主副本（地图）：** [Wayfinder: goal-pipeline v1.2 破坏性实现（Phase-5 落地）](https://github.com/sophiezel/goal/issues/44)  
**Frontier（首波）：** [#51](https://github.com/sophiezel/goal/issues/51)（#45–#50 已闭合）

**前置地图（已关闭）：** [Wayfinder #36 — Phase-5 系统分析与优化规格](https://github.com/sophiezel/goal/issues/36) — [PHASE-5-CLOSURE.md](../PHASE-5-CLOSURE.md) · 规格 SSOT [optimization-spec-outline-v1.2.md](../research/optimization-spec-outline-v1.2.md)

**实现分支：** `feat/goal-pipeline-v1.2-breaking-impl`

**索引：** [goal-delivery-quality-optimization.md](../goal-delivery-quality-optimization.md) · P2 [tech-debt-p2.md](../tech-debt-p2.md)

## Destination（摘要）

落地 **optimization-spec v1.2** 的 goal-pipeline **breaking-first** 实现：Part J `stage_graph`/profile、Part K `engineering_pack`、Part L review kernel B schema + single-track 默认、Part M generic services 接线、Part N + 附录 **B1–B9** normative 行为。**不** 改造 guazi-flow-goal 编排；**不** 以 guazi 历史双轨为 goal-pipeline 默认兼容层。

**成功标准：** `goal-pipeline/scripts/fixtures/guazi-flow-gate/run-all-gate-tests.sh` 在 default profile 反映 v1.2 语义。

## 子票

| 标题 | 类型 | URL | Frontier |
| --- | --- | --- | --- |
| Task: profile stage_graph + handoff WO 字段（Part J / R1–R4 映射） | task | https://github.com/sophiezel/goal/issues/45 | **closed**（`58de85e`） |
| Task: review kernel B JSON schemas + 夹具校验（Part L） | task | https://github.com/sophiezel/goal/issues/46 | **closed**（`1886b23`） |
| Task: B1 — deprecate smoke advance；quality-only 主轨 | task | https://github.com/sophiezel/goal/issues/47 | **closed**（`1390b13`） |
| Task: B8 single-track 默认 + review gate/handoff（Part L） | task | https://github.com/sophiezel/goal/issues/48 | **closed**（`c4406e6`） |
| Task: engineering_pack 目录桩 + Phase 1 skill_to_load（Part K） | task | https://github.com/sophiezel/goal/issues/49 | **closed**（`1390b13`） |
| Task: B2 + B3 — 全 stage timing 与契约融入 WARN→BLOCK | task | https://github.com/sophiezel/goal/issues/50 | **closed** |
| Task: v1.2 gate fixture sweep（run-all-gate-tests 对齐） | task | https://github.com/sophiezel/goal/issues/51 | **open** |

## 并发与串行（路由）

| 票 | 可与谁并行 | 必须等待 |
| --- | --- | --- |
| [#45](https://github.com/sophiezel/goal/issues/45) stage_graph（Part J） | — | **closed** |
| [#46](https://github.com/sophiezel/goal/issues/46) B schemas（Part L） | #47、#49 | **closed** |
| [#47](https://github.com/sophiezel/goal/issues/47) B1 smoke 轨 | #49 | **closed** |
| [#49](https://github.com/sophiezel/goal/issues/49) engineering_pack（Part K） | #47 | **closed** |
| [#48](https://github.com/sophiezel/goal/issues/48) B8 single-track | #47、#49 | **closed** |
| [#50](https://github.com/sophiezel/goal/issues/50) B2 + B3 | #48（部分） | **closed** |
| [#51](https://github.com/sophiezel/goal/issues/51) gate sweep | #50（建议） | **open** |

**Frontier：** [#51](https://github.com/sophiezel/goal/issues/51)（#50 闭合后）

## Decisions so far（本地镜像）

- [Task: profile stage_graph + handoff WO 字段（Part J / R1–R4 映射）](https://github.com/sophiezel/goal/issues/45) — `references/profiles/default/pipeline.profile.json` + `kernel.profile.stage_graph`；`plan.json` 可覆盖拓扑；`goal-stage-driver` work_order 含 `pipeline_profile` / `stage_graph_ids` / `stage_meta`；gate post 用 `next_stage_id` 替代硬编码五段表；夹具 `test-stage-graph-profile-default.sh` 证明 default ≡ F.2（`58de85e`）。
- [Task: review kernel B JSON schemas + 夹具校验（Part L）](https://github.com/sophiezel/goal/issues/46) — `schemas/review-{run,unified,fix-input}.schema.json` 升为 draft-07；`kernel/review/b_schema.py` + `test-review-kernel-b-schemas.sh`（11 件夹具）；`gate-lib/review.sh` 复用 `b_schema_cli validate-fix-input`。
- [Task: B8 single-track 默认 + review gate/handoff（Part L）](https://github.com/sophiezel/goal/issues/48) — `review_track.py` 默认 `single` + `wrapper_profile_for_track`；plan post / `run-independent-review` / `gate-lib/review.sh` handoff 写入 `review_track` + `wrapper_profile`（`goal-review`）；single 轨拒绝 `gf_skill_attested`；dual 显式 `GOAL_REVIEW_TRACK=dual`；夹具 `test-review-track.sh`、`test-review-handoff-b8.sh`（`c4406e6`）。
- [Task: engineering_pack 目录桩 + Phase 1 skill_to_load（Part K）](https://github.com/sophiezel/goal/issues/49) — `goal-pipeline/skills/goal-engineering/*` stub；`engineering_pack` profile 键 + `goal-stage-driver` plan WO 软加载；`test-engineering-pack-phase1.sh`（`1390b13`）。
- [Task: B1 — deprecate smoke advance；quality-only 主轨](https://github.com/sophiezel/goal/issues/47) — default `--stage smoke` blocked；`GOAL_ALLOW_LEGACY_SMOKE_STAGE=1`；chain/stage-port/consistency 仅认 `quality.json`；`test-b1-smoke-quality-only-advance.sh`；`run-all-gate-tests.sh` exit 0（`1390b13`）。
- [Task: B2 + B3 — 全 stage timing 与契约融入 WARN→BLOCK](https://github.com/sophiezel/goal/issues/50) — gate pre/post `record-pipeline-timing`（phase substep；`smoke`→`quality`）；`guazi_flow_contract_enrich.py` plan post BLOCK + implement pre guard；default profile `contract_enrich.policy=block`；`test-b2-b3-timing-contract.sh` + kernel unit tests；`run-all-gate-tests.sh` exit 0。

## Not yet specified（Fog）

- SLO 数值校准、`sla_breach` failure_code 默认接线（Part N §N.2 脚注）
- Review kernel API semver v1 对外 adapter
- B4/B6/B7 专票拆分（首波后按 frontier 增补）
- B9 bridge-contract doc-only（P2）
- guazi-flow-goal wrapper 迁移（默认 out of scope）

## Out of scope

- guazi-flow-goal 编排 / dual-review **改造**
- 业务仓功能交付、Wayfinder 硬 gate stage
- 本图 chart 会话 bulk 实现（仅 issues + docs + 分支）

## 规格交叉引用

- [optimization-spec-outline-v1.2.md](../research/optimization-spec-outline-v1.2.md)（SSOT）
- [PHASE-5-CLOSURE.md](../PHASE-5-CLOSURE.md) · [goal-full-chain-phase5-analysis.md](goal-full-chain-phase5-analysis.md)（已关闭 Phase-5 分析图）
- [goal-pipeline/SKILL.md](../../../goal-pipeline/SKILL.md)
