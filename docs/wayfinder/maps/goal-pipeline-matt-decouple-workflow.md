# Wayfinder 本地镜像：goal-pipeline 与 guazi 解耦 + Matt 简体工程化工作流

**Status:** **open** — 规划轨（plan-first）  
**GitHub 主副本（地图）：** [Wayfinder: goal-pipeline 与 guazi 解耦 + Matt 简体工程化工作流（高保真/效率导向）](https://github.com/sophiezel/goal/issues/53)  
**Frontier（首波）：** [#54](https://github.com/sophiezel/goal/issues/54)、[#55](https://github.com/sophiezel/goal/issues/55)、[#56](https://github.com/sophiezel/goal/issues/56)

**前置：** [PHASE-5-V12-IMPL-CLOSURE.md](../PHASE-5-V12-IMPL-CLOSURE.md)（#44 已关）· [optimization-spec-outline-v1.2.md](../research/optimization-spec-outline-v1.2.md) · [goal-pipeline-external-patterns-gap-phase5.md](../research/goal-pipeline-external-patterns-gap-phase5.md)

**输入参考（微信，待 #54 消化）：**

- https://mp.weixin.qq.com/s/eEZhAnoI7PMDQ899VuD_rw
- https://mp.weixin.qq.com/s/9iOh0gG0Vp_gXip3FP6Xwg
- https://mp.weixin.qq.com/s/jB8dr7QLBo5O4fAoOU_5Ew
- https://mp.weixin.qq.com/s/DZM2-wG_p17kcnehD9dfww

## Destination（摘要）

goal-pipeline **完全与 guazi-flow-* 解耦**；仓内 **简体中文 Matt 工程化 Skill Pack**（蒸馏/fork）支撑 **高保真 + 效率** 交付；**不** 以硬性阶段锁死为首要目标。成功 = **spec v1.3 决策包** + 解耦边界 + Skill Pack 挂载规则；实现另开图。

## 子票

| 标题 | 类型 | URL | Frontier |
| --- | --- | --- | --- |
| Research: 微信四篇 Matt 工程化文章 + 公开 skill 清单消化 | research | https://github.com/sophiezel/goal/issues/54 | **open** |
| Grilling: goal-pipeline 解耦原则与「软性 workflow」裁决 | grilling | https://github.com/sophiezel/goal/issues/55 | **open** |
| Research: goal-pipeline 与 guazi-flow-* 耦合面审计（post-v1.2） | research | https://github.com/sophiezel/goal/issues/56 | **open** |
| Prototype: goal-engineering v2 Skill Pack 目录与挂载草案 | prototype | https://github.com/sophiezel/goal/issues/57 | blocked by **#54、#55** |
| Research: optimization-spec v1.3 大纲（解耦 + Matt workflow） | research | https://github.com/sophiezel/goal/issues/58 | blocked by **#55、#56、#57** |

## 并发与串行

| 票 | 可与谁并行 | 必须等待 |
| --- | --- | --- |
| [#54](https://github.com/sophiezel/goal/issues/54) Matt 清单消化 | #55、#56 | — |
| [#55](https://github.com/sophiezel/goal/issues/55) 解耦 + 软性 workflow grilling | #54、#56 | — |
| [#56](https://github.com/sophiezel/goal/issues/56) 耦合面审计 | #54、#55 | — |
| [#57](https://github.com/sophiezel/goal/issues/57) Skill Pack 原型 | — | **#54、#55** |
| [#58](https://github.com/sophiezel/goal/issues/58) spec v1.3 大纲 | — | **#55、#56、#57** |

**建议认领顺序：** 并行 **#54 / #55 / #56** → **#57** → **#58** →（新实现地图，本图外）

## Decisions so far（本地镜像）

_(empty — chart session)_

## Not yet specified（Fog）

- 实现地图拆分（gate 重命名、stage skill 去 Fork、夹具、迁移 guazi 业务仓 adapter）
- workflow_profile 与 stage_graph / engineering_pack 正交关系
- 微信文章若无法 HITL 粘贴时的降级来源（公开 Matt repo / 已有 Cursor skills）

## Out of scope

- guazi-flow-goal 编排重写
- 业务仓功能交付
- 本图 chart 会话 bulk 实现
