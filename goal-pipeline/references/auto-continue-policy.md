# Auto-Continue Policy

## 核心模型

所有平台采用**统一的 agent 持续执行模型**：

```
Agent 加载 goal-pipeline
  → Phase 1: Goal Engineering (访谈 + 生成 + 初始化)
  → Phase 2: Pipeline Execution (连续 agent turn, 不停止直至 done/blocked)
```

不需要平台提供特殊循环机制。Agent mode 在所有主流 coding agent 中天然支持在一个 turn 内连续调用工具，直到任务完成或遇到显式停止信号。

## 停止条件

Agent 在以下任一条件满足时停止执行，返回控制权给用户：

| 停止条件 | 判定方式 | Goal 状态 |
|---------|---------|:--:|
| 管线全部完成 | `verify.sh` → `completion_condition_met: true` | complete |
| 阶段阻塞（不可自动恢复） | failure_code 命中需用户输入 | blocked |
| 审核不可用 | 所有审核通道不可用 | blocked |
| 审核不确定 | 审核 JSON 解析失败 + 重试耗尽 | blocked |
| 预算耗尽 | `current_turn >= max_turns` | blocked |
| 空转 | 连续 3 轮 `current_stage` 无推进 | blocked |
| 用户中断 | 用户按下停止/打断 | paused |
| 致命错误 | API 调用连续失败 3+ 次 | blocked |

## 进度输出

每完成一个阶段后输出进度摘要:

```
─────────────────────────────────────────
[1/5] plan:      ✅ 完成 (任务文档已生成)
[2/5] implement: 🔄 执行中...
[2/5] implement: ✅ 完成 (3 files changed)
[3/5] smoke:     ✅ / skipped（无法推导 dev 命令）
[4/5] review:    🔄 独立审核中... (deepseek-v4-flash)
[4/5] review:    ✅ 通过
[5/5] complete:  ✅ 完成
─────────────────────────────────────────
✅ 目标完成
  📁 证据: evidence/
  📝 修改: src/auth/ (3 files)
  🔍 审核: deepseek-v4-flash (分离置信度: high)
  📊 耗时: 3 轮
```

## 阻塞时的输出

```
─────────────────────────────────────────
[4/5] review: ❌ 未通过
─────────────────────────────────────────
⚠️ Goal 已暂停

  阻塞原因: review 发现 2 个阻断问题
  证据路径: evidence/review.md
  问题:
    1. [blocker] authService 未按契约返回 refreshToken
    2. [warning] Login.tsx 缺少 loading 状态处理
  
  下一步:
    [A] 自动修复后重试 review
    [B] 人工检查 diff 后手动确认
    [C] 修改 Goal 范围后重试
    [D] 放弃本次 goal
```

## 空转检测

```
每轮记录当前阶段:
  turn N:   stage = implement
  turn N+1: stage = implement  ← 未推进
  turn N+2: stage = implement  ← 未推进
  turn N+3: stage = implement  ← 空转！暂停

暂停原因: 连续 3 轮没有阶段推进
可能原因: agent 在 implement 阶段反复修改但未完成
建议: 检查候选 diff 或调整验收标准
```

## 跨 session 恢复

Goal 状态通过 `state.json` 持久化。跨 session 恢复：

1. Agent 启动 → 检测 `~/.goal-state/projects/<pid>/<branch>/<task>/state.json` 存在且 `status ∈ {active, blocked, paused}`
2. 提示用户: "检测到未完成的 goal: <objective>，是否恢复?"
3. 用户确认 → 运行 `check-consistency` → 从断点继续
4. 用户拒绝 → goal 标记为 paused

**不依赖平台原生 goal 的持久化能力。** `state.json` 自建持久化在所有平台统一工作。


## 阶段推进（goal-advance-stage.sh）

Phase 2 每阶段结束 **MANDATORY** 运行：

```bash
~/.goal-state/scripts/goal-advance-stage.sh \
  --state-file <state.json> \
  --task-dir <docs/guazi-flow/task> \
  --project-root <repo_root>
```

- exit 0 + next_stage != done → **立即**进入 next_stage（禁止交还控制权）
- exit 1 → 管线完成，可结束 turn
- exit 2 → blocked，输出 failure_code

Agent **不得**在 implement 完成后停止；next_stage=review 时必须自动加载 guazi-flow-review。

## Stop Hook 联动

Session 结束前 Stop Hook 运行：

```bash
gate-guazi-flow-stage.sh --assert-complete --state-file ... --task-dir ... --project-root ...
```

exit 2 → 返回 followup_message 续跑 pipeline。

