#!/bin/bash
# goal-install.sh — Update/status entrypoint (deployed to GOAL_STATE_HOME/scripts).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/goal-install-lib.sh"
_goal_install_lib_source_paths

UPDATE=false
STATUS=false
CHANNEL=""
REF=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update) UPDATE=true; shift ;;
    --status) STATUS=true; shift ;;
    --channel) CHANNEL="$2"; shift 2 ;;
    --ref) REF="$2"; shift 2 ;;
    -h|--help)
      cat <<'USAGE'
goal-install — manage goal-pipeline install channel and runtime

Usage: bash goal-install.sh [options]

Options:
  --update          Fetch/checkout per config (or --channel/--ref) and redeploy runtime + skills
  --status          Print install channel, repository ref, VERSION summary
  --channel NAME    stable | latest | pinned (overrides config for this run)
  --ref REF         Tag or commit (implies pinned when set)
  -h, --help        Show help

Environment: GOAL_CHANNEL, GOAL_REF, GOAL_HOME, GOAL_PIPELINE_REPO, GOAL_STATE_HOME

Examples:
  bash goal-install.sh --update
  GOAL_CHANNEL=stable bash goal-install.sh --update
  bash goal-install.sh --update --ref v3.0.0
  bash goal-install.sh --status
USAGE
      exit 0
      ;;
    *) EXTRA_ARGS+=("$1"); shift ;;
  esac
done

if [[ "$STATUS" == true ]]; then
  goal_print_install_status
  exit 0
fi

if [[ -n "$CHANNEL" ]]; then export GOAL_CHANNEL="$CHANNEL"; fi
if [[ -n "$REF" ]]; then export GOAL_REF="$REF"; fi

ROOT_INSTALL="$GOAL_PIPELINE_REPO/install.sh"

if [[ "$UPDATE" == true ]]; then
  goal_read_install_config
  goal_normalize_channel_ref
  REPO_URL="$(git -C "$GOAL_PIPELINE_REPO" remote get-url origin 2>/dev/null || echo "")"
  if [[ -z "$REPO_URL" ]]; then
    echo "goal-install: install repository missing at $GOAL_PIPELINE_REPO — run install.sh first" >&2
    exit 1
  fi
  echo "📦 Updating repository (channel=${GOAL_INSTALL_CHANNEL}, ref=${GOAL_INSTALL_REF:-<auto>})..."
  goal_sync_repository "$REPO_URL" "$GOAL_PIPELINE_REPO" "$GOAL_INSTALL_CHANNEL" "$GOAL_INSTALL_REF"
  goal_write_install_config "$GOAL_INSTALL_CHANNEL" "$GOAL_INSTALL_REF" \
    "${GOAL_RESOLVED_REF:-}" "${GOAL_RESOLVED_COMMIT:-}"

  SYNC="$GOAL_PIPELINE_REPO/goal-pipeline/scripts/sync-install-repo.sh"
  if [[ -f "$SYNC" ]]; then
    env -u GOAL_DEV_REPO DEPLOY_SOURCE="$GOAL_PIPELINE_REPO" bash "$SYNC" --deploy-only
  else
    SYNC="$GOAL_STATE_HOME/scripts/sync-install-repo.sh"
    [[ -f "$SYNC" ]] && env -u GOAL_DEV_REPO DEPLOY_SOURCE="$GOAL_PIPELINE_REPO" bash "$SYNC" --deploy-only
  fi

  DEPLOY="$GOAL_PIPELINE_REPO/goal-pipeline/scripts/deploy-skills.sh"
  [[ -f "$DEPLOY" ]] && bash "$DEPLOY" --also-platform-native --quiet 2>/dev/null || \
    bash "$GOAL_STATE_HOME/scripts/deploy-skills.sh" --also-platform-native --quiet 2>/dev/null || true

  echo "✅ Update complete (${GOAL_RESOLVED_REF:-?} @ ${GOAL_RESOLVED_COMMIT:-?})"
  exit 0
fi

if [[ ${#EXTRA_ARGS[@]} -gt 0 && -f "$ROOT_INSTALL" ]]; then
  exec bash "$ROOT_INSTALL" "${EXTRA_ARGS[@]}"
fi

echo "goal-install: use --update, --status, or run install.sh from repository" >&2
exit 1
