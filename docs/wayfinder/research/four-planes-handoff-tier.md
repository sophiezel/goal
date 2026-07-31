# four_planes_doctor handoff tier regression (#17)

Parent: [Wayfinder #1](https://github.com/sophiezel/goal/issues/1). SSOT: [handoff-path-resolution.md](../../goal-pipeline/references/handoff-path-resolution.md), [pipeline-node-catalog.md](pipeline-node-catalog.md).

## Purpose

After split migration (#14), implement post-gates must resolve `plan.json` from Tier-R (`GOAL_STATE_HOME` runtime `handoff/`), not only `<task_dir>/handoff`. `four_planes_doctor` adds **live** split-layout checks so CI/Wave runs can detect resolver drift without relying on static string grep alone.

## Doctor checks

| Check | When | Meaning |
|-------|------|---------|
| `data.qg_shell_handoff_ssot` | always | `quality-gate.sh` uses `resolve-artifact-paths` + `HANDOFF_DIR` for `plan.json` |
| `data.verify_shell_handoff_ssot` | always | `verify.sh` resolves handoff via `resolve-artifact-paths` |
| `data.handoff_tier_rap_resolver` | `--state-file` + `--task-dir` (or `GOAL_RUN_FOUR_PLANES_DOCTOR=1`) | `resolve-artifact-paths` `handoff_dir` == `handoff_path_resolver.resolve_handoff_dir` |
| `data.handoff_tier_plan_json` | same | Tier-R `plan.json` exists at resolved path |
| `data.handoff_ssot_drift` | same | Split mode: no conflicting repo vs Tier-R `plan.json`; resolver not stuck on empty repo handoff |
| `data.handoff_tier_live` | `GOAL_RUN_FOUR_PLANES_DOCTOR=1` without task/state | Fail-fast misconfiguration |

Lite runs without `--state-file` skip live tier checks (default pass/fail unchanged).

## Fixture

```bash
goal-pipeline/scripts/fixtures/guazi-flow-gate/test-four-planes-handoff-tier.sh
```

Bundled in `run-all-gate-tests.sh`.

## Optional CI

```bash
export GOAL_RUN_FOUR_PLANES_DOCTOR=1
python3 goal-pipeline/scripts/four_planes_doctor.py \
  --task-dir "<TASK>" --project-root "<REPO>" --state-file "<STATE>" --format text
```

Cross-plane manual audit template: [cross-plane-handoff-audit-run-log.md](templates/cross-plane-handoff-audit-run-log.md).
