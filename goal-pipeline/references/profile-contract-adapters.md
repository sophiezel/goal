# Profile contract adapters (IQ-10)

Goal engine uses **adapters** to find HTTP client bindings in `write_set` files. Adapters know **syntax only**; `request_key` and `path` values always come from the task `index.md` **API 与工程映射** table.

## Registered adapters

| profile | Detector | Extract |
|---------|----------|---------|
| `h5`, `react`, `vue` (default) | `createRequest({` block (~800 chars) | `key: '...'`, `uri: '...'` |

## Adding a stack

1. Add a row to this table with regex/AST rules.
2. Extend `extract_bindings_for_profile()` in `goal-pipeline/scripts/contract_parser.py`.
3. Add a synthetic fixture under `scripts/fixtures/guazi-flow-gate/`.

## Skip behavior

If the index has **no** `## API 与工程映射` table, `contract-conformance-check.py` exits 0 with `skipped: true`.

## Optional env registry (IQ-12, future)

When index declares `env_registry: src/config/env.js`, a separate check may verify table `request_key` symbols exist in that file. Not enabled unless the plan explicitly declares the registry path.
