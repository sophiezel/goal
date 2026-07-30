---
name: goal-implement
description: 进化轨 implement 阶段。Fork 自 guazi-flow-implement，叠加 implement-verify 与 V# 覆盖声明。Use with /goal-pipeline when pipeline_track=evolution.
---

# goal-implement

Fork-and-Own 自 `guazi-flow-implement`。

## 必读

- `goal-pipeline/references/dual-track-contract.md`
- 上游 `guazi-flow-implement/SKILL.md`

## goal_patches

1. **implement-verify**：完成代码后跑项目 test/lint（IQ-01）
2. **V# 覆盖声明**：在 index.md 执行记录声明已覆盖的 V# 列表（strict tier IQ-02）
3. **write_set 合规**：diff ⊆ write_set
4. **声明式契约**：`gate --post implement` 内强制执行 `contract-conformance-check.py`（IQ-10，当 index 含 API 映射表）；若存在 `handoff/integration-manifest.json` 则跑 `integration-contract-check.sh`（失败记 `integration_gap`）。见 [`declarative-contract-gates.md`](../../references/declarative-contract-gates.md)。

## Stage Exit

```bash
gate-guazi-flow-stage.sh --stage implement --pre
# 按 profile/contract 实现
python3 implement-qc-gate.py --task-dir <task> --repo-root <root>
gate-guazi-flow-stage.sh --stage implement --post
validate-pipeline-chain.sh --task-dir <task>
```

## NEVER

- NEVER 在 gate --post 前输出 [2/5] ✅
- NEVER 超 write_set 改文件而不更新 plan
