# Host Adapters（可选加强，非 Core）

控制面 Core 保证：走 `goal-pipeline-kernel` 则阶段序语义成立。  
会话内物理拒写 `src` 需要宿主 permission；本目录提供 **可选** 适配说明。

| 宿主 | 建议 |
|------|------|
| Claude Code | PreToolUse / permissions：当 `capability.code_writes_allowed=false` 时 deny Edit/Write 命中 `deny_write_globs` |
| Cursor | 可选 `preToolUse` 调 `assert-plan-before-code.sh` |
| 通用 | 包装 Agent Write：先 `kernel next`，再按 WO.capability 校验路径 |

**一律调用** 与 Kernel 同一判定，禁止宿主私造旁路规则：

- `goal-pipeline/scripts/assert_plan_before_code.py`（plan gate 前脏工作树）
- `goal-pipeline/adapters/assert_capability.py --work-order WO.json --path <file>`（消费 FrozenWorkOrder.capability）

未安装 adapter 时：`GOAL_HOST_GUARD=off`（默认）；doctor / `kernel next` 信封会标明。这不削弱四平面 Core 验收。
