---
name: goal-implement
description: goal-pipeline implement 阶段。implement-verify、V# 覆盖声明、write_set 合规。Use with /goal-pipeline (default track).
---

# goal-implement

**SSOT** for implement stage. guazi-flow-implement is optional via `pipeline_track=compatibility|guazi` appendix.

## 必读

- `goal-pipeline/references/dual-track-contract.md`
- `goal-pipeline/references/declarative-contract-gates.md`（IQ-10 / integration manifest）

## goal_patches

1. **implement-verify**：完成代码后跑项目 test/lint（IQ-01）
2. **V# 覆盖声明**：在 index.md 执行记录声明已覆盖的 V# 列表（strict tier IQ-02）
3. **write_set 合规**：diff ⊆ write_set
4. **声明式契约**：`gate --post implement` 内强制执行 `contract-conformance-check.py`（IQ-10，当 index 含 API 映射表）；若存在 `handoff/integration-manifest.json` 则跑 `integration-contract-check.sh`（失败记 `integration_gap`）。见 [`declarative-contract-gates.md`](../../references/declarative-contract-gates.md)。
5. **UX D2/D5 auto-fix（C1 P1-9）**：在 `write_set` 内由本阶段尝试 D2（`loading`/`disabled`）与 D5（`aria-label`/`aria-labelledby`）最小修复；Goal 无内置 codemod。`gate --post implement` 跑 `ux-auto-fix-audit.py`，留痕 `evidence/ux-autofix.json`；S+（`task_tier` M/L/XL）审计失败 block（`write_set_violation`），XS/S 仅 warn。见 [`ux-auto-fix-c1.md`](../../references/ux-auto-fix-c1.md)。

## guazi adapter（可选）

`pipeline_track=compatibility|guazi` 时可对照上游 `guazi-flow-implement/SKILL.md` 作为附录。

## Stage Exit

```bash
gate-goal-stage.sh --stage implement --pre
# 按 profile/contract 实现
python3 implement-qc-gate.py --task-dir <task> --repo-root <root>
gate-goal-stage.sh --stage implement --post
validate-pipeline-chain.sh --task-dir <task>
```

## NEVER

- NEVER 在 gate --post 前输出 [2/5] ✅
- NEVER 超 write_set 改文件而不更新 plan
