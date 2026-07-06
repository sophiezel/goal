#!/bin/bash
# inject-docs-gitignore.sh — Append goal Tier-R gitignore rules to docs/guazi-flow/.gitignore
# Usage: inject-docs-gitignore.sh --project-root <path> [--mode split|repo_full]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../templates/docs-guazi-flow.gitignore"
GOAL_REPO="${GOAL_PIPELINE_REPO:-$HOME/.goal-pipeline-repo}"
ALT_TEMPLATE="$GOAL_REPO/guazi-flow-goal/templates/docs-guazi-flow.gitignore"
PROJECT_ROOT=""
MODE="${GOAL_ARTIFACT_MODE:-split}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$PROJECT_ROOT" ]] || PROJECT_ROOT="$(pwd)"
[[ "$PROJECT_ROOT" != /* ]] && PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

if [[ "$MODE" == "repo_full" ]]; then
  echo "inject-docs-gitignore: skipped (repo_full mode)"
  exit 0
fi

[[ -f "$TEMPLATE" ]] || TEMPLATE="$ALT_TEMPLATE"
if [[ ! -f "$TEMPLATE" ]]; then
  TEMPLATE="$(mktemp)"
  cat > "$TEMPLATE" << 'EOF'
# goal-pipeline Tier-R runtime (split mode — also under ~/.goal-state/projects/.../artifacts/)
handoff/
evidence/review-goal.json
evidence/review-gf.json
evidence/review-run.json
evidence/review-fix-input.json
evidence/review-transcript.md
evidence/*-gate-fix-input.json
evidence/runtime-smoke.md
EOF
fi

TARGET="$PROJECT_ROOT/docs/guazi-flow/.gitignore"
MARKER="# goal-pipeline Tier-R (auto-injected)"

mkdir -p "$(dirname "$TARGET")"
if [[ -f "$TARGET" ]] && grep -qF "$MARKER" "$TARGET" 2>/dev/null; then
  echo "inject-docs-gitignore: already present in $TARGET"
  exit 0
fi

{
  echo ""
  echo "$MARKER"
  cat "$TEMPLATE"
} >> "$TARGET"

echo "inject-docs-gitignore: appended to $TARGET"
