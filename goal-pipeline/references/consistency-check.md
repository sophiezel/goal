# Consistency Check

## 目的

交叉校验 Goal 状态（state.json）、guazi-flow 管线状态（index.md + evidence）、git 状态。

## 路径

- state.json: `$GUAZI_GOAL_HOME/projects/<project_id>/<branch>/<task>/state.json`
- index.md: `<project>/docs/guazi-flow/<task>/index.md`
- evidence: `<project>/docs/guazi-flow/<task>/evidence/*.md`

## 校验规则

### state.json vs index.md current_stage
- Goal complete 要求 index current_stage = complete
- Goal 非 complete 时 index current_stage 应 ≤ Goal 记录的 last_stage

### Evidence 完整性
- current_stage = implement → evidence/plan.md 必须存在且 pass + fresh
- current_stage = review → evidence/plan.md + implement.md 必须存在且 pass + fresh
- current_stage = complete → evidence/complete.md 必须存在且 pass

### Evidence freshness
- evidence git_head 必须与当前 git rev-parse HEAD 一致
- 不一致 → stale，需重跑对应阶段

### 锁检查
- lock 存在 + pid 不存活 → 可接管
- lock 存在 + pid 存活 + heartbeat 超 5min → 可能死锁

### 全局配置检查
- `~/.guazi-flow-goal/config.json` 存在且 JSON 合法 → 正常
- 缺失 → 创建骨架
- 不合法 → 警告，使用空配置
