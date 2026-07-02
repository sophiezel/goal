#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Deterministic gate: review pre — GATE BLOCK on failure (exit 1)
exec "$ROOT/scripts/verify-review.sh" "$@"
