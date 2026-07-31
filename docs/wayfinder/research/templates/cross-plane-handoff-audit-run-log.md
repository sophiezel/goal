# Cross-plane handoff audit — run log template

Copy this file per task/run (do not commit host-specific paths into goal scripts).

## Metadata

| Field | Value |
|-------|--------|
| Date (UTC) | |
| Goal commit | |
| Host repo / branch | |
| Task dir (Tier-G) | |
| `GOAL_STATE_FILE` | |
| `artifact_layout.mode` | split / repo_full |

## Resolved paths (must match)

```bash
python3 goal-pipeline/scripts/resolve-artifact-paths.py \
  --task-dir "<TASK_DIR>" --project-root "<REPO_ROOT>" \
  --state-file "<STATE_FILE>" --format json
```

| Key | Expected | Actual |
|-----|----------|--------|
| `handoff_dir` | | |
| `goal_evidence_dir` | | |
| `plan.json` exists | yes/no | |

## Consumer spot-checks (no `GOAL_HANDOFF_DIR` unless testing override)

```bash
python3 -c "
from goal-pipeline.scripts.handoff_path_resolver import resolve_plan_json_path
import os
p = resolve_plan_json_path('<TASK_DIR>', state_file='<STATE_FILE>', project_root='<REPO_ROOT>')
print('plan', p, 'exists', os.path.isfile(p))
"
```

| Consumer | Command | pass? |
|----------|---------|-------|
| IQ-10 | `contract-conformance-check.py --task-dir … --repo-root …` | |
| AM ratchet | `acceptance-matrix-ratchet.py --task-dir … --evidence-dir …` | |
| UX scan | `ux_scan_v1.py --task-dir … --state-file …` | |
| Quality plane | `quality_plane_check.py --task-dir … --state-file …` | |

## Notes

- If repo `task_dir/handoff/` is empty but Tier-R has `plan.json`, **split SSOT is healthy** after #14.
- Escalate if `four_planes_doctor` handoff tier checks fail in CI — see [four-planes-handoff-tier.md](../four-planes-handoff-tier.md) (landed #17).
