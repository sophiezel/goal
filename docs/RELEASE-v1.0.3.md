# goal v1.0.3

Patch release: declarative contract semantic gates (PQ-10..14, IQ-10), integration manifest barrier, and RCA closeout docs/fixtures.

## Highlights

- **Plan/implement gates**: table-driven `contract-conformance-check.py` / `contract_parser.py` for PQ-10..PQ-14 (plan) and IQ-10 (implement); profile adapters keep gates free of business constants.
- **Integration barrier**: when `handoff/integration-manifest.json` exists, implement post runs `integration-contract-check.sh` and writes `evidence/integration-barrier.json`.
- **RCA closeout**: `declarative-contract-gates.md`, `rca-plan-closeout-checklist.md`, gate fixtures (`test-contract-gate.sh`, `test-plan-quality-gate.sh`, IQ-10/PQ-10 samples), and eval case `contract-semantic-gates.yaml`.

## Update

```bash
bash ~/.goal-pipeline/state/scripts/goal-install.sh --update
# or
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/main/install.sh | bash -s -- --update --channel stable
```

Stable channel resolves to the latest non-prerelease tag (this release: **v1.0.3**).
