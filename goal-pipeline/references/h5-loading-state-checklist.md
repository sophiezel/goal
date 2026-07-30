# H5 loading-state checklist (reference)

Non-blocking guidance for implement agents (bridge docs). Tag frozen rules in `handoff/decisions.json` → `ui.loading[]`.

| Tag | Meaning |
|-----|---------|
| `no_footer_cta_in_skeleton` | Skeleton must not show primary footer CTA |
| `section_title_spacer_only` | Section titles use spacer, not fake title text in skeleton |
| `single_column_skeleton` | No multi-column skeleton rows mimicking final layout |

When `quality_policy.tier=strict` or plan lists these tags, review should verify loading UI against checklist.
