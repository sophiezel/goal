# Stage × Script × Artifact Matrix

| Stage | Required scripts | Required artifacts | Gate |
|-------|------------------|-------------------|------|
| plan | gate --pre/post | index.md, handoff/plan.json | plan |
| implement | gate --pre/post | handoff/implement.json | implement |
| smoke | runtime-smoke.sh, gate --post | evidence/runtime-smoke.md, handoff/smoke.json | smoke |
| review | assemble-review-packet, run-independent-review (dual), merge-review-issues, gate --pre/post | review-packet.json, review-run.json, review-goal.json, review-gf.json, **review-fix-input.json**, review.md | review |
| complete | verify.sh, gate --post | handoff/complete.json | complete |

**执行 Agent 修复子循环 MUST 只读** `evidence/review-fix-input.json`（`action` + `issues` + `next_steps`）。禁止直接解析 review-goal / review-gf / review.md 做分流。
