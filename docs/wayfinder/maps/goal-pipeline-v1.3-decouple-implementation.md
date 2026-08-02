# Wayfinder 本地镜像：goal-pipeline v1.3 解耦实现

**Status:** **open** — 实现轨  
**GitHub 主副本（地图）：** [Wayfinder: goal-pipeline v1.3 解耦实现（gate / stage / pack / 夹具）](https://github.com/sophiezel/goal/issues/59)  
**Frontier（首波）：** [#60](https://github.com/sophiezel/goal/issues/60)

**前置（已关闭）：** [Wayfinder #53 — Matt 解耦规划轨](https://github.com/sophiezel/goal/issues/53) · [optimization-spec-outline-v1.3.md](../research/optimization-spec-outline-v1.3.md) · [goal-pipeline-guazi-decouple-inventory.md](../research/goal-pipeline-guazi-decouple-inventory.md)

**建议分支：** `feat/goal-pipeline-v1.3-decouple-impl`

## Destination（摘要）

落地 **v1.3 Part O–Q**：goal-pipeline **默认路径零 guazi 隐式依赖**；`gate-goal-stage` + 兼容窗；stage 去 Fork；`workflow_profile` + engineering_pack v2；夹具拆分 goal / guazi-adapter。

**成功标准：** `run-all-gate-tests.sh`（goal 默认套件）exit 0；guazi-adapter 套件 exit 0。

## 子票

| 标题 | Impl | URL | Frontier |
| --- | --- | --- | --- |
| Task: gate 重命名与兼容窗（gate-goal-stage） | Impl-1 | https://github.com/sophiezel/goal/issues/60 | **open** |
| Task: driver / advance 默认 goal 叙事 | Impl-2 | https://github.com/sophiezel/goal/issues/61 | blocked by **#60** |
| Task: stage SKILL 去 Fork（5 stages） | Impl-3 | https://github.com/sophiezel/goal/issues/62 | blocked by **#60** |
| Task: 根 SKILL + references 默认叙事 | Impl-4 | https://github.com/sophiezel/goal/issues/63 | blocked by **#62** |
| Task: 任务目录 + goal_lite plan 路径 | Impl-5 | https://github.com/sophiezel/goal/issues/64 | blocked by **#62** |
| Task: artifact schema 目录重命名 | Impl-6 | https://github.com/sophiezel/goal/issues/65 | blocked by **#60** |
| Task: profile workflow_profile + engineering_pack v2 | Impl-7 | https://github.com/sophiezel/goal/issues/66 | blocked by **#62** |
| Task: 夹具拆分 goal-gate / guazi-adapter | Impl-8 | https://github.com/sophiezel/goal/issues/67 | blocked by **#60** |
| Task: 安装/部署脚本分 consumer | Impl-9 | https://github.com/sophiezel/goal/issues/68 | blocked by **#60、#67** |
| Task: v1.3 gate sweep + 实现收口文档 | sweep | https://github.com/sophiezel/goal/issues/69 | blocked by **#61–#68** |

## 并发与串行

| 票 | 可与谁并行 | 必须等待 |
| --- | --- | --- |
| [#60](https://github.com/sophiezel/goal/issues/60) gate 重命名 | — | — |
| [#61](https://github.com/sophiezel/goal/issues/61) driver/advance | #65、#67 | **#60** |
| [#62](https://github.com/sophiezel/goal/issues/62) stage 去 Fork | #65、#67 | **#60** |
| [#63](https://github.com/sophiezel/goal/issues/63) 根 SKILL | #64、#66 | **#62** |
| [#64](https://github.com/sophiezel/goal/issues/64) goal_lite | #63、#66 | **#62** |
| [#65](https://github.com/sophiezel/goal/issues/65) schema 重命名 | #61、#62、#67 | **#60** |
| [#66](https://github.com/sophiezel/goal/issues/66) profile v2 | #63、#64 | **#62** |
| [#67](https://github.com/sophiezel/goal/issues/67) 夹具拆分 | #61、#65 | **#60** |
| [#68](https://github.com/sophiezel/goal/issues/68) 安装/部署 | — | **#60、#67** |
| [#69](https://github.com/sophiezel/goal/issues/69) sweep | — | **#61–#68** |

**建议认领顺序：** **#60** → (#61 ∥ #62 ∥ #65 ∥ #67) → (#63 ∥ #64 ∥ #66) → **#68** → **#69**

## Decisions so far（本地镜像）

_(empty — chart session)_

## Not yet specified（Fog）

- Review kernel API semver v1 对外 adapter
- `plan.schema.json` prototype_assets 正式 bump 时机
- 业务仓（瓜子）迁移 playbook

## Out of scope

- guazi-flow-goal 编排重写
- 业务仓功能交付
- loop-me fork

## 规格交叉引用

- [optimization-spec-outline-v1.3.md](../research/optimization-spec-outline-v1.3.md)
- [goal-engineering-pack-v2-prototype.md](../research/goal-engineering-pack-v2-prototype.md)
- [goal-pipeline-decouple-matt-ratification.md](../research/goal-pipeline-decouple-matt-ratification.md)
