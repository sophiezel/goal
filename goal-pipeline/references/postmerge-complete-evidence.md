# Postmerge vs complete evidence checklist

Machine checks: `resolve_postmerge_policy.py`, `quality_plane_check.py --mode complete`, `goal-advance-stage.sh` (routing).

## Policy

| Signal | Effect |
|--------|--------|
| `resolved_rule_context.postmerge_policy = required` (any unit) | MUST have `evidence/postmerge.md` with `result: pass` before complete |
| `optional` (default) | No postmerge gate; manual postmerge allowed (`manual_postmerge` note per guazi-flow-postmerge) |
| `GOAL_POSTMERGE_POLICY=required` | Test / CI override |

## Sample task evidence

| Artifact | Tier | postmerge stage | complete stage |
|----------|------|-----------------|----------------|
| `index.md` (`current_stage`) | G | may be `postmerge` | `complete` |
| `evidence/review.md` (`result: pass`, `review_subject_hash`) | G | **input** (fresh) | **input** (still fresh) |
| `evidence/postmerge.md` (`stage: postmerge`, `result: pass`, `review_subject_hash`) | G | **output** | **required** when policy required |
| `handoff/review.json` | R | after review gate | pre complete |
| `handoff/complete.json` | R | — | after complete gate |
| `handoff/delivery-quality.json` | R | — | complete `--post` |
| `evidence/verification-oracle.json` | R | — | UVO check at complete |
| `evidence/contract-conformance.json` | R | — | IQ-10 at complete |
| `quality_plane_check` JSON | — | — | **mandatory** at complete |

Postmerge does **not** replace review; `guazi-flow-complete` still reads `evidence/review.md`.

## failure_code

| Code | When |
|------|------|
| `postmerge_required` | Policy `required` and postmerge evidence missing, not `pass`, or `review_subject_hash` mismatch vs `review.md` |

W1: counted via `quality_plane_check` error at complete (blocks silent pass).  
W2: use MR / delivery checklist for Jira sync; not `matrix_rows_unsatisfied`.

## Related

- [`guazi-flow-integration.md`](../../guazi-flow-goal/references/guazi-flow-integration.md) — stage driver path
- [`stage-handoff-contract.md`](../../guazi-flow-goal/references/stage-handoff-contract.md) — handoff tiers
- guazi-flow-core `delivery-policy.md` — Git gate / target-branch read-only guard
