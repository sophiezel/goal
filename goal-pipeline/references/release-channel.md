# Release channels and tags

Install/update track is controlled by `config.json` → `install` and CLI flags on [`install.sh`](../../install.sh) / [`goal-install.sh`](../scripts/goal-install.sh).

## Channels

| Channel | Git resolution | Audience |
|---------|----------------|----------|
| **stable** (default) | Highest `vMAJOR.MINOR.PATCH` tag on `origin`, excluding `-rc`, `-beta`, `-alpha`, `-pre` | Production / daily use |
| **latest** | `origin/main` tip | Early adopters |
| **pinned** | Exact `--ref` tag or commit | Reproducibility, CI, rollback |

No long-lived `release` branch: shipping is **annotated tag + GitHub Release** on `main`.

## User commands

```bash
# Install (bootstrap installer from main; content follows channel)
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/main/install.sh | bash -s -- --channel stable
curl -fsSL .../main/install.sh | bash -s -- --channel latest
curl -fsSL .../main/install.sh | bash -s -- --ref v1.0.0

# Update / status (after install)
bash ~/.goal-pipeline/state/scripts/goal-install.sh --update
bash ~/.goal-pipeline/state/scripts/goal-install.sh --status

# Uninstall (channel-independent)
bash install.sh --uninstall
bash install.sh --uninstall --purge
```

Reproducible bootstrap (installer and tree at same tag):

```bash
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/refs/tags/v1.0.0/install.sh | bash -s -- --ref v1.0.0
```

## Maintainer release

1. Merge to `main`; ensure [`goal-pipeline/VERSION`](../VERSION) matches the release (e.g. `1.0.0`).
2. Run gate tests (`goal-pipeline/scripts/fixtures/guazi-flow-gate/run-gate-tests.sh`).
3. Create annotated tag `vX.Y.Z` on `main` and publish GitHub Release notes (breaking changes, layout under `~/.goal-pipeline/`).
4. Pre-releases (`v1.1.0-rc.1`) are installable via `--ref` only; they do not become **stable**.

## config.json

```json
"install": {
  "channel": "stable",
  "ref": "",
  "resolved_ref": "v1.0.0",
  "resolved_commit": "abc1234",
  "default_branch": "main",
  "installed_at": "2026-07-30T00:00:00Z"
}
```

`~/.goal-pipeline/state/VERSION` mirrors `goal_pipeline_version`, `install_channel`, `git_tag`, and runtime hashes for doctor drift checks.

## Contributor pre-push

`pre-push` still uses `sync-install-repo.sh --from-dev` and does **not** change `install.channel`. Point your install clone at **latest** only if you intend to test rolling `main` in `~/.goal-pipeline/repository`.
