# goal Artifact Schema (SSOT)

Canonical artifact validation rules for goal-pipeline gates. **Default consumer:** goal-pipeline (`gate-goal-stage.sh`, `--mode goal`).

**Guazi adapter:** legacy path `guazi-flow-artifact-schema/` remains synced for `pipeline_track=guazi`; resolvers prefer this directory first, then fall back to `guazi-flow-artifact-schema/`.

## Files

- `plan-index-rules.json` — index.md frontmatter + required sections (full)
- `plan-index-rules-lite.json` — Index-Lite (XS/S, `plan_profile: lite`)
- `review-evidence-rules.json` — evidence/review.md frontmatter + sections
- `stage-gate-fix-input.schema.json` — fix-input contract
- `decisions.schema.json` — frozen decisions handoff
- `integration-manifest.schema.json` — integration manifest

## Consumers

| Script | Usage |
|--------|-------|
| `gate-goal-stage.sh` | `SCHEMA_DIR` → goal-artifact-schema (fallback guazi-flow-artifact-schema) |
| `resolve_plan_index_rules.py` | plan-index-rules full/lite resolution |
