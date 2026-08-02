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
  if [[ -z "${REVIEW_KERNEL_HOME:-}" ]]; then
    local _paths_script
    _paths_script="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/resolve-review-kernel-home.sh"
    if [[ -f "$_paths_script" ]]; then
      # shellcheck disable=SC1091
      source "$_paths_script"
    else
      REVIEW_KERNEL_HOME="${HOME}/.goal-services/review-kernel"
      export REVIEW_KERNEL_HOME
    fi
  fi
  export GOAL_HOME GOAL_PIPELINE_REPO GOAL_STATE_HOME REVIEW_KERNEL_HOME
}
