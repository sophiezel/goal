#!/bin/bash
# gf-stage-driver.sh — guazi-flow-goal native orchestration (M4)
# Feature flag: GF_USE_NATIVE_DRIVER=1 (default 0 falls back to goal-stage-driver.sh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${GF_USE_NATIVE_DRIVER:-0}" != "1" ]]; then
  exec "$SCRIPT_DIR/goal-stage-driver.sh" "$@"
fi

export GOAL_PIPELINE_ID=guazi-flow-goal
export GOAL_REVIEW_RUBRIC_PROVIDER=guazi
exec "$SCRIPT_DIR/goal-stage-driver.sh" "$@"
