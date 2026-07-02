#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Deterministic gate: plan-post — GATE BLOCK on failure (exit 1)
exec "$ROOT/scripts/gate-guazi-flow-stage.sh" "$@"
