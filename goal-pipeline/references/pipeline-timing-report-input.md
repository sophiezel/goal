# Pipeline timing report input schema

SSOT for timing fields: [`docs/wayfinder/research/pipeline-timing-dashboard-v0.md`](../../docs/wayfinder/research/pipeline-timing-dashboard-v0.md).

## Primary: `pipeline-timing.json`

Written by `record-pipeline-timing.py`; consumed by `render-pipeline-timing-report.py` (Markdown v0 / HTML v1).

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `schema_version` | int | yes | Currently `1` |
| `timezone` | string | yes | Must be `UTC` for efficiency plane checks |
| `updated_at_utc` | ISO-8601 `Z` | yes | Last recorder write |
| `stages` | object | yes | Keys: `plan`, `implement`, `quality`, `review`, `complete` (legacy `smoke` merged into quality row) |

Per-stage object:

| Field | Type | Notes |
|-------|------|-------|
| `duration_ms` | int | Wall clock for the stage (report SSOT) |
| `started_at_utc` | string | First start |
| `last_timestamp_utc` | string | Last event |
| `events` | array | `{event: start\|end\|mark, timestamp_utc, substep?, duration_ms?}` |
| `substeps` | object | Named substeps → `{duration_ms, events, last_timestamp_utc?}` |

## Optional companions (same evidence dir)

| File | Report section |
|------|----------------|
| `verification-oracle.json` | UVO table (`steps[].id`, `duration_ms`, `pass`/`ok`, `output`/`command`) |
| `review-run.json` | Review provenance (`latency_ms`, `invocation_count`, `provider`) |
| `runtime-smoke.md` | Frontmatter `duration_ms` for R5 flag only |

## Generator CLI

```bash
# Task dir (gate-aligned paths via resolve-artifact-paths)
./generate-pipeline-timing-report.sh --task-dir "$TASK_DIR" --format html --output report.html

# Fixture-friendly (direct JSON)
python3 render-pipeline-timing-report.py \
  --format html \
  --timing-json path/to/pipeline-timing.json \
  [--uvo-json ...] [--review-json ...] \
  --task-id my-task --output report.html
```

HTML v1 fixture: `scripts/fixtures/pipeline-timing-html-v1/`; gate test: `test-pipeline-timing-html-v1.sh`.
