# Plan post — Argus L10 manifest hook (v1)

Plan gate `--post` invokes `argus-enrich-plan.sh` after `handoff/plan.json` is written.

## Inputs

- `index.md`
- `handoff/plan.json` `write_set`

## Output

- `handoff/argus-scenario-manifest.json` (SSOT for L10 rows; default `severity=soft`, `w1_status=open`)

## Manual run

```bash
goal-pipeline/scripts/argus-enrich-plan.sh \
  --task-dir docs/guazi-flow/<task> \
  --handoff-dir <tier-r-handoff-if-split>
```

v1 uses rule-based keywords only; fe-argus Scenario Q INDEX on-demand is optional upgrade path.
