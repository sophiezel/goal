#!/bin/bash
# CI entry: all gate + observability fixture tests
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$DIR/run-gate-tests.sh"
"$DIR/test-review-gf-count.sh"
"$DIR/test-validate-chain.sh"
echo "All gate + observability tests passed"
