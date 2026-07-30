# goal v1.0.1

Patch release for install/runtime deploy and doctor diagnostics.

## Fixes

- Deploy extensionless runtime helpers `detect-review-channels` and `detect-platform` to `~/.goal-pipeline/state/scripts/` (fixes doctor `review_channels` / missing script on fresh install).
- `install.sh`: when stop hook already exists in `~/.cursor/hooks.json`, raise `loop_limit` to at least **10** (doctor `stop_hook_loop_limit`).
- `goal-pipeline-doctor.sh`: run channel detect with `--no-probe` to avoid false timeouts during health check.

## Update

```bash
bash ~/.goal-pipeline/state/scripts/goal-install.sh --update
# or
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/main/install.sh | bash -s -- --update --channel stable
```

Stable channel resolves to the latest non-prerelease tag (this release: **v1.0.1**).
