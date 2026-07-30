#!/bin/bash
exec "${GOAL_STATE_HOME:-${GOAL_HOME:-$HOME/.goal-pipeline}/state}/scripts/goal-pipeline-stop-hook.sh"
