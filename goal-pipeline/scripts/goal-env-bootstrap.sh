#!/bin/bash
# goal-env-bootstrap.sh — Export GOAL_HOME / GOAL_STATE_HOME / GOAL_PIPELINE_REPO (source only).
# Optional: GOAL_BOOTSTRAP_STATE_FILE → apply state.json runtime_env when env unset.

_goal_env_bootstrap_dir() {
  cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  _BOOTSTRAP_DIR="$(_goal_env_bootstrap_dir)"
  # shellcheck disable=SC1091
  source "$_BOOTSTRAP_DIR/source-goal-install-paths.sh"
  _goal_install_paths

  if [[ -n "${GOAL_BOOTSTRAP_STATE_FILE:-}" && -f "${GOAL_BOOTSTRAP_STATE_FILE}" ]]; then
    eval "$(python3 "$_BOOTSTRAP_DIR/goal_state_paths.py" --apply-state-file "${GOAL_BOOTSTRAP_STATE_FILE}")"
    # shellcheck disable=SC1091
    source "$_BOOTSTRAP_DIR/source-goal-install-paths.sh"
    _goal_install_paths
  fi

  export GOAL_HOME GOAL_PIPELINE_REPO GOAL_STATE_HOME
fi
