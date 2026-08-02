# Wayfinder 本地镜像：goal-pipeline v1.3 解耦实现

**Status:** **closed** — 2026-08-02（#60–#69）  
**GitHub 主副本（地图）：** [Wayfinder: goal-pipeline v1.3 解耦实现（gate / stage / pack / 夹具）](https://github.com/sophiezel/goal/issues/59)  
**收口:** [PHASE-6-V13-IMPL-CLOSURE.md](../PHASE-6-V13-IMPL-CLOSURE.md)  
**分支:** `feat/goal-pipeline-v1.3-decouple-impl`

**前置:** [#53 规划轨](https://github.com/sophiezel/goal/issues/53) · [optimization-spec-outline-v1.3.md](../research/optimization-spec-outline-v1.3.md)

## Destination（摘要）

落地 v1.3：**默认路径零 guazi 隐式依赖**；`gate-goal-stage`；stage SSOT 本仓；`workflow_profile` + pack v2 stubs；夹具 `goal-gate` 主套件。**已达成。**

## 子票

| 标题 | URL | 状态 |
| --- | --- | --- |
| Task: gate 重命名与兼容窗 | https://github.com/sophiezel/goal/issues/60 | **closed** |
| Task: driver / advance 默认 goal 叙事 | https://github.com/sophiezel/goal/issues/61 | **closed** |
| Task: stage SKILL 去 Fork | https://github.com/sophiezel/goal/issues/62 | **closed** |
| Task: 根 SKILL + references | https://github.com/sophiezel/goal/issues/63 | **closed** |
| Task: 任务目录 + goal_lite | https://github.com/sophiezel/goal/issues/64 | **closed** |
| Task: artifact schema 重命名 | https://github.com/sophiezel/goal/issues/65 | **closed** |
| Task: profile workflow_profile + pack v2 | https://github.com/sophiezel/goal/issues/66 | **closed** |
| Task: 夹具拆分 goal-gate / guazi-adapter | https://github.com/sophiezel/goal/issues/67 | **closed** |
| Task: 安装/部署分 consumer | https://github.com/sophiezel/goal/issues/68 | **closed** |
| Task: v1.3 gate sweep + 收口 | https://github.com/sophiezel/goal/issues/69 | **closed** |

## Decisions so far

- [gate 重命名](https://github.com/sophiezel/goal/issues/60) — `gate-goal-stage.sh` SSOT；compat wrapper 保留 `--mode guazi`
- [driver / advance](https://github.com/sophiezel/goal/issues/61) — 默认 `goal-*` + `--mode goal`；`pipeline_track=compatibility|guazi` 走 adapter
- [stage 去 Fork](https://github.com/sophiezel/goal/issues/62) — 五 stage SKILL 本仓 SSOT
- [profile v2](https://github.com/sophiezel/goal/issues/66) — `workflow_profile.py`；pack stubs prototype/handoff/tdd
- [夹具拆分](https://github.com/sophiezel/goal/issues/67) — `fixtures/goal-gate/` 默认 CI；`guazi-adapter-gate/` opt-in
- [gate sweep](https://github.com/sophiezel/goal/issues/69) — `run-all-gate-tests.sh` exit 0 → [PHASE-6-V13-IMPL-CLOSURE.md](../PHASE-6-V13-IMPL-CLOSURE.md)

## Out of scope

- guazi-flow-goal 编排重写
- 业务仓功能交付
