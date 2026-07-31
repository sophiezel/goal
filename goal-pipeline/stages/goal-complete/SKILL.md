---
name: goal-complete
description: 进化轨 complete 阶段。Fork 自 guazi-flow-complete，产出 ready_for_production 候选与质量报告。
---

# goal-complete

Fork-and-Own 自 `guazi-flow-complete`。`complete` = 本地候选就绪，**不**自动 commit/push/MR。

## 必读

- 上游 `guazi-flow-complete/SKILL.md`
- `goal-pipeline/scripts/goal-metrics-calibrate.sh`

## goal_patches

1. **quality-report**：跑 `goal-metrics-calibrate.sh` 写入 evidence
2. **ready_for_production**：verify.sh 全链通过 + handoff/complete.json
3. **人工提交**：提示用户自行 commit/push/MR

## Stage Exit

When `resolve_postmerge_policy` → `required` and `evidence/postmerge.md` is not `pass`, run **postmerge** before complete (`goal-stage-driver` `next_stage=postmerge`).

```bash
# optional: confirm policy
python3 goal-pipeline/scripts/resolve_postmerge_policy.py --index <task>/index.md --state-file <state> --handoff-dir <handoff>
gate-guazi-flow-stage.sh --stage complete --pre
# guazi-flow-complete 等价收口
bash goal-metrics-calibrate.sh --task-dir <task> --state-file <state>
gate-guazi-flow-stage.sh --stage complete --post
gate-guazi-flow-stage.sh --assert-complete
```

## NEVER

- NEVER 自动 git push 或创建 MR
- NEVER 在 verify 未通过时设 status=complete
