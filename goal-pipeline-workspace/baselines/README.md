# Baselines (v3 §8.5 #0)

Pre-optimization baseline JSONs for the §8 fast-track. Replay with the exact commands below to reproduce.

## Files

| File | Fixture | Purpose |
|------|---------|---------|
| `xs-v3-pre.json` | `fixtures/guazi-flow-gate/plan-good` | plan-stage static replay (feature flags + review-chain score) |
| `xs-v3-pre-review.json` | `fixtures/guazi-flow-gate/chain-good` | full chain static replay (review-chain features) |

## Reproduce (pre-optimization)

```bash
bash goal-pipeline/scripts/benchmark-pipeline-replay.sh \
  --task-dir goal-pipeline/scripts/fixtures/guazi-flow-gate/plan-good \
  --output goal-pipeline-workspace/baselines/xs-v3-pre.json

bash goal-pipeline/scripts/benchmark-pipeline-replay.sh \
  --task-dir goal-pipeline/scripts/fixtures/guazi-flow-gate/chain-good \
  --output goal-pipeline-workspace/baselines/xs-v3-pre-review.json
```

## Reproduce (post-optimization, for §8.5 #4 comparison)

```bash
bash goal-pipeline/scripts/benchmark-pipeline-replay.sh \
  --task-dir goal-pipeline/scripts/fixtures/guazi-flow-gate/plan-good \
  --output goal-pipeline-workspace/baselines/xs-v3-post.json

bash goal-pipeline/scripts/benchmark-pipeline-replay.sh \
  --task-dir goal-pipeline/scripts/fixtures/guazi-flow-gate/chain-good \
  --output goal-pipeline-workspace/baselines/xs-v3-post-review.json
```

## Acceptance gate (§8.5 #4)

Post vs pre: `duration_ms` reduction ≥25% **or** plan_gate+review_chain combined ≥30%.

Note: `benchmark-pipeline-replay.sh` is a **static** replay (script feature scan, no live API). It measures which optimization features are wired, not wall-clock of a live agent run. For live wall-clock, use a real XS task end-to-end.
