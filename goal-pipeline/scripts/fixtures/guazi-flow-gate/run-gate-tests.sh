#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/../../gate-guazi-flow-stage.sh"

echo "=== plan-good should PASS ==="
if "$GATE" --task-dir "$SCRIPT_DIR/plan-good" --stage plan --post --mode guazi; then
  echo "OK plan-good"
else
  echo "FAIL plan-good expected pass"; exit 1
fi

echo "=== plan-bad should FAIL ==="
if "$GATE" --task-dir "$SCRIPT_DIR/plan-bad" --stage plan --post --mode guazi; then
  echo "FAIL plan-bad expected fail"; exit 1
else
  echo "OK plan-bad rejected"
fi

echo "=== ctb-43532-simplified should FAIL ==="
if "$GATE" --task-dir "$SCRIPT_DIR/ctb-43532-simplified" --stage plan --post --mode guazi; then
  echo "FAIL ctb-43532 expected fail"; exit 1
else
  echo "OK ctb-43532-simplified rejected"
fi

echo "All gate fixture tests passed"
