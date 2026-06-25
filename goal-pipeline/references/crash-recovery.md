# Crash Recovery

## 状态恢复入口

Goal 状态存储在 `~/.guazi-flow-goal/projects/<project_id>/<branch>/<task>/state.json`。
锁文件同目录 `.lock`。

## 崩溃场景

| 场景 | 检测 | 恢复方法 |
|------|------|---------|
| Agent crash | 下次启动时检测 state.json | 运行恢复流程 |
| state.json 损坏 | JSON parse 失败 | 从 git + evidence 重建 |
| .lock 残留 | lock 中 pid 不存活 | 接管 lock，继续 |
| Goal 状态与管线不一致 | check-consistency | 以 guazi-flow 事实为准 |
| 旧路径 state.json 存在 | `<project>/.guazi-flow/goal/state.json` | 迁移到新路径，删除旧文件 |

## 恢复流程

```
1. 计算 project_id = sha256($(git rev-parse --show-toplevel))[:12]
2. 解析 branch = $(git rev-parse --abbrev-ref HEAD) or "default"
3. 检测旧路径 → 存在则迁移
4. 检测 state.json → 读取 status
5. 运行 check-consistency → 分类处理
```

## 旧路径迁移

`<project>/.guazi-flow/goal/` → `~/.guazi-flow-goal/projects/<project_id>/<branch>/<task>/`

`<project>/.guazi-flow/config.local.json` 中的 goal 相关字段（api key / review_model）→ 迁移到 `~/.guazi-flow-goal/config.json`，删除旧字段。

JIRA_TOKEN、FIGMA_ACCESS_TOKEN、repos 留在原地不动。
