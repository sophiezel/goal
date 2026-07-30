# Dual-Track Contract（双轨架构契约）

goal 仓库内 **进化轨** 与 **兼容轨** 的边界与共享约定。

## 两轨定义

| 轨 | 入口 | 阶段执行 | 优化空间 |
|----|------|----------|----------|
| **进化轨** | `/goal-pipeline` | `goal-pipeline/stages/goal-*` | 可 fork 优化 |
| **兼容轨** | `/guazi-flow-goal` | 黑盒 `guazi-flow-*` + 质检防火墙 | 仅编排与 gate，不改原 skill |

## 共享层（单一真相）

- **产物**：`docs/guazi-flow/<task>/index.md`、handoff JSON、evidence/
- **脚本**：`plan-quality-gate.py`、`implement-qc-gate.py`、`quality-gate.sh`
- **状态**：`~/.goal-state/projects/.../state.json`
- **修复循环**：`review-fix-input.json`、`quality-gate-fix-input.json`

## Lean 5 阶段（Agent 可见）

```text
plan → implement → quality → review → complete
```

- 进化轨：加载 `goal-plan` … `goal-complete`
- 兼容轨：加载 `guazi-flow-plan` … + 防火墙脚本

## 质检防火墙（兼容轨专用插入点）

```text
guazi-flow-plan → plan-quality-gate.py (PQ-01..PQ-14) → gate --post plan
guazi-flow-implement → implement-qc-gate.py (IQ-01..02) + contract-conformance-check.py (IQ-10) → gate --post implement
```

语义契约（表驱动，无业务硬编码）：PQ-10 API 映射自洽、PQ-11 响应 VO、PQ-12 冻结决策、IQ-10 实现↔映射表。术语与边界见 [`declarative-contract-gates.md`](declarative-contract-gates.md)；适配器见 [`profile-contract-adapters.md`](profile-contract-adapters.md)。

进化轨将 PQ/IQ 规则 **内嵌** 到 `goal-plan` / `goal-implement` SKILL，并调用同一脚本。

## NEVER

- NEVER 修改 `~/.agents/skills/guazi-flow-*` 原 skill 文件
- NEVER 为两轨各写一套 plan-quality-gate（必须共用脚本）
- NEVER 在兼容轨跳过 plan/implement 防火墙（policy=required 时）

## quality_policy 档位

| tier | validate | e2e | 说明 |
|------|----------|-----|------|
| standard | optional | optional | 默认 |
| strict | required | required | P0 UI / 核心链路 |

写入 `state.json.quality_policy.tier`。
