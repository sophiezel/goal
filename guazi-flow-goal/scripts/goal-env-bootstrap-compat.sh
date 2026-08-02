#!/bin/bash
# goal-env-bootstrap.sh (guazi runtime compat) — scripts still source goal-env-bootstrap in v1.4 bundle.

_goal_env_bootstrap_dir() {
  cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  _BOOTSTRAP_DIR="$(_goal_env_bootstrap_dir)"
  if [[ -n "${GOAL_BOOTSTRAP_STATE_FILE:-}" ]]; then
    GUAZI_BOOTSTRAP_STATE_FILE="$GOAL_BOOTSTRAP_STATE_FILE"
  fi
  # shellcheck disable=SC1091
  source "$_BOOTSTRAP_DIR/guazi-env-bootstrap.sh"
  # shellcheck disable=SC1091
  source "$_BOOTSTRAP_DIR/source-goal-install-paths.sh"
  _goal_install_paths
fi
