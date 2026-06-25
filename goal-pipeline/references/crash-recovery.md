# Crash Recovery

## 状态恢复入口

Goal 状态存储在 `~/.goal-state/projects/<project_id>/<branch>/<task>/state.json`。
锁文件同目录 `.lock`。

## 崩溃场景

| 场景 | 检测 | 恢复方法 |
|------|------|---------|
| Agent crash | 下次启动时检测 state.json | 运行恢复流程 |
| state.json 损坏 | JSON parse 失败 | 从 git + evidence 重建 |
| .lock 残留 | lock 中 pid 不存活 | 接管 lock，继续 |
| Goal 状态与管线不一致 | check-consistency | 以管线事实为准 |
| 旧路径 state.json 存在 | `~/.guazi-flow-goal/` 旧目录 | 迁移到新路径 `~/.goal-state/` |

## 恢复流程

```
1. 计算 project_id = sha256($(git rev-parse --show-toplevel))[:12]
2. 解析 branch = $(git rev-parse --abbrev-ref HEAD) or "default"
3. 检测旧路径 → 存在则迁移
4. 检测 state.json → 读取 status
5. 运行 check-consistency → 分类处理
```

## 旧路径迁移

`~/.guazi-flow-goal/` → `~/.goal-state/`

检测旧目录存在且新目录不存在时自动 mv。JIRA_TOKEN、FIGMA_ACCESS_TOKEN 等非 goal 配置留在原地不动。
