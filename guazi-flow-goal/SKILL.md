---
name: guazi-flow-goal
description: guazi-flow 独立管线入口（v1.4）。使用 `/guazi-flow-goal <目标>` 启动；MUST 调度 guazi-flow-plan/implement/review/complete + guazi-gate-stage.sh；review 经 REVIEW_KERNEL_HOME。不加载 goal-pipeline 脚本。Use when executing guazi-flow tasks with index.md contract, split handoff, and JIRA/profile integration. Do NOT use for pure goal-pipeline `/goal-pipeline` goals or when guazi-flow-* skills are unavailable.
---
# Guazi Flow Goal（v1.4 独立栈）

**不依赖 goal-pipeline。** Pre-flight：`bash guazi-flow-goal/scripts/guazi-install.sh` → `~/.guazi-flow/` + `~/.goal-services/review-kernel/`。

| 组件 | 路径 |
|------|------|
| Gate | `$GUAZI_STATE_HOME/scripts/guazi-gate-stage.sh` |
| Advance | `$GUAZI_STATE_HOME/scripts/guazi-advance-stage.sh` |
| Review chain | `$REVIEW_KERNEL_HOME/bin/run-review-chain.sh` |
| State | `$GUAZI_STATE_HOME/projects/<pid>/<branch>/<task>/state.json` |

环境变量：`GUAZI_STATE_HOME`（默认 `~/.guazi-flow/state`）、`REVIEW_KERNEL_HOME`（review-kernel 安装路径）。

阶段 SKILL（Lazy Load）：`guazi-flow-plan` / `guazi-flow-implement` / `guazi-flow-review` / `guazi-flow-complete`；`review_track=single` 时可跳过 guazi-flow-review，仅走 review-kernel unified 分支。

**禁止** exec `goal-pipeline/scripts/*` 或读写 `~/.goal-pipeline/`。

> **UVO + preflight + hash-split**：L1 权威为 `verification-oracle.sh` 一次；review 前 `review_packet_preflight.py`；stale 用 `code_subject_hash`。推荐 **commit feature 后再跑 gates**。`task_tier`（XS–XL）见 `references/task-tier-matrix.md`。

## NEVER

- **NEVER exec `goal-pipeline/scripts/*` 或读写 `~/.goal-pipeline/`**（v1.4 边界）
- **NEVER 跳过阶段 Lazy Load**——未读 `guazi-flow-<stage>/SKILL.md` 不得执行该阶段
- **NEVER 输出 `[N/5] ✅` 而未 `guazi-gate-stage.sh --post` exit 0**
- **NEVER 在 index.md + gate --post plan 通过前进入 implement**
- **NEVER 绕过 review-kernel 独立审核**——MUST assemble → run-review-chain → merge → gate --post review
- **NEVER gate 失败后盲重试**——MUST Read `evidence/<stage>-gate-fix-input.json` 或 `review-fix-input.json`
- **NEVER 在 [5/5] complete 前交还控制权**——implement 完成 ≠ goal 完成

## 关键话术

**用户催促「先写代码」** — MUST 拒绝（含 **不能跳过** + **gate --post plan**）：

> **不能**在 plan gate 通过前写代码。`handoff/plan.json` 未就绪时 **不得** implement；Index-Lite 仅精简 index，**不降级** PQ 门禁。

**infra 缺失** — `guazi-install.sh` 或 blocked(infra_missing)；**不** fallback 到 goal-pipeline。

## 必读 references

### 启动时（MANDATORY）

| 文件 | 用途 |
|------|------|
| `references/guazi-flow-integration.md` | 调度规则与产物 GATE |
| `references/bridge-contract.md` | v1.4 扩展字段（无 goal 桥接） |
| `references/guazi-flow-state-schema.md` | state 路径与字段 |

### 阶段内按需

| 时机 | 文件 |
|------|------|
| Phase 1 | `references/interview-protocol.md`、`references/platform-detection.md` |
| plan | `references/task-tier-matrix.md`、`references/index-lite-protocol.md`（XS/S） |
| review | `references/separation-strategies.md`、review-kernel 契约 |
| 集成任务 | `references/decisions-handoff-protocol.md` |

脚本处理、无需预读：`references/artifact-tier-policy.md`、`references/stage-handoff-contract.md`。

## Phase 1: Goal Engineering

```
Step 1: Pre-flight
  ├─ guazi-install.sh（若 $GUAZI_STATE_HOME/scripts 缺失）
  ├─ 验证 guazi-gate-stage.sh + $REVIEW_KERNEL_HOME/bin/run-review-chain.sh
  └─ 缺失 → blocked(infra_missing)

Step 2-3: 访谈（interview-protocol.md）+ profile 推断（guazi-flow-doctor 若可用）

Step 4: Goal 结构确认（目标 / 验收 / Allowed Files / Stop Conditions）

Step 5: 初始化 state（guazi-flow-state-schema.md）
  ├─ mkdir -p $GUAZI_STATE_HOME/projects/<pid>/<branch>/<task>/
  ├─ state.json：project_root、guazi_flow_task、artifact_layout（split）
  └─ **NEVER** 使用 ~/.goal-pipeline/

Step 6: GATE Check → 全部通过才进入 Phase 2
```

Fast-path：可缩减访谈，**不可**跳过 state.json、index schema、gate --post plan。

## Phase 2: Pipeline Execution

### Turn Protocol

每个 Agent turn **第一步**：

1. Read `state.json` → `current_stage` / `status`
2. 若 `blocked` → 按 `failure_code` + fix-input 执行，**不得**新功能
3. 若 `code_writes_allowed=false`（plan 未完成）→ **禁止**写业务代码

每阶段顺序（MANDATORY）：

```
guazi-gate-stage.sh --task-dir <task> --stage <stage> --pre --mode guazi --state-file <state>
→ Read guazi-flow-<stage>/SKILL.md 全文并执行
→ guazi-gate-stage.sh --stage <stage> --post --mode guazi --state-file <state> --project-root <repo>
→ exit 0 才输出 [N/5] guazi-flow-<stage>: ✅
→ 立即进入 next_stage（**禁止**询问用户是否继续）
```

| 阶段 | Lazy Load | Gate |
|------|-----------|------|
| plan | guazi-flow-plan | plan post → index.md + handoff/plan.json |
| implement | guazi-flow-implement | UVO 一次 + implement post |
| quality | goal-quality（仓外/profile） | smoke + quality-gate |
| review | guazi-flow-review 或 review-kernel only | assemble → chain → merge → post |
| complete | guazi-flow-complete | verify + complete post |

**review 单轨**（`review_track=single`）：不加载 guazi-flow-review；`$REVIEW_KERNEL_HOME/bin/run-review-chain.sh` unified + rubric in packet。

**handoff** 仅由 gate `--post` 写入；Agent **禁止**手写 `handoff/*.json`。

### implement Stage Exit（重读）

implement 代码完成 **≠** 阶段结束。MUST：

```
guazi-gate-stage.sh --stage implement --post ...
→ 读 state next_stage → 立即 quality/review
```

**反例**：「实现完成，需要我继续 review 吗？」

### 修复子循环

MUST 只读 `evidence/review-fix-input.json` 的 `action` / `issues` / `next_steps`。`blocked_stagnant` → 停止盲修复，呈现 A/B/C 选项。

## 进度输出

```
[1/5] guazi-flow-plan: ...
[2/5] guazi-flow-implement: ...
[3/5] goal-quality: ...        # quality 阶段 skill 名来自 profile
[4/5] guazi-flow-review: ... # 或 review-kernel unified
[5/5] guazi-flow-complete: ✅
```

## 写入边界

| 路径 | 操作 |
|------|------|
| `$GUAZI_STATE_HOME/**` | state、handoff（split Tier-R）、lock |
| `docs/guazi-flow/<task>/index.md` 等 Tier-G | guazi-flow-* 产出，进 git |
| `docs/guazi-flow/<task>/handoff/**` | split 模式下 **不写** repo |
| 业务代码 | guazi-flow-implement（write_set 内） |
| `~/.goal-pipeline/**` | **禁止** |

## 错误处理

| 场景 | 行为 |
|------|------|
| infra_missing | blocked；运行 guazi-install.sh |
| guazi-flow-core 版本不兼容 | blocked；升级 guazi-flow marketplace |
| plan_artifact_missing / plan_schema_incomplete | blocked；重跑 guazi-flow-plan 完整流程 |
| gate failed | Read fix-input；Judge/Executor 分离 |
| goal_already_active | [继续/清除/查看] |

## 完成门禁

- `state.json` status = complete
- `evidence/complete.md` + `evidence/review.md` pass+fresh
- index.md 契约段（allowed_patterns / exclusions / stop_conditions）存在
- verify.sh → completion_condition_met

## Eval / fixture

- Gate 夹具：`guazi-flow-goal/fixtures/guazi-gate/run-all-gate-tests.sh`
- 桥接契约：`references/bridge-contract.md`
