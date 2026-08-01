#!/usr/bin/env bash
# v1.2 Part L: review kernel B JSON schemas + fixture samples (normative)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="$(cd "$DIR/../../../kernel/review" && pwd)/b_schema_cli.py"
FIXTURES_ROOT="$(cd "$DIR/.." && pwd)"

echo "=== review kernel B schema — fixture artifacts under scripts/fixtures ==="
python3 "$CLI" validate-fixtures --fixtures-root "$FIXTURES_ROOT"
echo "OK review kernel B schemas"
