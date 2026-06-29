# Review Packet Prompt Template

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

## Output JSON schema

```json
{
  "result": "pass|not_pass",
  "issues_goal": [
    {"id": "G01", "severity": "critical|high|medium|low", "summary": "...", "root_cause": "plan_gap|implement_error|spec_ambiguity", "evidence": "..."}
  ],
  "root_cause_summary": {"plan_gap": 0, "implement_error": 0, "spec_ambiguity": 0}
}
```

Write output to `evidence/review-goal.json`, then run `merge-review-issues.sh`.
