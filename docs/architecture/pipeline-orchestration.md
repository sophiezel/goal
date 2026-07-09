# Pipeline Orchestration

Goal-pipeline + guazi-flow-goal 编排架构（机器门禁 + 可续跑工单）。

## 三层模型

| 层 | 组件 | 职责 |
|----|------|------|
| 软约束 | `guazi-flow-goal/SKILL.md` NEVER 条款 | Agent 行为约定 |
| 硬约束 | `gate-guazi-flow-stage.sh`, `validate-pipeline-chain.sh`, `goal-advance-stage.sh` | 产物校验、handoff 写入 |
| Hook 补救 | `goal-pipeline-stop-hook.sh` | turn 结束前 `gate --assert-complete` |

**原则**：SKILL 写 MUST 的，gate 或 driver 必须能 FAIL。

## Turn Protocol

每个 Agent turn：

1. `goal-pipeline-recover.sh`（resume 时）
2. `goal-stage-driver.sh` → 唯一 work_order
3. 按 `mandatory_commands` 执行当前阶段
4. `gate --post` → chain → advance → driver（下一阶段）
5. Turn 结束：`gate --assert-complete` exit 0

### Review 阶段 mandatory（含 refresh）

```
refresh-handoffs-after-index.sh   # 执行记录漂移时 cascade implement；契约变更 cascade plan；已 fresh 则 no-op
gate --pre review                 # 缺 packet 时自动 assemble；仅 contract_hash 变化才 stale FAIL
goal-run-review-chain.sh          # assemble → independent review → merge
gate --post review
goal-advance-stage.sh
```

`index_contract_hash` 排除 `## 执行记录`，避免「补执行记录 → plan handoff stale → 多轮重跑」。

## handoff 状态机

进度真相：`handoff/{plan,implement,smoke,review,complete}.json`

- `index.md current_stage` 仅展示，由 gate `--post` 同步
- 禁止 Agent 手写 handoff

阶段顺序：plan → implement → runtime_smoke → review → complete

## 脚本边界

| 脚本 | 用途 |
|------|------|
| `goal-stage-driver.sh` | 工单 JSON + mandatory_commands |
| `goal-run-review-chain.sh` | assemble → review → merge 原子链 |
| `goal-pipeline-recover.sh` | 断点诊断与修复命令 |
| `goal-pipeline-doctor.sh` | VERSION/hooks/channels 诊断 |

**不修改** `guazi-flow-plan/implement/review/complete` skill 本体；只改 goal 侧编排。

## Review 统一通道

- 默认 `GOAL_REVIEW_MODE=unified`（Guazi Flow rubric 存在时）；纯 goal 任务为 `goal`
- 仅 deterministic 时 → `review_undetermined` → gate post review FAIL
- CI：`GOAL_REVIEW_FORCE_DETERMINISTIC=1`

## Stop Hook

- `loop_limit` 默认 10（`GOAL_STOP_HOOK_LOOP_LIMIT` 可覆盖）
- incomplete → `goal-stage-driver` 生成 followup_message
