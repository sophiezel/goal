# ReviewPacket Schema

Assembled by `assemble-review-packet.sh` for goal-pipeline independent review (Step 2).

## Fields

| Field | Type | Description |
|-------|------|-------------|
| schema_version | int | Always 1 |
| task_dir | string | docs/guazi-flow/<task> |
| contract | object | Excerpt from index.md: goal, scope, design, acceptance matrix, pseudocode summary |
| diff | string | git diff limited to write_set (truncated) |
| constraints | object | Allowed files, stop conditions, AGENTS.md summary |
| verification_checklist | array | V# or Case IDs from acceptance matrix |
| deterministic_checks | object | verify-review.sh JSON output |
| issues_gf | array | Findings from guazi-flow-review (do not duplicate) |
| smoke_diagnostic | object | From evidence/runtime-smoke.md if present |
| hashes | object | candidate_diff_hash, review_subject_hash, git_head |
| truncated | object | Which fields were truncated and why |

## Prompt usage

Review prompt MUST NOT include executor reasoning chain. Only ReviewPacket JSON + review instructions.
See `goal-pipeline/references/review-packet-prompt.md`.
