# Pipeline Orchestration

权威目标态见 [`goal-runtime.md`](./goal-runtime.md)（四平面 + Kernel 协议）。

本文描述 **运行时接线**：Agent 如何调用 Kernel；旧脚本如何降级为内部实现。

## 对外入口（收敛后）

| 入口 | 用途 |
|------|------|
| `goal-pipeline-kernel` | **唯一**编排 CLI：`init` / `next` / `gate` / `status` / `doctor` / `complete` |
| `goal-pipeline-doctor.sh` | 亦可经 `kernel doctor` 调用 |

## Turn Protocol（Kernel）

```text
goal-pipeline-kernel next --state-file S --task-dir T --project-root R
  → FrozenWorkOrder (JSON)
执行 WO.mandatory_commands（含 stage skill）
goal-pipeline-kernel gate --stage <stage> --post --state-file S --task-dir T --project-root R
goal-pipeline-kernel next …
退出：goal-pipeline-kernel complete …
```

Stop Hook 仍可在 turn 结束调用 `gate --assert-complete`（经 Kernel 或内部脚本）。

## 内部实现（兼容期可直调，非对外产品叙事）

| 脚本 | 归属平面 | 说明 |
|------|----------|------|
| `goal-stage-driver.sh` | 控制面 | `kernel next` 的内核 |
| `gate-guazi-flow-stage.sh` | 控制+质量 | `kernel gate` 的内核 |
| `goal-advance-stage.sh` | 控制面 | 阶段推进 |
| `assert-plan-before-code.sh` | 控制面 | 并入 plan 不变量 |
| `validate-pipeline-chain.sh` | 数据+质量 | chain |
| `refresh-handoffs-after-index.sh` | 数据面 | HashPolicy |
| `goal-run-review-chain.sh` | 质量面 | review 原子链 |
| `runtime-smoke.sh` / `quality-gate.sh` | 质量+效率 | quality 阶段 |
| `verification-oracle.sh` | 质量面 | UVO once |
| `record-pipeline-timing.py` | 效率面 | UTC timing |

## 阶段顺序

`plan → implement → quality → review → complete`（smoke 别名归 quality）

## Review

- 默认 unified；ChannelPolicy：0 通道 → `separation=degraded`，不得伪装 full pass
- CI：`GOAL_REVIEW_FORCE_DETERMINISTIC=1`

## 原则

- SKILL 写 MUST 的，Kernel/gate **必须能 FAIL**
- 禁止第 N 旁路脚本产品化；新逻辑进四平面
- **不修改** `guazi-flow-plan/implement/review/complete` 业务 skill 本体职责；只改 goal 侧编排表面
