# Wayfinder 本地镜像：guazi-flow-goal 全链路硬化（Phase-4）

**Status:** **closed（2026-08-01）** — 夹具 [#30](https://github.com/sophiezel/goal/issues/30) PASS；地图 [#24](https://github.com/sophiezel/goal/issues/24) 已关  
**GitHub 主副本（地图）：** [Wayfinder: guazi-flow-goal 全链路硬化（Phase-4，profile 无关）](https://github.com/sophiezel/goal/issues/24)  
**前置地图（已关闭）：** [Wayfinder: Goal 交付质量与全链路效率优化](https://github.com/sophiezel/goal/issues/1) · [PHASE-3-CLOSURE](../PHASE-3-CLOSURE.md)  
**相关 RCA：** [Research: jian-h5 CTB-44243 运行复盘](https://github.com/sophiezel/goal/issues/3)（`2026-07-31-*` / IQ-10）

## HITL 裁决（2026-08-01）

**系统级根因优先：** 首目标为 **profile/项目无关** 的 Phase-4 通用硬化（分层需求、门禁、UVO/handoff/IQ 政策、量化 SLO），落地于 **goal-pipeline / guazi-flow-goal**，而非业务仓点对点补丁。

**回归夹具（强制验收）：** CTB-44243 `260728-*` 为 **mandatory regression fixture**；在 goal 侧根因修复落地后，该 run 上 **`gate --post implement` 绿** 是证明通用修复端到端有效的 **acceptance check**——既不是地图完成的唯一定义，也 **不得** 通过修 jian-h5 既有单测、收窄 `testPathPattern`、或仅为单票 skip 门禁等方式「假绿」。

详见 [Grilling #29 HITL](https://github.com/sophiezel/goal/issues/29#issuecomment-5151003002) 与 [口径校正 ratification](https://github.com/sophiezel/goal/issues/29#issuecomment-5151007927)。

## 样本 run 事实（夹具）

| 项 | 值 |
| --- | --- |
| Jira | CTB-44243（产品上下文；**交付在 goal 通用硬化 + 夹具验收**） |
| 任务目录 | `jian-h5/docs/guazi-flow/260728-疑似车商车源收车审批` |
| Pipeline state | `~/.goal-pipeline/state/projects/1115ca6039e1/CTB-44243-T1/260728-疑似车商车源收车审批/` |
| Gate | **UVO-01** — `test:related-tests`；`findRelatedTests` 含 `App.tsx`；失败含 `order/newbie` 等与 write_set 弱相关套件 |
| 根因（#25 闭合） | **DEM-08** — `related_union` 合成过宽：hub `App.tsx` + `_test_files_for_write_set` 对 `constants` 整仓基名匹配 |

## 子票

| 标题 | 类型 | URL | Frontier |
| --- | --- | --- | --- |
| Research: UVO-01 — 260728 CTB-44243 implement gate 失败归因 | research | https://github.com/sophiezel/goal/issues/25 | **closed** — [uvo-01-260728-root-cause-and-fix-options.md](../research/uvo-01-260728-root-cause-and-fix-options.md) |
| Task: Phase-4 goal-pipeline UVO related_union 根因实现合入 main | task | https://github.com/sophiezel/goal/issues/32 | **closed** — G1+G2+G5 in `verification_oracle_core.py` |
| Research: Phase-4 分层需求与 pipeline SLO 规格输入 | research | https://github.com/sophiezel/goal/issues/28 | **closed** — [phase-4-layered-demand-and-slo-input.md](../research/phase-4-layered-demand-and-slo-input.md) |
| Task: Phase-4 UVO write_set 闭包收紧（G3+G6，#30 夹具 DEM-08 残留） | task | https://github.com/sophiezel/goal/issues/33 | **closed** — G3+G6 `write_set_closure` 默认 |
| Task: UVO write_set_closure — 纯 DEM-08 不阻断 implement gate | task | https://github.com/sophiezel/goal/issues/34 | **closed** — 判定层：`dem08_implement_warn` + `overall=pass` |
| Task: implement post — AUTOFIX-01 与 write_set/feature diff 对齐（#30 夹具） | task | https://github.com/sophiezel/goal/issues/35 | **closed** — scoped audit + quotepath=false；#30 夹具 implement post exit 0 |
| Task: 260728 夹具 implement gate 复跑（goal 根因修复后验收） | task | https://github.com/sophiezel/goal/issues/30 | **closed** — 正式验收 `gate --post implement` exit 0（2026-08-01；#32–#35 合入后） |
| Task: optimization-spec v1.1 — 合入 Part F–I（分层需求与 Pipeline SLO） | task | https://github.com/sophiezel/goal/issues/31 | **closed** — [optimization-spec-outline-v1.1.md](../research/optimization-spec-outline-v1.1.md) |
| Grilling: Phase-4 硬化范围与 CTB 解阻的优先级 | grilling | https://github.com/sophiezel/goal/issues/29 | **closed** — HITL + 口径校正 |
| Grilling: CTB-44243 UVO 解阻 — 业务仓修测 vs goal-pipeline 政策 | grilling | https://github.com/sophiezel/goal/issues/26 | **closed** — 点对点业务仓路线否决 |
| Task: jian-h5 260728 任务 implement gate 解阻并复跑 | task | https://github.com/sophiezel/goal/issues/27 | **closed** — 原「业务仓解阻」任务；验收改 #30 |

**建议下一认领：** 无开放子票；可关闭 [地图 #24](https://github.com/sophiezel/goal/issues/24)。

## 并发与串行（路由）

GitHub 主副本说明见 [地图 #24 评论「并发与串行（路由图）」](https://github.com/sophiezel/goal/issues/24#issuecomment-5151027574)。

| 票 | 可与谁并行 | 必须等待 |
| --- | --- | --- |
| [Task: Phase-4 goal-pipeline UVO related_union 根因实现合入 main](https://github.com/sophiezel/goal/issues/32) | — | **closed**（[#25](https://github.com/sophiezel/goal/issues/25)） |
| [Task: Phase-4 UVO write_set 闭包收紧（G3+G6）](https://github.com/sophiezel/goal/issues/33) | — | **closed** |
| [Task: UVO write_set_closure — 纯 DEM-08 不阻断 implement gate](https://github.com/sophiezel/goal/issues/34) | — | **closed** |
| [Task: implement post — AUTOFIX-01 与 write_set/feature diff 对齐](https://github.com/sophiezel/goal/issues/35) | — | **closed** |
| [Task: 260728 夹具 implement gate 复跑](https://github.com/sophiezel/goal/issues/30) | — | **closed** — mandatory fixture acceptance |

**Tracker 口径：** 子票 #25–#35、#30 均已 closed；地图 [#24](https://github.com/sophiezel/goal/issues/24) **已关闭**。

## 规格交叉引用

- [optimization-spec-outline-v1.md](../research/optimization-spec-outline-v1.md) · [optimization-spec-outline-v1.1.md](../research/optimization-spec-outline-v1.1.md)（Part F–I）
- [tech-debt-p2.md](../tech-debt-p2.md)
- [phase-4-layered-demand-and-slo-input.md](../research/phase-4-layered-demand-and-slo-input.md)（#28）
- [uvo-01-260728-root-cause-and-fix-options.md](../research/uvo-01-260728-root-cause-and-fix-options.md)（#25）

## Decisions so far（本地镜像）

- [#28](https://github.com/sophiezel/goal/issues/28) — R1–R4 四层需求、失败 taxonomy（含 DEM-08 误拦）、横切面政策默认、SLO v0 表、行业采纳边界 → 研究稿见上链。
- [#32](https://github.com/sophiezel/goal/issues/32) — **G1+G2+G5** 落地：`verification_oracle_core.py` 同目录测试配对、hub 默认不进 `findRelatedTests`、oracle JSON `failing_test_files` / `out_of_write_set_closure` / `verification_scope_overreach` + `verification_scope_overreach` failure_code；fixture `test-verification-oracle.sh`。
- [#33](https://github.com/sophiezel/goal/issues/33) — **G3+G6**：`GOAL_UVO_RELATED_UNION_MODE` 默认 `write_set_closure`（`legacy_wide` opt-in）；`write_set∩changed` 种子 + 测试文件直跑（不进 `findRelatedTests`）；`uvo_hub_expansion`（plan/index/env）；oracle JSON `related_union_mode`；fixture 回归 env.js / App.test.tsx。
- [#34](https://github.com/sophiezel/goal/issues/34) — **判定层（#25/v1.1 边界）：** `write_set_closure` 下纯 DEM-08 → `dem08_implement_warn`、`overall=pass`、test step `dem08_warn`；`verification_scope_overreach` 仍记入 oracle/SLO-Q-01；implement gate 不因闭包外红测 block。
- [#35](https://github.com/sophiezel/goal/issues/35) — **AUTOFIX-01 范围对齐：** `ux-auto-fix-audit.py` 仅审计 narrow D2/D5 autofix（`implement_scope_changed_files`、跳过 `docs/guazi-flow/**`、`core.quotepath=false`）；write_set 内 feature implement 不误拦；`diff_resolver.git_changed_and_untracked`；fixture `test-ux-auto-fix-audit.sh`；jian-h5 260728 `gate --post implement` exit 0。
- [#30](https://github.com/sophiezel/goal/issues/30) — 夹具复跑 **PASS**（2026-08-01 正式验收）：`gate-guazi-flow-stage.sh --stage implement --post` exit `0`（jian-h5 `260728-*`，`GOAL_PIPELINE_REPO` goal 仓）。UVO：`overall=pass`，`related_union_mode=write_set_closure`，`dem08_implement_warn=true`（不阻断）。`ux-autofix.json`：`ok=true`，`violations=[]`。证据：`~/.goal-pipeline/state/projects/1115ca6039e1/CTB-44243-T1/260728-疑似车商车源收车审批/artifacts/evidence/{verification-oracle.json,ux-autofix.json,pipeline-timing.json}`。未改 jian-h5 测试。
- [#31](https://github.com/sophiezel/goal/issues/31) — 研究稿合入 [optimization-spec-outline-v1.1.md](../research/optimization-spec-outline-v1.1.md)（Part F–I + 附录）；Part H `related_union` 已由 #25 ratified（v1.1.1 行）；代码 [#32](https://github.com/sophiezel/goal/issues/32)。
