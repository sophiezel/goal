#!/bin/bash
# CI entry: all gate + observability fixture tests
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$DIR/test-plan-quality-gate.sh"
"$DIR/test-verification-oracle.sh"
"$DIR/test-review-packet-preflight.sh"
"$DIR/test-code-subject-hash.sh"
"$DIR/run-gate-tests.sh"
"$DIR/test-review-gf-count.sh"
"$DIR/test-validate-chain.sh"
echo "All gate + observability tests passed"
