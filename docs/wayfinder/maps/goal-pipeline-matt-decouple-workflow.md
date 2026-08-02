# Wayfinder 本地镜像：goal-pipeline 与 guazi 解耦 + Matt 简体工程化工作流

**Status:** **closed** — 规划轨完成（2026-08-02）；实现另开图（见 [#53 comment](https://github.com/sophiezel/goal/issues/53)）  
**GitHub 主副本（地图）：** [Wayfinder: goal-pipeline 与 guazi 解耦 + Matt 简体工程化工作流（高保真/效率导向）](https://github.com/sophiezel/goal/issues/53)  
**Spec SSOT:** [optimization-spec-outline-v1.3.md](../research/optimization-spec-outline-v1.3.md)

**前置：** [PHASE-5-V12-IMPL-CLOSURE.md](../PHASE-5-V12-IMPL-CLOSURE.md)（#44 已关）· [optimization-spec-outline-v1.2.md](../research/optimization-spec-outline-v1.2.md)

**输入参考（微信，#54 已消化）：**

- https://mp.weixin.qq.com/s/eEZhAnoI7PMDQ899VuD_rw
- https://mp.weixin.qq.com/s/9iOh0gG0Vp_gXip3FP6Xwg
- https://mp.weixin.qq.com/s/jB8dr7QLBo5O4fAoOU_5Ew
- https://mp.weixin.qq.com/s/DZM2-wG_p17kcnehD9dfww

## Destination（摘要）

goal-pipeline **完全与 guazi-flow-* 解耦**；仓内 **简体中文 Matt 工程化 Skill Pack**（蒸馏/fork）支撑 **高保真 + 效率** 交付；**不** 以硬性阶段锁死为首要目标。成功 = **spec v1.3 决策包** + 解耦边界 + Skill Pack 挂载规则；**已达成**（规划轨）。

## 子票

| 标题 | 类型 | URL | 状态 |
| --- | --- | --- | --- |
| Research: 微信四篇 Matt 工程化文章 + 公开 skill 清单消化 | research | https://github.com/sophiezel/goal/issues/54 | **closed** → [matt-engineering-skill-canon-phase6.md](../research/matt-engineering-skill-canon-phase6.md) |
| Grilling: goal-pipeline 解耦原则与「软性 workflow」裁决 | grilling | https://github.com/sophiezel/goal/issues/55 | **closed** → [goal-pipeline-decouple-matt-ratification.md](../research/goal-pipeline-decouple-matt-ratification.md) |
| Research: goal-pipeline 与 guazi-flow-* 耦合面审计（post-v1.2） | research | https://github.com/sophiezel/goal/issues/56 | **closed** → [goal-pipeline-guazi-decouple-inventory.md](../research/goal-pipeline-guazi-decouple-inventory.md) |
| Prototype: goal-engineering v2 Skill Pack 目录与挂载草案 | prototype | https://github.com/sophiezel/goal/issues/57 | **closed** → [goal-engineering-pack-v2-prototype.md](../research/goal-engineering-pack-v2-prototype.md) |
| Research: optimization-spec v1.3 大纲（解耦 + Matt workflow） | research | https://github.com/sophiezel/goal/issues/58 | **closed** → [optimization-spec-outline-v1.3.md](../research/optimization-spec-outline-v1.3.md) |

## Decisions so far（本地镜像）

- [Research: optimization-spec v1.3 大纲](https://github.com/sophiezel/goal/issues/58) — Part O–Q：解耦边界、workflow_profile、迁移与 Impl-1..9 指针 → [v1.3](../research/optimization-spec-outline-v1.3.md)
- [Prototype: goal-engineering v2 Skill Pack 草案](https://github.com/sophiezel/goal/issues/57) — 目录树 + profile 示例 + XS 高保真路径 → [prototype](../research/goal-engineering-pack-v2-prototype.md)
- [Research: guazi 耦合面审计](https://github.com/sophiezel/goal/issues/56) — 28 项剥离 / 18 adapter / 14 文档；9 张实现票 → [inventory](../research/goal-pipeline-guazi-decouple-inventory.md)
- [Grilling: 解耦 + 软性 workflow](https://github.com/sophiezel/goal/issues/55) — C1 全采纳四轴 → [ratification](../research/goal-pipeline-decouple-matt-ratification.md)
- [Research: Matt 清单消化](https://github.com/sophiezel/goal/issues/54) — 四篇微信 + engineering 全表 → [canon](../research/matt-engineering-skill-canon-phase6.md)

## Not yet specified（Fog）

_(empty — 规划轨 Destination 已满足；实现细节见 v1.3 Part Q 与新实现地图)_

## Out of scope

- guazi-flow-goal 编排重写
- 业务仓功能交付
- 本图内 bulk 实现（gate 重命名、stage 去 Fork、pack 实装）→ **新实现地图**

## 建议下一图（未创建）

**标题：** Wayfinder: goal-pipeline v1.3 解耦实现（gate / stage / pack / 夹具）

**草案子票：** Impl-1 Gate 重命名 · Impl-2 Driver/advance · Impl-3 Stage 去 Fork · Impl-7 profile v1.3 · Impl-8 夹具拆分
