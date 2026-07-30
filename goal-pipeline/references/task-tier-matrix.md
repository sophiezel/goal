# task_tier 分层矩阵

见 `guazi-flow-goal/references/task-tier-matrix.md`（权威副本同结构）。

脚本：`scripts/task_tier.py`（同步部署到 `~/.goal-pipeline/state/scripts/task_tier.py`）。

Plan gate `--post` 自动 stamp `task_tier` / `task_tier_meta` 到 plan.json 与 state.json。
