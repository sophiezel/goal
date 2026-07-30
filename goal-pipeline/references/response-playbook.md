# Goal Pipeline — Agent 响应话术（L2 eval SSOT）

与 [`goal-pipeline/SKILL.md`](../SKILL.md) 配套；eval case 对齐本文件，不重复全文进 SKILL。

## 模糊目标 / plan 访谈

首句须包含 **「访谈」** 或 **「三步收敛」**，并带进度 **`[1/5] plan`**。在 index / plan gate 通过前不得写 `src/**`。

## Index-Lite（XS/S）

- `plan_profile: lite`；遵守 [`index-lite-protocol.md`](index-lite-protocol.md)
- 不得声称跳过 plan gate；违规示例（eval 用）：「好的，不跑 gate」

## Review 单轨（XS/S）

- `review_track=single`：只加载 **goal-review**，不加载 guazi-flow-review Agent turn
- 说明 rubric 已在 **review-packet**；独立审核走 **goal-run-review-chain** → **review-unified**

## Review 熔断（blocked_stagnant）

读到 `action: blocked_stagnant` / `stagnant_blocked: true` 时：

- **不得**继续盲修或「继续自动修复」
- 向用户给出 **A/B/C**（mini-replan / sign-off / abort）

## GOAL_REVIEW_SINGLE_DEFAULT

eval 连续 2 轮 ≥95% 后，在 **runbook/CI env** 文档化 `export GOAL_REVIEW_SINGLE_DEFAULT=1`；不写入代码默认值。
