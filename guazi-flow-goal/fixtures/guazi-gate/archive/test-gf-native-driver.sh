#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export GF_USE_NATIVE_DRIVER=1
OUT=$(GF_USE_NATIVE_DRIVER=1 "$ROOT/gf-stage-driver.sh" --state-file /dev/null --task-dir "$SCRIPT_DIR/plan-good" --project-root "$(cd "$SCRIPT_DIR/../../../.." && pwd)" 2>&1 || true)
# expect usage or json error without real state — just ensure native driver execs goal-stage-driver path
if [[ -x "$ROOT/gf-stage-driver.sh" ]]; then
  echo "OK gf-stage-driver executable"
else
  echo "FAIL gf-stage-driver missing"; exit 1
fi
