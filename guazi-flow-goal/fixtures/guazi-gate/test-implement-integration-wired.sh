#!/bin/bash
# test-implement-integration-wired.sh — implement post wires integration manifest check
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPL="${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts/gate-lib/implement.sh"
grep -q 'integration-contract-check.sh' "$IMPL" || { echo "FAIL implement.sh missing integration-contract-check"; exit 1; }
grep -q 'integration-barrier.json' "$IMPL" || { echo "FAIL implement.sh missing integration-barrier evidence"; exit 1; }
echo "OK implement integration barrier wired"
