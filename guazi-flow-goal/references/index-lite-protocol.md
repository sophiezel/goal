# Index-Lite 协议（v3 §8.1）

> XS/S 任务的精简 plan 契约。gate 全保留，仅削减 index 篇幅与伪代码下限。

## 1. 启用条件（优先级从高到低）

1. **环境变量覆盖**：`GOAL_PLAN_PROFILE=lite` → 强制 lite；`GOAL_PLAN_PROFILE=full` → 强制 full
2. **frontmatter 显式声明**：`plan_profile: lite` 或 `task_tier: XS` / `task_tier: S`
3. **gate 预估算**（仅当 1–2 未命中）：
   - `write_set` 路径数 ≤3
   - 无新 `src/pages/` 目录
   - 无 `units[]` 声明
   - → lite
4. **plan post 回写校验**：`handoff/plan.json.task_tier` 为 XS/S → lite；M+ → **强制 full rules**（即使 frontmatter 写 lite 也被覆盖）

## 2. Lite vs Full schema 差异

| 项 | Full ([`plan-index-rules.json`](guazi-flow-artifact-schema/plan-index-rules.json)) | Lite（[`plan-index-rules-lite.json`](guazi-flow-artifact-schema/plan-index-rules-lite.json)） |
|----|---|-----|
| 必填章节 | 7 段：概览、任务目标、范围与非目标、核心事实、完整伪代码、验收与验证矩阵、执行记录 | 6 段：概览、任务目标、**范围与写集**（合并）、完整伪代码、验收与验证矩阵、执行记录 |
| 伪代码下限 | ≥200 chars | ≥80 chars |
| unit.md 拆分 | M+ 推荐 | XS/S 可单文件 index |
| PQ-01（write_set 非空） | block | **block（不降级）** |
| PQ-02（验收 ID ≥1） | block | **block（不降级）** |
| PQ-05（无未解决 P0） | block | **block（不降级）** |
| PQ-07（pages 须 build:beta） | block | **block（不降级）** |
| PQ-06（伪代码字数） | standard 200 / strict 500 | **lite 80** |
| PQ-08（机器可验列） | standard warn / strict block | **warn only** |
| PQ-09（验收行数 3–5） | 不适用 | **warn** |

## 3. PQ 规则交互（防打架）

- `plan_profile=lite` 时 PQ-08 恒 **warn**（硬质量靠 PQ-01/02/05/07 block 兜底）
- `plan_profile=full` 时 PQ-08 按 `quality_policy.tier`：standard=warn，strict=block
- PQ-09 仅 lite 生效；full 不检查行数

## 4. h5 / pages 边界（快车道不假装覆盖 UI 漏出）

- `plan_profile=lite` 且 write_set 触 `src/pages/`：**PQ-07 build:beta 仍 block**
- UI 交互漏出主路径仍在 **Phase A2**（strict+h5 e2e BLOCK）；XS 快车道 **不替代** e2e
- 可选后续：XS + pages 时 quality 强制 `runtime-smoke` path 命中（单列 ADR，不在 §8 W1）

## 5. 模板

见 [`index-lite-template.md`](index-lite-template.md)。

## 6. 路由实现

[`resolve_plan_index_rules.py`](../../goal-pipeline/scripts/resolve_plan_index_rules.py) 按上述优先级返回 rules JSON 路径（guazi runtime：`$GUAZI_STATE_HOME/scripts/resolve_plan_index_rules.py`）。`guazi-gate-stage.sh` 的 `py_check_index()` 调用 resolver，不再写死 `plan-index-rules.json`。
