# 生命周期管理

所有命令以 `/goal-pipeline` 为前缀。对于支持原生 /goal 的平台，同时提供平台级别名。

## 命令表

| 命令 | 操作 | 对齐 Claude Code |
|------|------|:---:|
| `/goal-pipeline <目标>` | 启动新 goal | /goal |
| `/goal-pipeline` | 恢复当前 active goal | /goal (no args) |
| `/goal-pipeline-status` | 读取 state.json + verify.sh，输出摘要 | /goal status |
| `/goal-pipeline-pause` | status = paused, 释放 .lock, 输出断点 | 暂停 |
| `/goal-pipeline-resume` | **MANDATORY**: 读 `references/consistency-check.md` → check-consistency → status = active | 继续 |
| `/goal-pipeline-clear` | 归档 state.json → archive/，保留 evidence/ | /goal clear |
| `/goal-pipeline-list` | 遍历 archive/，输出历史列表 | /goal list |

## status 输出格式

```
目标: 给项目加用户认证 | 状态: 活跃
管线: plan(✓) → implement(✓) → review( ) → complete( )
进度: 50% (2/4) | 审核: deepseek-v4-flash | 消耗: 2/50 轮
```

## pause / clear 行为

| 操作 | 行为 |
|------|------|
| pause | 写入 pause_reason + paused_at → 释放 .lock → 输出恢复提示 |
| clear | 归档 state.json → archive/<pid>/goal_<id>.json → 保留 evidence/ → 释放 .lock |
