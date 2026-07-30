#!/bin/bash
# gate-gf-stage.sh — thin wrapper around gate-guazi-flow-stage.sh (shared GateRuntime)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/gate-guazi-flow-stage.sh" "$@"
