# Plan post — Argus L10 manifest hook (v2 hybrid)

Plan gate `--post` invokes `argus-enrich-plan.sh` after `handoff/plan.json` is written (**step 1**, rule-only, zero LLM).

When C1 triggers (see `docs/goal-pipeline/argus-v2-hybrid.md`), the Agent work order from `goal-stage-driver` / kernel `next` requires **step 2** (manifest must reach `merged` or `partial` before advance — not `rule_only`):

**推荐安装** `fe-argus` skill when missing (`fe-argus-skill-recommendation.md`); this does **not** block pipeline init or shell step 1.

1. Load `fe-argus` skill; INDEX on-demand Scenario Q.
2. Write `handoff/fe-argus-scenarios-pending.json` with `{ "scenarios": [...] }`.
3. `python3 argus_enrich_plan.py --merge-fe-argus-file ... --merge-status merged|partial`
4. `python3 argus_plan_post_policy.py --check-plan-post` before `goal-advance-stage`.

**Lite / XS:** step 2 skipped unless `GOAL_ARGUS_SKILL_REQUIRED=1`.

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
