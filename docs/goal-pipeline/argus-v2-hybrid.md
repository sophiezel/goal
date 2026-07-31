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
   - **Lite / XS**: skip step 2 unless `GOAL_ARGUS_SKILL_REQUIRED=1`.  
   - Agent MUST load **fe-argus** skill, INDEX on-demand → Scenario Q, merge into manifest.  
   - Merge: dedupe by `scenario.id`; on conflict **rule wins**; argus-only rows get `source: argus`.  
   - Use `argus_enrich_plan.merge_scenario_lists()` or equivalent hand-edit preserving schema v2.  
   - fe-argus failure → set `argus_enrich_status: partial` + PQ warn; **do not** silent-pass plan post.

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

- [ ] Step 1 ran and manifest exists before `gate --post plan` completes.  
- [ ] If triggered, fe-argus INDEX loaded and scenarios merged with `source` provenance.  
- [ ] If argus partial, document in plan PQ / index execution record; status `partial` on manifest.

## References

- `goal-pipeline/scripts/argus_enrich_plan.py`  
- `docs/wayfinder/research/phase-2-real-closure-grilling.md` §2.1 Ratified C1
