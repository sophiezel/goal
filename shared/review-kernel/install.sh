#!/bin/bash
# install.sh — Deploy review-kernel to ~/.goal-services/review-kernel/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${REVIEW_KERNEL_INSTALL_TARGET:-${HOME}/.goal-services/review-kernel}"

mkdir -p "$TARGET"/{bin,scripts,kernel/review,schemas}

rsync -a --delete \
  "$SCRIPT_DIR/kernel/review/" "$TARGET/kernel/review/"
rsync -a --delete \
  "$SCRIPT_DIR/scripts/" "$TARGET/scripts/"

if [[ -f "$SCRIPT_DIR/bin/run-review-chain.sh" ]]; then
  install -m 0755 "$SCRIPT_DIR/bin/run-review-chain.sh" "$TARGET/bin/run-review-chain.sh"
fi

# Schemas: prefer sibling review-schema package, else bundled copy
SCHEMA_SRC="$(cd "$SCRIPT_DIR/../review-schema" 2>/dev/null && pwd || echo "")"
if [[ -n "$SCHEMA_SRC" && -d "$SCHEMA_SRC" ]]; then
  rsync -a "$SCHEMA_SRC/"*.schema.json "$TARGET/schemas/" 2>/dev/null || true
fi

echo "review-kernel installed to $TARGET"
echo "export REVIEW_KERNEL_HOME=$TARGET"
