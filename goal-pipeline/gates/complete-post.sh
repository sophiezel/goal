#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Deterministic gate: complete post — GATE BLOCK on failure (exit 1)
exec "$ROOT/scripts/verify.sh" "$@"
