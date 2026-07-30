# Multi-goal orchestration

When the user declares **more than one** `project_root` for a single delivery:

1. Phase 1 MUST set `state.multi_goal[]` with `{ "project_root", "guazi_flow_task", "id" }` per repo.
2. Each repo keeps its own `docs/guazi-flow/<task>/index.md` and `handoff/`.
3. Optional **federation** artifact at the workspace or primary task dir:
   - `handoff/integration-manifest.json` — lists `cross_app[]` with `path`, `query`, `scan_globs` per `project_root` id.
4. **Barrier**: after `gate --post implement` succeeds, if `handoff/integration-manifest.json` exists, `gate-lib/implement.sh` runs `integration-contract-check.sh` and writes `evidence/integration-barrier.json`.

## Fast-path

Goals with `cross_app`, external API tables, or `multi_goal` MUST NOT use interview fast-path skip for integration checklist (see `guazi-flow-goal` bridge docs).

## Engine rule

Scripts never hardcode repository names (e.g. xrk / jian-h5). All paths and routes come from manifest + per-repo index tables.
