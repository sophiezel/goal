# Handoff path resolution (SSOT)

Single narrative for **where** `handoff/*.json` lives and **how** gates resolve it. Canonical implementation: `goal-pipeline/scripts/handoff_path_resolver.py` (wraps `resolve-artifact-paths.py`).

Related: [artifact-tier-policy.md](../../guazi-flow-goal/references/artifact-tier-policy.md), [stage-handoff-contract.md](../../guazi-flow-goal/references/stage-handoff-contract.md), [resolve-artifact-paths.py](../scripts/resolve-artifact-paths.py).

## Layouts

| Mode | Handoff root | Evidence (Tier-R) | Repo task dir |
|------|----------------|-------------------|---------------|
| **split** (default for `docs/guazi-flow/*`) | `$RUNTIME_ROOT/handoff` under goal-state | `$RUNTIME_ROOT/evidence` | `index.md` + Tier-G `evidence/` only |
| **repo_full** (legacy) | `<task_dir>/handoff` | `<task_dir>/evidence` | handoff + evidence in repo |

`RUNTIME_ROOT` defaults to `~/.goal-pipeline/state/projects/<project_id>/<branch>/<task>/artifacts` when `state.json` is discovered.

## Resolution order (all consumers)

1. **`GOAL_HANDOFF_DIR`** or **`HANDOFF_DIR`** — explicit override; `gate-guazi-flow-stage.sh` / `implement.sh` export `GOAL_HANDOFF_DIR=$HANDOFF_DIR` after `resolve-artifact-paths`.
2. **`resolve-artifact-paths.py`** — uses `GOAL_STATE_FILE` (or branch-scoped discovery), `artifact_layout.mode`, `GOAL_ARTIFACT_MODE`.
3. **`<task_dir>/handoff`** — `repo_full` fallback.

Python entry points should call `handoff_path_resolver.resolve_handoff_dir()` / `resolve_plan_json_path()` rather than joining `task_dir/handoff` directly.

## Environment variables

| Variable | Role |
|----------|------|
| `GOAL_HANDOFF_DIR` | Tier-R handoff directory (split) |
| `HANDOFF_DIR` | Alias accepted by resolver |
| `GOAL_EVIDENCE_DIR` | Tier-R evidence (AM ratchet, UVO output) |
| `GOAL_STATE_FILE` | Canonical `state.json` for path resolver |
| `GOAL_REPO_ROOT` / `--project-root` | Git project root for `project_id` (when equal to `task_dir`, resolver uses `git rev-parse` root) |
| `GOAL_STATE_HOME` | Goal state root (default `~/.goal-pipeline/state`) |
| `GOAL_ARTIFACT_MODE` | Force `split` or `repo_full` |

## Consumers (implement post + complete)

| Script | Handoff usage |
|--------|----------------|
| `contract-conformance-check.py` (IQ-10) | `resolve_plan_json_path` via `verification_oracle_core` |
| `acceptance-matrix-ratchet.py` | plan load + optional write_set prune |
| `ux_scan_v1.py` | `write_set` from `plan.json` |
| `quality_plane_check.py` | `matrix_satisfaction`, Argus L10 manifest |
| `argus_enrich_plan.py` | plan post manifest |
| `verification_oracle_core.py` | plan handoff for UVO |

Shell gates should `eval "$(resolve-artifact-paths.py --format shell)"` and export `GOAL_HANDOFF_DIR` before invoking Python post-gates.

## Auditing split handoff

Use [cross-plane-handoff-audit-run-log.md](../../wayfinder/research/templates/cross-plane-handoff-audit-run-log.md) when verifying a task after `artifact_layout.migrated_at` or Tier-R-only `plan.json`.

Fixture: `goal-pipeline/scripts/fixtures/guazi-flow-gate/test-split-handoff-ssot.sh`.
