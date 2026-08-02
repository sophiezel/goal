# shared/review-kernel

Pipeline-agnostic review chain (assemble → invoke → merge) shared by goal-pipeline and guazi-flow-goal.

## REVIEW_KERNEL_HOME

Resolution order (see `goal-pipeline/scripts/resolve-review-kernel-home.sh`):

1. `REVIEW_KERNEL_HOME` env (if directory exists)
2. Repo `shared/review-kernel/` (dev checkout)
3. `~/.goal-services/review-kernel/` (installed)

## Install

```bash
bash shared/review-kernel/install.sh
# → ~/.goal-services/review-kernel/
```

## API

| Entry | Purpose |
|-------|---------|
| `$REVIEW_KERNEL_HOME/bin/run-review-chain.sh --task-dir …` | Full review chain |
| `python3 $REVIEW_KERNEL_HOME/kernel/review/cli.py run …` | CLI fast path |
| `$REVIEW_KERNEL_HOME/schemas/review-*.schema.json` | B-schema validation |

Wrappers (`goal-run-review-chain.sh`, guazi review chain) delegate here when `REVIEW_KERNEL_HOME` resolves.

## Schemas

Canonical B-schemas live in `shared/review-schema/` (`@goal/review-schema@1.x`). Install copies them into `$REVIEW_KERNEL_HOME/schemas/`.
