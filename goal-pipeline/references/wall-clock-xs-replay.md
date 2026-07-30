# XS 墙钟对比（方案 A）— §8.5 #4

> 静态 `benchmark-pipeline-replay.sh` 不测 Agent 墙钟。须用**同一条真实 XS 任务**跑两遍对比。

## 前置

- 已 merge §8 优化（Index-Lite + 单轨 + info_gain + commit-before-review）
- 选定一条 XS 任务：有 JIRA/明确验收、write_set ≤3 路径、无新 pages 目录为佳

## 步骤

### 1. 基线（优化前，若未保留则跳过）

在优化前分支或历史任务目录记录：

```bash
# 任务完成后从 state / 日志提取
PLAN_MS=...      # plan gate --post 完成 → implement 开始
REVIEW_MS=...    # review chain 完成墙钟
TOTAL_MS=...     # 用户发需求 → complete gate exit 0
```

已有 fixture 基线见 `goal-pipeline-workspace/baselines/xs-v3-pre.json`（仅 wiring，非墙钟）。

### 2. 优化后（当前分支）

```bash
export GOAL_PLAN_PROFILE=lite          # XS/S 推荐
# eval 通过后再开：
# export GOAL_REVIEW_SINGLE_DEFAULT=1

# 跑完整 pipeline（/goal-pipeline <目标> 或 guazi-flow-goal）
# 记录各阶段时间戳到 index ## 执行记录 或 state.json
```

### 3. 对比门槛（§8.5 #4）

| 指标 | 通过标准 |
|------|----------|
| `total_ms` | 较基线 **↓≥25%** |
| 或 `plan_ms + review_ms` | 合计 **↓≥30%** |

### 4. 记录模板

```json
{
  "task_id": "<JIRA or slug>",
  "baseline": { "plan_ms": 0, "review_ms": 0, "total_ms": 0, "recorded_at": "" },
  "post_v3": { "plan_ms": 0, "review_ms": 0, "total_ms": 0, "recorded_at": "" },
  "plan_profile": "lite",
  "review_track": "single",
  "reduction_pct": { "total": 0, "plan_plus_review": 0 },
  "passed": false
}
```

保存到：`goal-pipeline-workspace/baselines/xs-v3-wallclock.json`

## 你需提供

1. **一条 XS 任务描述**（或已有 `docs/guazi-flow/.../index.md` 路径）
2. **优化前墙钟**（若有历史记录）；没有则本次跑完只记 post，后续补 baseline
