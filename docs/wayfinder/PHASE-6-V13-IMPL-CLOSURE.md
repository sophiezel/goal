# Phase-6 goal-pipeline v1.3 解耦实现收口

**Map:** [Wayfinder #59 — goal-pipeline v1.3 解耦实现](https://github.com/sophiezel/goal/issues/59)  
**Spec SSOT:** [optimization-spec-outline-v1.3.md](research/optimization-spec-outline-v1.3.md)  
**Branch:** `feat/goal-pipeline-v1.3-decouple-impl`  
**Baseline:** 规划轨 [#53](https://github.com/sophiezel/goal/issues/53) closed @ `0cc7593`

## 子票闭合

| 票 | 摘要 | 关键产物 |
|----|------|----------|
| [#60](https://github.com/sophiezel/goal/issues/60) | gate 重命名 | `gate-goal-stage.sh` SSOT；`gate-guazi-flow-stage.sh` compat wrapper |
| [#61](https://github.com/sophiezel/goal/issues/61) | driver / advance | 默认 `goal-*` skill + `--mode goal` |
| [#62](https://github.com/sophiezel/goal/issues/62) | stage 去 Fork | `stages/goal-*/SKILL.md` 本仓 SSOT |
| [#63](https://github.com/sophiezel/goal/issues/63) | 根 SKILL + refs | `SKILL.md` goal-first；plan-before-code / handoff-path |
| [#64](https://github.com/sophiezel/goal/issues/64) | goal_lite + task docs | `docs/goal`；grill；`plan_profile: goal_lite` |
| [#65](https://github.com/sophiezel/goal/issues/65) | schema 重命名 | `references/goal-artifact-schema/` + fallback |
| [#66](https://github.com/sophiezel/goal/issues/66) | profile v2 | `workflow_profile.py`；pack prototype/handoff/tdd stubs |
| [#67](https://github.com/sophiezel/goal/issues/67) | 夹具拆分 | `fixtures/goal-gate/` + `guazi-adapter-gate/` |
| [#68](https://github.com/sophiezel/goal/issues/68) | 安装/部署 | deploy-skills / sync-install consumer 分轨 |
| [#69](https://github.com/sophiezel/goal/issues/69) | sweep + 收口 | 本文；`run-all-gate-tests.sh` exit 0 |

## 验收

```bash
cd goal-pipeline/scripts/fixtures/goal-gate
GOAL_GATE_COMPAT_WARN=0 bash run-all-gate-tests.sh
# exit 0
```

## 残余 / P2

- `plan.schema.json` 正式 `prototype_assets` bump（v1.3 字段名已 normative，schema 实现轨可跟进）
- 业务仓迁移 playbook（瓜子 adapter 仍 `--mode guazi` / `pipeline_track=compatibility`）
- Review kernel API semver v1 对外 adapter

## 与规划轨关系

- [#53](https://github.com/sophiezel/goal/issues/53) Destination（spec v1.3 + 边界 + 挂载规则）→ **本实现轨落地默认路径解耦**
- guazi-flow-goal **未重写**；adapter 夹具 `guazi-adapter-gate/` 保留
