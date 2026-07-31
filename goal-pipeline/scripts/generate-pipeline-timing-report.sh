#!/usr/bin/env bash
# generate-pipeline-timing-report.sh — timing dashboard Markdown v0 / HTML v1 (Wayfinder #7 / #9)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/render-pipeline-timing-report.py" "$@"
