# Pipeline profiles (v1.2 Part J)

| Profile | File | Notes |
|---------|------|-------|
| `default` | [default/pipeline.profile.json](default/pipeline.profile.json) | Five stages; equivalent to optimization-spec v1.1 **F.2** |

Resolve at runtime:

```bash
goal-pipeline/scripts/resolve_stage_graph.py --profile default --action validate-default-f2
```

`handoff/plan.json` may set `pipeline_profile` and optional `stage_graph[]` override (`schemas/plan.schema.json`).
