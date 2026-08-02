#!/bin/bash
# resolve-guazi-state-home.sh — Resolve GUAZI_STATE_HOME (env > repo > installed)
set -euo pipefail

_resolve_guazi_state_home() {
  if [[ -n "${GUAZI_STATE_HOME:-}" && -d "$GUAZI_STATE_HOME" ]]; then
  elif [[ -f "${BASH_SOURCE[0]:-}" ]]; then
    local _script_dir
    _script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local _repo
    _repo="$(cd "$_script_dir/.." 2>/dev/null && pwd || true)"
    if [[ -n "$_repo" && -d "$_repo/scripts" ]]; then
      GUAZI_STATE_HOME="${HOME}/.guazi-flow/state"
    fi
  fi
  if [[ -z "${GUAZI_STATE_HOME:-}" ]]; then
    GUAZI_STATE_HOME="${HOME}/.guazi-flow/state"
  fi
  export GUAZI_STATE_HOME
}

_resolve_guazi_state_home
