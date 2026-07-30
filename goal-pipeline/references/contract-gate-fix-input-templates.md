# Contract / complete gate fix-input templates

Use with `evidence/*-gate-fix-input.json` (schema: [`stage-gate-fix-input.schema.json`](guazi-flow-artifact-schema/stage-gate-fix-input.schema.json)).

## Plan — PQ-10 API mapping self-consistency

```json
{
  "schema_version": 1,
  "stage": "plan",
  "action": "fix_and_rerun",
  "subject_hash": "<index_contract_hash>",
  "gate_script": "plan-quality-gate.py",
  "issues": [
    {
      "id": "PQ-10",
      "severity": "blocker",
      "summary": "path /external/... has multiple request_key mentions",
      "root_cause": "plan_gap",
      "criterion_ref": "API 与工程映射 — single request_key per path"
    }
  ],
  "next_steps": [
    "Unify request_key in ## API 与工程映射 table and prose",
    "Remove contradictory CSP_* references for the same path",
    "gate-guazi-flow-stage.sh --stage plan --post"
  ]
}
```

## Implement — IQ-10 contract drift

```json
{
  "schema_version": 1,
  "stage": "implement",
  "action": "fix_and_rerun",
  "subject_hash": "<code_subject_hash>",
  "gate_script": "contract-conformance-check.py",
  "issues": [
    {
      "id": "IQ-10",
      "severity": "blocker",
      "summary": "service request_key does not match plan API table",
      "root_cause": "contract_drift",
      "criterion_ref": "index.md API 与工程映射"
    }
  ],
  "next_steps": [
    "Align createRequest({ key, uri }) with plan table row",
    "Add missing required_params from table",
    "gate-guazi-flow-stage.sh --stage implement --post"
  ]
}
```

## Complete — review not pass (no L2)

```json
{
  "schema_version": 1,
  "stage": "complete",
  "action": "blocked_user_decision",
  "subject_hash": "",
  "issues": [
    {
      "id": "COMPLETE-01",
      "severity": "blocker",
      "summary": "review handoff result not pass — cannot mark complete",
      "root_cause": "spec_ambiguity"
    }
  ],
  "next_steps": [
    "Run gate --post review until pass",
    "OR document exception: evidence/goal-review-waiver.json with reason + approver",
    "OR set GOAL_REVIEW_WAIVER=1 with written reason in evidence/"
  ]
}
```

### goal-review-waiver.json (minimal)

```json
{
  "schema_version": 1,
  "reason": "L2 review channel unavailable; human sign-off on MR #123",
  "approved_by": "user",
  "approved_at": "2026-07-30T12:00:00Z"
}
```
