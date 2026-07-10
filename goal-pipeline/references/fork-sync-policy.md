# Fork Sync Policy

从上游 `guazi-flow-*` 向 `goal-pipeline/stages/` 同步的最小策略。

## 触发条件

- 上游 skill 发布新版本且 bridge-contract `required_version` 变更
- fork-manifest 中 `goal_patches` 与上游冲突

## 同步步骤

1. 只读对比上游 SKILL.md 与本地 `goal-plan` 等 diff
2. 保留 `goal_patches` 段落不被覆盖
3. 更新 `fork-manifest.yaml` 的 `forked_at` 与 `upstream_version`
4. 跑 `run-all-gate-tests.sh` 回归

## 不回灌

- NEVER 将 goal 优化 patch 写回 `~/.agents/skills/guazi-flow-*`
