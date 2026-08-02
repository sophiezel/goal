#!/bin/bash
# guazi-env-bootstrap.sh — Export GUAZI_HOME / GUAZI_STATE_HOME / REVIEW_KERNEL_HOME (source only).
# Optional: GUAZI_BOOTSTRAP_STATE_FILE → apply state.json runtime_env when env unset.

_guazi_env_bootstrap_dir() {
  cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  _BOOTSTRAP_DIR="$(_guazi_env_bootstrap_dir)"
  # shellcheck disable=SC1091
  source "$_BOOTSTRAP_DIR/source-guazi-install-paths.sh"
  _guazi_install_paths

  if [[ -n "${GUAZI_BOOTSTRAP_STATE_FILE:-}" && -f "${GUAZI_BOOTSTRAP_STATE_FILE}" ]]; then
    if [[ -f "$_BOOTSTRAP_DIR/goal_state_paths.py" ]]; then
      eval "$(python3 "$_BOOTSTRAP_DIR/goal_state_paths.py" --apply-state-file "${GUAZI_BOOTSTRAP_STATE_FILE}")"
      # shellcheck disable=SC1091
      source "$_BOOTSTRAP_DIR/source-guazi-install-paths.sh"
      _guazi_install_paths
    fi
  fi

  export GUAZI_HOME GUAZI_STATE_HOME REVIEW_KERNEL_HOME
fi
