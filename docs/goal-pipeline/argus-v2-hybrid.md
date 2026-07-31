# fe-argus v2 Hybrid (plan post)

**Ratified:** Phase-2 C1 (Wayfinder #1). Shell stays deterministic; fe-argus skill is Agent-only.

## Plan post — fixed two steps

1. **Rule manifest (required)** — `argus_enrich_plan.py` / `argus-enrich-plan.sh`  
   - Zero LLM; writes `handoff/argus-scenario-manifest.json`.  
   - Each scenario carries `source: rule`.  
   - Top-level `argus_enrich_status: rule_only` until Agent merge.  
   - **Missing manifest = plan post fail** (`gate-lib/plan.sh`).

2. **fe-argus skill (conditional)** — Agent work order only  
   - Trigger when **any**: `write_set` contains `src/pages/`, profile/tier ≥ S, or `GOAL_ARGUS_SKILL_REQUIRED=1`.  
   - **Lite / XS (HITL #13):** skip step 2 unless `GOAL_ARGUS_SKILL_REQUIRED=1`.  
   - **推荐安装** fe-argus skill（可选依赖，不阻塞 pipeline 初始化）；见 `goal-pipeline/references/fe-argus-skill-recommendation.md`。  
   - When triggered, Agent should load **fe-argus**, INDEX on-demand → Scenario Q, merge into manifest (`merged` or `partial` before leaving plan).  
   - Merge: dedupe by `scenario.id`; on conflict **rule wins**; argus-only rows get `source: argus`.  
   - Use `argus_enrich_plan.py --merge-fe-argus-file` or `merge_scenario_lists()` preserving schema v2.  
   - fe-argus failure → set `argus_enrich_status: partial` + PQ warn on `handoff/plan.json`; **do not** silent-pass plan post.

**Orchestration (implemented #8):** `goal-stage-driver` / `goal-pipeline-kernel next` inject `fe_argus_plan_post`, `skills_to_load`, and mandatory commands **after** `gate --post plan` (shell step 1). `goal-advance-stage` blocks leaving plan while `argus_fe_skill_pending`. Policy: `argus_plan_post_policy.py`.

## Manifest schema (v2)

```json
{
  "schema_version": 2,
  "argus_enrich_status": "rule_only | merged | partial",
  "scenarios": [
    { "id": "...", "severity": "soft", "source": "rule|argus", "w1_status": "open" }
  ]
}
```

## Agent checklist (no LLM in shell)

- [x] Step 1 ran and manifest exists before `gate --post plan` completes.  
- [x] If triggered, fe-argus INDEX loaded (or install per recommendation doc) and scenarios merged with `source` provenance.  
- [x] If argus partial, document in plan PQ / index execution record; status `partial` on manifest.

## References

- `goal-pipeline/scripts/argus_enrich_plan.py`  
- `goal-pipeline/scripts/argus_plan_post_policy.py`  
- `goal-pipeline/references/fe-argus-skill-recommendation.md`  
- `docs/wayfinder/research/phase-2-real-closure-grilling.md` §2.1 Ratified C1
