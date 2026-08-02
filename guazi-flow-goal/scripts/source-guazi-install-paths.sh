#!/bin/bash
# source-guazi-install-paths.sh — Canonical guazi install/runtime paths (source only).

_guazi_install_paths() {
  if [[ -z "${GUAZI_HOME:-}" ]]; then
    GUAZI_HOME="${HOME}/.guazi-flow"
  fi
  if [[ -z "${GUAZI_STATE_HOME:-}" ]]; then
    GUAZI_STATE_HOME="${GUAZI_HOME}/state"
  fi
  if [[ -z "${REVIEW_KERNEL_HOME:-}" ]]; then
    local _rk
    _rk="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/resolve-review-kernel-home.sh"
    if [[ ! -f "$_rk" ]]; then
      _rk="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../../goal-pipeline/scripts" && pwd)/resolve-review-kernel-home.sh"
    fi
    if [[ -f "$_rk" ]]; then
      # shellcheck disable=SC1091
      source "$_rk"
    else
      REVIEW_KERNEL_HOME="${HOME}/.goal-services/review-kernel"
      export REVIEW_KERNEL_HOME
    fi
  fi
  export GUAZI_HOME GUAZI_STATE_HOME REVIEW_KERNEL_HOME
}
