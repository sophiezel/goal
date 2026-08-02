---
name: goal-quality
description: Lean quality 阶段（原生）。内部编排 smoke/validate/e2e + quality-gate.sh，Agent 只见 [3/5] quality。双轨共用。
---

# goal-quality

原生阶段，非 fork。将原 runtime_smoke + validate + e2e 收敛为单一 Agent 可见阶段。

## 必读

- `goal-pipeline/references/tiered-adjudication.md`
- `goal-pipeline/references/dual-track-contract.md`
- `goal-pipeline/references/goal-quality-e2e-profile.md`（#19：lite/standard/strict × validate/e2e 默认与 gate 证据）

## 内部编排（L0+L1）

```text
runtime-smoke.sh → quality-gate.sh → gate --post quality
```

`quality-gate.sh` **读取**已有证据，不重跑 smoke/UVO：

| 层 | 检查 | 失败级别 |
|----|------|----------|
| L0 | UVO overall=pass、handoff 链、secret（git diff 变更文件） | BLOCK |
| L1 | runtime-smoke.md result∈{pass,skipped}、IQ 结构检查 | BLOCK |
| L1 strict | index.md 是否提及 validate / e2e\|playwright | **WARN**（当前不 BLOCK；Agent 可按任务自行跑 validate/e2e 并写入 evidence） |

| tier | Agent 侧 validate/e2e |
|------|------------------------|
| standard（lite 或 full） | validate / e2e **默认 off**；test+lint 由 **UVO**（implement） |
| strict + full | validate / e2e **推荐**（h5 e2e 优先）；gate 对缺失引用 **WARN**，h5 缺 e2e 证据 **BLOCK** |
| strict + lite | 同 strict，但 Agent e2e 对非 h5 **默认 off**（墙钟）；质量面不 skip（#13） |

完整矩阵与 PQ/IQ/UVO dedupe：[goal-quality-e2e-profile.md](../../references/goal-quality-e2e-profile.md)。

## guazi adapter（可选）

`pipeline_track=compatibility|guazi` 时进度标签可显示 `guazi-flow-*` 前缀；gate 脚本仍为 `gate-goal-stage.sh`。

## Stage Exit

```bash
runtime-smoke.sh --repo-root <root> --task-dir <task>
bash quality-gate.sh --task-dir <task> --repo-root <root> --tier <tier>
gate-goal-stage.sh --stage quality --post
goal-advance-stage.sh
```

## NEVER

- NEVER 将 smoke/validate/e2e 作为独立 Agent 阶段对外暴露
- NEVER 跳过 quality-gate.sh
- NEVER 假设 quality-gate 会执行 Playwright/validate——它只汇总证据
