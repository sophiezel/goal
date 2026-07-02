#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$DIR/../../validate-pipeline-chain.sh"

echo "=== chain-bad-implement-pending should FAIL ==="
if "$VALIDATOR" --task-dir "$DIR/chain-bad-implement-pending" \
    --state-file "$DIR/chain-bad-implement-pending/state.json" 2>/dev/null; then
  echo "FAIL expected chain-bad to fail"; exit 1
fi
echo "OK chain-bad-implement-pending rejected"

echo "=== chain-good should PASS ==="
if "$VALIDATOR" --task-dir "$DIR/chain-good"; then
  echo "OK chain-good"
else
  echo "FAIL chain-good expected pass"; exit 1
fi
