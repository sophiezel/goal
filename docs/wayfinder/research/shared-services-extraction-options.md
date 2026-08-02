# Shared Services Extraction Options (#73)

**Status:** aligned with Wayfinder #70 v1.4 implementation (2026-08-03)  
**SSOT:** [two-pipeline-independence-ratification.md](./two-pipeline-independence-ratification.md) · [optimization-spec-outline-v1.4.md](./optimization-spec-outline-v1.4.md)

## What was extracted

| Package | Path | Install target |
|---------|------|----------------|
| **review-kernel** | `shared/review-kernel/` | `~/.goal-services/review-kernel/` |
| **review-schema** | `shared/review-schema/` | copied into kernel `schemas/` on install |

### review-kernel contents

- `kernel/review/*.py` — CLI, invoke, merge, loop policy, B-schema helpers
- `scripts/` — `run-review-chain.sh`, `assemble-review-packet.sh`, `run-independent-review.sh`, `merge-review-issues.sh`, channel guard, packet preflight
- `bin/run-review-chain.sh` — public entry (spec S.3)

### Resolution

`REVIEW_KERNEL_HOME` via `goal-pipeline/scripts/resolve-review-kernel-home.sh`:

1. env `REVIEW_KERNEL_HOME` (if directory exists)
2. repo `shared/review-kernel/` (dev)
3. `~/.goal-services/review-kernel/` (installed)

`goal-run-review-chain.sh` is a thin wrapper that `exec`s the shared chain when available.

## What stays in each pipeline

| Asset | goal-pipeline | guazi-flow-goal |
|-------|---------------|-----------------|
| Gate | `gate-goal-stage.sh` | `guazi-gate-stage.sh` (fork @ 9910d79 guazi mode) |
| gate-lib | goal-only | guazi fork under `scripts/gate-lib/` |
| Stage driver / kernel | goal-only | guazi install + own orchestration |
| Review wrapper SKILL | `goal-review` | `guazi-flow-review` |

## Q5 fallback

If shared kernel cannot ship on schedule: fork implementation per pipeline, **keep** `shared/review-schema/` as semver SSOT (`@goal/review-schema@1.x`). Breaking schema changes require coordinated major bump.

## Migration from 9910d79

1. `bash shared/review-kernel/install.sh`
2. goal: use `resolve-review-kernel-home.sh` / updated `source-goal-install-paths.sh`
3. guazi: `bash guazi-flow-goal/scripts/guazi-install.sh` → `~/.guazi-flow/` + review-kernel
4. Remove `gate-guazi-flow-stage.sh` references; point CI at `guazi-gate-stage.sh`

## Reject

- goal-pipeline retaining guazi compat wrappers
- guazi calling `goal-pipeline/scripts/*` at runtime
- schema major drift between implementations
