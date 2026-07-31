# UX auto-fix C1 (P1-9) — skill WO + gate audit

**Ratified:** [phase-2-real-closure-grilling.md](../../docs/wayfinder/research/phase-2-real-closure-grilling.md) §2.4  
**Gate:** `goal-pipeline/scripts/ux-auto-fix-audit.py` on `gate-lib/implement.sh` **post**  
**Spec cross-ref:** [optimization-spec-outline-v1.md](../../docs/wayfinder/research/optimization-spec-outline-v1.md) Part B / Part E P1-9

## Execution (skill-only)

D2/D5 UX fixes **MUST** be applied only inside **`guazi-flow-implement`** (or review 回流 work orders). Goal **does not** ship codemods or gate-side auto-patch.

| Track | Agent obligation |
|-------|------------------|
| **D2** | `loading` / `disabled` binding on interactive controls when UX scan or matrix flags UX-D2 |
| **D5** | `aria-label` / `aria-labelledby` when UX-D5 or a11y gap is in scope |

When `evidence/ux-scan.json` (or plan L10 manifest) lists D2/D5 findings in `write_set`, implement **MUST** attempt a minimal in-scope fix before handoff. Scope外（routes、services、新页）**禁止** auto-fix.

## Audit (implement post)

After `guazi-flow-implement`, `gate --post implement` runs:

```bash
python3 ux-auto-fix-audit.py \
  --repo-root "$GIT_ROOT" \
  --handoff-dir "$HANDOFF_DIR" \
  --evidence "$GOAL_EVIDENCE_DIR/ux-autofix.json" \
  [--strict]   # M/L/XL task_tier (S+)
```

| Check | Violation id | strict | XS/S |
|-------|----------------|--------|------|
| `git diff` paths ⊆ `handoff/plan.json` write_set | `AUTOFIX-WS` | blocker → `write_set_violation` | warn |
| No `App.tsx` / `pages/index` / `services` / `routes` paths | `AUTOFIX-ROUTE` | blocker | warn |
| Added lines ⊆ D2/D5 heuristics only | `AUTOFIX-PATTERN` | blocker | warn |

S+ (`task_tier` M/L/XL): audit failure **blocks** implement post (`AUTOFIX-01`, `root_cause: write_set_violation`).  
XS/S: violations are **warn**; gate continues; evidence still written when git root present.

## Evidence paths

| Artifact | When |
|----------|------|
| `evidence/ux-scan.json` | implement post UX scan (warn-only discovery) |
| `evidence/ux-autofix.json` | implement post auto-fix audit (always when script + git root) |

`goal-implement` fork: see `goal-pipeline/stages/goal-implement/SKILL.md` § goal_patches.
