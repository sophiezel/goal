#!/bin/bash
# goal-run-review-chain.sh — Thin wrapper delegating to shared review-kernel when available
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/resolve-review-kernel-home.sh"

CHAIN="$REVIEW_KERNEL_HOME/scripts/run-review-chain.sh"
if [[ -x "$CHAIN" ]]; then
  export GOAL_PIPELINE_SCRIPTS="$SCRIPT_DIR"
  exec bash "$CHAIN" "$@"
fi

# Fallback: inline chain (dev without shared install)
exec bash "$SCRIPT_DIR/.goal-run-review-chain-legacy.sh" "$@"
