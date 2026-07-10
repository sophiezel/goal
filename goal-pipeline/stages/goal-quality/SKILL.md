---
name: goal-quality
description: Lean quality 阶段（原生）。内部编排 smoke/validate/e2e + quality-gate.sh，Agent 只见 [3/5] quality。双轨共用。
---

# goal-quality

原生阶段，非 fork。将原 runtime_smoke + validate + e2e 收敛为单一 Agent 可见阶段。

## 必读

- `goal-pipeline/references/tiered-adjudication.md`
- `goal-pipeline/references/dual-track-contract.md`

## 内部编排（L0+L1）

```text
runtime-smoke.sh → validate? → e2e? → quality-gate.sh → gate --post quality
```

| tier | validate | e2e |
|------|----------|-----|
| standard | optional | optional |
| strict | required | required |

## Stage Exit

```bash
runtime-smoke.sh --repo-root <root> --task-dir <task>
bash quality-gate.sh --task-dir <task> --repo-root <root> --tier <tier>
gate-guazi-flow-stage.sh --stage quality --post
goal-advance-stage.sh
```

## L2 条件触发

仅当 smoke/validate/e2e 结果为 `inconclusive`/`partial`/`skipped` 时启用子域 LLM judge。

## NEVER

- NEVER 将 smoke/validate/e2e 作为独立 Agent 阶段对外暴露
- NEVER 跳过 quality-gate.sh
