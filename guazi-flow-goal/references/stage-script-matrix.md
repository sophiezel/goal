# Stage × Script × Artifact Matrix

| Stage | Required scripts | Required artifacts | Gate |
|-------|------------------|-------------------|------|
| plan | gate --pre/post | index.md, handoff/plan.json | plan |
| implement | gate --pre/post | handoff/implement.json | implement |
| quality | runtime-smoke.sh, quality-gate.sh, gate --post | evidence/runtime-smoke.md, handoff/quality.json | quality |
| review | assemble-review-packet, run-independent-review (unified), merge-review-issues, gate --pre/post | review-packet.json, review-run.json, review-unified.json, **review-fix-input.json**, review.md | review |
| complete | verify.sh, gate --post | handoff/complete.json | complete |

**执行 Agent 修复子循环 MUST 只读** `evidence/review-fix-input.json`（`action` + `issues` + `next_steps`）。禁止直接解析 review-unified.json / review.md 做分流。
