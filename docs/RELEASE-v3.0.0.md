# goal v3.0.0

First release with unified `GOAL_HOME` (`~/.goal-pipeline/{repository,state}`) and **install channels** (stable / latest / pinned).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/main/install.sh | bash -s -- --channel stable
```

After this tag exists on GitHub:

```bash
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/refs/tags/v3.0.0/install.sh | bash -s -- --ref v3.0.0
```

## Breaking changes

- Install layout is only `~/.goal-pipeline/repository` and `~/.goal-pipeline/state`. No automatic migration from `~/.goal-pipeline-repo`, `~/.goal-state`, or `~/.guazi-flow-goal`.
- Default install track is **stable** (latest non-prerelease SemVer tag), not `main`.

## Upgrade from pre-3.0

1. Move or clone git install tree to `~/.goal-pipeline/repository`.
2. Move runtime state to `~/.goal-pipeline/state`.
3. Run `bash install.sh --channel stable` or `goal-install.sh --update`.

## Channels

See [goal-pipeline/references/release-channel.md](goal-pipeline/references/release-channel.md).
