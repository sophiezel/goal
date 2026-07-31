# fe-argus skill (optional dependency)

C1 plan post **step 2** (conditional fe-argus Scenario Q merge) is orchestrated by shell policy and Agent work orders. The **fe-argus** Cursor/agent skill is **recommended**, not a hard prerequisite to start or initialize the goal pipeline.

## When it matters

When C1 triggers (see [argus-v2-hybrid.md](../../docs/goal-pipeline/argus-v2-hybrid.md)), the Agent should load the **fe-argus** skill, run INDEX on-demand for Scenario Q, and merge into `handoff/argus-scenario-manifest.json`. Leaving plan still requires `argus_enrich_status` of `merged` or `partial` when step 2 is triggered — not `rule_only`.

If the skill is not installed locally, the work order includes an install hint; pipeline init and shell step 1 are **not** blocked.

## Install (recommended)

One-liner (installs to `~/.agents/skills/fe-argus` by default; override with `FE_ARGUS_DIR`):

```bash
curl -fsSL https://raw.githubusercontent.com/sophiezel/fe-argus/main/install.sh | bash
```

Alternatively: clone [sophiezel/fe-argus](https://github.com/sophiezel/fe-argus) and run `bash install.sh` from the repo root.

## Discovery (policy / doctor)

`argus_plan_post_policy.fe_argus_skill_discover()` treats the skill as present when either:

- `FE_ARGUS_DIR` points at a directory containing `SKILL.md`, or
- `~/.agents/skills/fe-argus/SKILL.md` exists.

No user-specific paths are required in task repos or CI.

## Skill name

Load as **`fe-argus`** (`fe-argus/SKILL.md`).

## Related

- [argus-v2-hybrid.md](../../docs/goal-pipeline/argus-v2-hybrid.md) — C1 two-step plan post
- [argus-enrich-plan-hook.md](./argus-enrich-plan-hook.md) — shell hook + Agent step 2
- `goal-pipeline/scripts/argus_plan_post_policy.py` — triggers, WO JSON, advance gate
