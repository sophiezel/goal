# goal v1.0.2

Patch release: review channel path SSOT and Agent subprocess env bootstrap.

## Fixes

- **`goal_state_paths.py`**: canonical `GOAL_HOME` / `GOAL_STATE_HOME` / `config.json` resolution (replaces legacy `~/.goal-state` defaults in `detect-review-channels`).
- **`goal-env-bootstrap.sh`**: sourced by gate, `goal-run-review-chain`, and `run-independent-review` so review scripts see the same state dir as doctor.
- **`resolve-artifact-paths`**: persists `runtime_env` snapshot on `state.json` during `--ensure-state`.
- **Doctor**: splits `review_channel_configured` vs `review_channel_reachable`; runs detect with explicit `GOAL_STATE_HOME`.
- **Review gate post**: clearer failures for `review_channel_unconfigured` / `review_provider_downgrade_blocked`.

## Update

```bash
bash ~/.goal-pipeline/state/scripts/goal-install.sh --update
# or
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/main/install.sh | bash -s -- --update --channel stable
```

Stable channel resolves to the latest non-prerelease tag (this release: **v1.0.2**).
