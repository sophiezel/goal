#!/bin/bash
# guazi-install.sh — Deploy guazi-flow-goal runtime to ~/.guazi-flow/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUAZI_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$GUAZI_ROOT/.." && pwd)"
TARGET="${GUAZI_INSTALL_TARGET:-${HOME}/.guazi-flow}"
STATE_HOME="$TARGET/state"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/guazi-install-lib.sh"
_guazi_deploy_runtime "$REPO_ROOT" "$STATE_HOME" "$SCRIPT_DIR"

# review-kernel (shared service)
RK_INSTALL="$REPO_ROOT/shared/review-kernel/install.sh"
if [[ -x "$RK_INSTALL" ]]; then
  bash "$RK_INSTALL"
fi

echo "guazi-flow installed to $TARGET"
echo "export GUAZI_STATE_HOME=$STATE_HOME"
echo "export GUAZI_HOME=$TARGET"
echo "gate: $STATE_HOME/scripts/guazi-gate-stage.sh"
echo "advance: $STATE_HOME/scripts/guazi-advance-stage.sh"
