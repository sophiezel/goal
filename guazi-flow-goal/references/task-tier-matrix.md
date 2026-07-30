# task_tier 分层矩阵（复杂度 SLO + 并行策略）

Plan 结束后由 `task_tier.py` 写入 `state.json` / `plan.json` 的 `task_tier` + `task_tier_meta`。

**禁止**把 M/L 任务硬卡成 XS「20 分钟」；在对应档位内吃满 CPU / 缓存 / subagent，而不是偷减阶段。

## 矩阵

| Tier | 典型形态 | p50 墙钟 | p90 | 并行策略 | Index-Lite |
|------|----------|----------|-----|----------|-----------|
| XS | 单文件文案/常量 | ≤15m | 25m | 单 agent；不开 subagent | ✅ 推荐 `plan_profile: lite` |
| S | 单页局部交互 + 少量单测 | ≤25m | 40m | 可选 2 subagent（UI∥test） | ✅ 推荐 `plan_profile: lite` |
| M | 新列表 / 多文件跨页 | ≤45m | 70m | 3–4 subagent DAG；路由串行收口 | ❌ 强制 full（plan.json M+ 覆盖 frontmatter） |
| L | 多页 + 契约 + 设计还原 | ≤90m | 120m | multi-unit；unit 内 subagent；review shard | ❌ 强制 full |
| XL | 多仓 / 大重构 | 按 unit | — | worktree 隔离；禁止单闸门吞全量 | ❌ 强制 full |

**Index-Lite**：XS/S 推荐使用精简 index（6 段、伪代码 ≥80 chars），由 [`resolve_plan_index_rules.py`](../../goal-pipeline/scripts/resolve_plan_index_rules.py) 路由。gate 全保留，PQ-01/02/05/07 不降级。详见 [`index-lite-protocol.md`](../../goal-pipeline/references/index-lite-protocol.md)。

## 分级信号

- 新建页面目录数、write_set 文件数、跨域（pages/services/routing）
- 共享入口（`App.tsx` / `pages/index.ts`）
- 多 UI 表面（FailReason/Popup/List 等跨 page root）
- Figma 高保真 / `units[]` 文档声明

## Pack F 编排硬约束

1. **文件不相交 → subagent 并行**；共享入口由主编排**最后串行**合并
2. 切片用快模型；契约/合并用主模型
3. Watchdog：超过该档编码预算 80% 未汇合 → 收束为最小可过门禁切片
4. L+：unit 级并行 + 独立 evidence；冲突文件进 integration unit

## 全档公共底座（与档位无关）

- Pack A：smoke script 名、hash+stage、AM prune、stop hook 按 branch、PQ-07
- Pack D：UVO build 缓存、smoke 暖机、review packet/channel cache
- Pack E：UVO 内 typecheck ∥ jest `--maxWorkers=50%`
- Pack B：同 hash 贵操作单次；write_set shrink 不废审

## CLI

```bash
python3 ~/.goal-state/scripts/task_tier.py \
  --task-dir docs/guazi-flow/<task> \
  --plan-json <handoff>/plan.json \
  --state-file ~/.goal-state/projects/<pid>/<branch>/<task>/state.json \
  --stamp-state
```
