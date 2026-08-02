#!/bin/bash
# resolve-review-kernel-home.sh — Resolve REVIEW_KERNEL_HOME (env > repo > installed)
set -euo pipefail

_resolve_review_kernel_home() {
  if [[ -n "${REVIEW_KERNEL_HOME:-}" && -d "$REVIEW_KERNEL_HOME" ]]; then
    :
  elif [[ -f "${BASH_SOURCE[0]:-}" ]]; then
    local _script_dir
    _script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local _repo_kernel
    _repo_kernel="$(cd "$_script_dir/../../shared/review-kernel" 2>/dev/null && pwd || true)"
    if [[ -n "$_repo_kernel" && -d "$_repo_kernel" ]]; then
      REVIEW_KERNEL_HOME="$_repo_kernel"
    fi
  fi
  if [[ -z "${REVIEW_KERNEL_HOME:-}" ]]; then
    REVIEW_KERNEL_HOME="${HOME}/.goal-services/review-kernel"
  fi
  export REVIEW_KERNEL_HOME
}

_resolve_review_kernel_home
