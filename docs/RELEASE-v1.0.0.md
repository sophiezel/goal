# goal v1.0.0

First SemVer release: unified `GOAL_HOME` (`~/.goal-pipeline/{repository,state}`), dual-pipeline kernel, and **install channels** (stable / latest / pinned).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/main/install.sh | bash -s -- --channel stable
```

Pinned to this release:

```bash
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/refs/tags/v1.0.0/install.sh | bash -s -- --ref v1.0.0
```

## Breaking changes (vs informal pre-release installs)

- Install layout is only `~/.goal-pipeline/repository` and `~/.goal-pipeline/state`. No automatic migration from `~/.goal-pipeline-repo`, `~/.goal-state`, or `~/.guazi-flow-goal`.
- Default install track is **stable** (latest non-prerelease SemVer tag), not rolling `main`.

## Upgrade from legacy paths

1. Move or clone git install tree to `~/.goal-pipeline/repository`.
2. Move runtime state to `~/.goal-pipeline/state`.
3. Run `bash install.sh --channel stable` or `goal-install.sh --update`.

## Channels

See [goal-pipeline/references/release-channel.md](goal-pipeline/references/release-channel.md).
