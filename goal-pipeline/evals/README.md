# Goal Pipeline — Skill Eval

## 分层

| 层 | 测什么 | 命令 | 可信度 |
|----|--------|------|--------|
| L0 | Gate fixture / 脚本 | `goal-pipeline/scripts/fixtures/guazi-flow-gate/run-gate-tests.sh` | 高 |
| L1 | Kernel 单测（merge / port） | `pytest goal-pipeline/kernel/tests`（如有） | 高 |
| L2 | Agent 编排话术 | `skill-up run evals/eval.yaml --iteration 1` | 中（关键词 judge） |

L2 **不能**替代 L0。话术 SSOT：[`references/response-playbook.md`](../references/response-playbook.md)。

## 运行（P2）

```bash
cd goal-pipeline
skill-up run evals/eval.yaml --iteration 1 \
  --output-dir ../goal-pipeline-workspace/eval-final/iteration-1
```

- `--iteration 1` 是 skill-up 引擎参数，**不是**「第 N 轮目录名」。
- 第二轮请用新目录，例如 `eval-final/iteration-2`。

门槛：连续 2 个独立 output 目录各 ≥95%（≥7.6/8）后，在 runbook 文档化 `GOAL_REVIEW_SINGLE_DEFAULT=1`。

详见 [`references/p2-eval-runbook.md`](../references/p2-eval-runbook.md)。
