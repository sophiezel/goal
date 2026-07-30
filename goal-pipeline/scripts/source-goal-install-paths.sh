#!/bin/bash
# source-goal-install-paths.sh — Canonical install/runtime paths (source from bash entrypoints).
# Respects GOAL_HOME, GOAL_PIPELINE_REPO, GOAL_STATE_HOME when already set.

_goal_install_paths() {
  if [[ -z "${GOAL_HOME:-}" ]]; then
    GOAL_HOME="${HOME}/.goal-pipeline"
  fi
  if [[ -z "${GOAL_PIPELINE_REPO:-}" ]]; then
    GOAL_PIPELINE_REPO="${GOAL_HOME}/repository"
  fi
  if [[ -z "${GOAL_STATE_HOME:-}" ]]; then
    GOAL_STATE_HOME="${GOAL_HOME}/state"
  fi
  export GOAL_HOME GOAL_PIPELINE_REPO GOAL_STATE_HOME
}
