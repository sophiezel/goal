#!/bin/bash
# CI entry: all gate + observability fixture tests
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$DIR/run-gate-tests.sh"
"$DIR/test-review-gf-count.sh"
VALIDATOR="$DIR/../../validate-pipeline-chain.sh"
echo "=== chain-good validate-pipeline-chain ==="
if "$VALIDATOR" --task-dir "$DIR/chain-good"; then
  echo "OK chain-good"
else
  echo "FAIL chain-good expected pass"; exit 1
fi
echo "All gate + observability tests passed"
