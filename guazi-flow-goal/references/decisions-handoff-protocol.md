# decisions.json handoff protocol

Phase 1 or **grill-with-docs** MUST write `handoff/decisions.json` when integration or UI loading rules are frozen.

## Path

`docs/guazi-flow/<task>/handoff/decisions.json` (or runtime task dir equivalent).

## Index mirror

Add `## 冻结决策` with `decisions_hash: <sha16>` matching canonical JSON hash (see `contract_parser.decisions_file_hash`).

## Schema

[`goal-pipeline/references/guazi-flow-artifact-schema/decisions.schema.json`](../../goal-pipeline/references/guazi-flow-artifact-schema/decisions.schema.json)

## Gate

PQ-12 blocks when decisions file exists but index section or hash is missing.
