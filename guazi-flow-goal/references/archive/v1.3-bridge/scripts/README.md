# v1.3 bridge scripts (archived)

Guazi v1.4 no longer ships or invokes these goal-pipeline bridge entrypoints:

- `goal-pipeline-stop-hook.sh`
- `goal-pipeline-session-start-hook.sh`
- `goal-stage-driver.sh`
- `goal-pipeline-doctor.sh`
- `deploy-skills.sh`

Canonical copies remain in `goal-pipeline/scripts/` for the goal pipeline. Guazi fixtures that still need kernel/driver behavior skip when `goal-pipeline-kernel.sh` is absent from the guazi install bundle.
