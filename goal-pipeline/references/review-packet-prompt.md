# Review Packet Prompt Template

> **Deprecated**: 独立审核现由 `run-independent-review.sh` + `references/unified-review-prompt.md` 驱动，产出 `review-unified.json`。本模板仅作 packet 字段说明保留。

Use this when invoking goal-pipeline Step 2 independent review.

## Input

Provide ONLY the JSON from `handoff/review-packet.json`. Do NOT include executor reasoning or chat history.

## Instructions

1. Compare `contract` (goal, scope, design, acceptance matrix, pseudocode summary) against `diff`.
2. Check each item in `verification_checklist` for evidence in the diff.
3. Do NOT duplicate findings already listed in `issues_gf` — extend or disagree with justification only.
4. Respect `constraints.allowed_files` — flag any diff outside scope as CRITICAL.
5. If `deterministic_checks.pass` is false, prioritize those failures.
6. Consider `smoke_diagnostic.classification` when attributing runtime failures.

## Output

Run `run-independent-review.sh --mode unified` (or `goal` when no Guazi Flow rubric). Do **not** hand-write review JSON. After review, run `merge-review-issues.sh --unified-json evidence/review-unified.json`.

Unified output schema: `goal-pipeline/schemas/review-unified.schema.json`.
