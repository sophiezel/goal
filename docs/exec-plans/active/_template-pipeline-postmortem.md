# Pipeline Postmortem 模板

复制本文件为 `docs/exec-plans/active/<date>-<任务>-pipeline-postmortem.md` 并填写。

## 元信息

| 字段 | 值 |
|------|-----|
| 任务 ID | |
| 分支 | |
| goal commit | |
| 日期 | |

## 1. 墙钟分解

| 节点 | 起止 | 墙钟 | 说明 |
|------|------|------|------|
| plan | | | |
| implement | | | |
| quality | | | |
| review | | | |
| complete | | | |
| **总计** | | | |

## 2. 根因（Review 优先）

- **直接原因**：
- **结构性原因**（verify 重复 / packet 体积 / 无 fallback / 盲重试）：
- **分离度**（执行者 vs 审核者）：

## 3. 质量评估

| 阶段 | 评级 | 主要问题 |
|------|------|----------|
| plan | | |
| implement | | |
| quality | | |
| review | | |
| complete | | |

## 4. 优化动作与 Phase 映射

| ROI | 动作 | Phase | 状态 |
|-----|------|-------|------|
| P0 | UVO skip verify | 0 | |
| P0 | scoped diff + commit 顺序 | 0 | |
| P0 | API fallback chain | 0 | |
| P1 | packet 分片 + review_depth | 1 | |
| P1 | zh-CN annex | 1 | |
| P2 | readonly subagent | 2 | |
| P2 | benchmark replay | 2 | |

## 5. 度量对比

```bash
bash goal-pipeline/scripts/benchmark-pipeline-replay.sh \
  --task-dir <task> --profile ctb43806
```

| 指标 | 基线 | 目标 | 实测 |
|------|------|------|------|
| T_review | | ≤8 min | |
| T_retry | | 0 | |
| review_chain score | | ≥7/8 | |
| separation_score | | medium+ | |

## 6. 遗留与 follow-up

- 
