#!/bin/bash
# source-goal-install-paths.sh (guazi runtime compat) — GOAL_* aliases over guazi install paths.

_goal_install_paths() {
  local _dir _meta
  _dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
  # shellcheck disable=SC1091
  source "$_dir/source-guazi-install-paths.sh"
  _guazi_install_paths
  _meta="$_dir/../guazi-install-meta.env"
  if [[ -f "$_meta" ]]; then
    # shellcheck disable=SC1090
    source "$_meta"
  fi
  export GOAL_HOME="${GUAZI_HOME:-${HOME}/.guazi-flow}"
  export GOAL_STATE_HOME="${GUAZI_STATE_HOME:-${GOAL_HOME}/state}"
  export GOAL_PIPELINE_REPO="${GUAZI_PIPELINE_REPO:-${GOAL_PIPELINE_REPO:-${GOAL_HOME}/repository}}"
}
