# Tiered Adjudication（分层裁决）

质量裁决 **不** 为每个子阶段强制独立 LLM；按层级与条件触发。

## L0 — 确定性门禁（必跑）

- handoff schema / provenance
- secret scan
- flaky 探针（e2e 重试上限）
- `plan-quality-gate` / `implement-qc-gate` / `quality-gate.sh`

## L1 — 可执行 Oracle（必跑）

| 检查 | 脚本 |
|------|------|
| smoke | `runtime-smoke.sh` |
| validate | `guazi-flow-validate` cases（policy 要求时） |
| e2e | Playwright exit code（policy 要求时） |
| test+lint | `quality-gate.sh` standard+ |

## L2 — 条件独立 LLM

仅当 L1 结果为 `inconclusive` / `partial` / `skipped` 时触发子域 judge。

## L2 — 强制独立 LLM

`review_unified`：**始终** cross-provider 独立模型（`run-independent-review.sh`）。

## quality 阶段内部编排

```text
smoke → validate? → e2e? → quality-gate.sh → handoff quality.json
```

单一 `quality-gate.sh` 汇总 L0+L1；不对外暴露 smoke/validate/e2e 为独立 Agent 阶段。
