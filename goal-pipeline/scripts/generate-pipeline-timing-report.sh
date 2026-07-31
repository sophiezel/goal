#!/usr/bin/env bash
# generate-pipeline-timing-report.sh — v0 Markdown timing dashboard (Wayfinder #7)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/render-pipeline-timing-report.py" "$@"
