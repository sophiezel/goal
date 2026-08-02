---
name: goal-complete
description: goal-pipeline complete 阶段。产出 ready_for_production 候选与质量报告。Use with /goal-pipeline (default track).
---

# goal-complete

**SSOT** for complete stage. `complete` = 本地候选就绪，**不**自动 commit/push/MR。guazi-flow-complete is optional via `pipeline_track=compatibility|guazi` appendix.

## 必读

- `goal-pipeline/scripts/goal-metrics-calibrate.sh`
- `goal-pipeline/references/lifecycle.md`

## goal_patches

1. **quality-report**：跑 `goal-metrics-calibrate.sh` 写入 evidence
2. **ready_for_production**：verify.sh 全链通过 + handoff/complete.json
3. **人工提交**：提示用户自行 commit/push/MR

## guazi adapter（可选）

`pipeline_track=compatibility|guazi` 时可对照上游 `guazi-flow-complete/SKILL.md` 作为附录。

## Stage Exit

When `resolve_postmerge_policy` → `required` and `evidence/postmerge.md` is not `pass`, run **postmerge** before complete (`goal-stage-driver` `next_stage=postmerge`).

```bash
# optional: confirm policy
python3 goal-pipeline/scripts/resolve_postmerge_policy.py --index <task>/index.md --state-file <state> --handoff-dir <handoff>
gate-goal-stage.sh --stage complete --pre
# complete 收口
bash goal-metrics-calibrate.sh --task-dir <task> --state-file <state>
gate-goal-stage.sh --stage complete --post
gate-goal-stage.sh --assert-complete
```

## NEVER

- NEVER 自动 git push 或创建 MR
- NEVER 在 verify 未通过时设 status=complete
