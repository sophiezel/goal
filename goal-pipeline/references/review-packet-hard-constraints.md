# Review packet hard constraints (PKT)

**Scope:** Generic goal-pipeline review chain — not tied to any business repository.

## Mandatory preflight (PKT-01–04)

`review_packet_preflight.py` runs **before** any L2 LLM invocation:

| ID | Rule | On fail |
| --- | --- | --- |
| PKT-01 | Packet diff must include at least one `src/**` path | Hard stop — no L2 spend |
| PKT-02 | Diff volume sanity (tiny diff without ref branch) | Hard stop |
| PKT-03 | `verification-oracle.json` overall must be `pass` | Hard stop — implement quality debt |
| PKT-04 | Packet integrity / required fields | Hard stop |

**Call sites (must not skip):**

- `assemble-review-packet.sh` (end of assemble)
- `gate-lib/review.sh` (`--pre`)
- `goal-run-review-chain.sh` (`assert_review_packet_preflight` after assemble)

## Packet truncation policy

- Default max diff bytes: assemble `--max-diff-bytes` (80_000)
- Scoped retry shrink: orchestrator ~25_000 bytes
- Truncation is a **leakage risk** — do not disable preflight to “go faster”

## UVO + IQ-10 before review

Review `--pre` must not run when:

- UVO evidence missing/stale (`verification-oracle.sh --check-freshness`)
- `contract-conformance.json` exists and `passed` is not true (IQ-10)

UVO `pass` with IQ-10 `fail` is **quality-plane incomplete** — fix at implement post, not review.
