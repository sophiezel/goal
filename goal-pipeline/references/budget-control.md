# Budget 控制

与 Claude Code 对齐的预算模型：

```json
{
  "max_tokens": 200000,
  "warning_threshold": 0.8,
  "tokens_used": 0,
  "review_tokens_used": 0,
  "max_turns": 50,
  "current_turn": 0
}
```

## 阈值行为

- `< 80%`: 静默
- `≥ 80%`: 轻量提示
- `≥ 95%`: 警告
- `≥ 100%`: 暂停，用户可 extend

## Token 统计规则

审核 token 单独统计（API 直调精确值），执行 token 估算（无 API usage 时按字符数/4）。

## 边缘场景

| 场景 | 行为 |
|------|------|
| budget ≥100% | 暂停，用户可 extend 或 /goal-pipeline-clear |
