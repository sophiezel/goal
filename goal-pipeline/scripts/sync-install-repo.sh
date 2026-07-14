#!/bin/bash
# sync-install-repo.sh — Keep ~/.goal-pipeline-repo and ~/.goal-state/scripts in sync
set -euo pipefail

REPO_DIR="${GOAL_PIPELINE_REPO:-$HOME/.goal-pipeline-repo}"
GOAL_STATE_HOME="${GOAL_STATE_HOME:-$HOME/.goal-state}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

QUIET=false
PULL_ONLY=false
DEPLOY_ONLY=false
SKILLS_ONLY=false
FROM_DEV=""
# Preserve DEPLOY_SOURCE when set by caller (e.g. local dev checkout)
DEPLOY_SOURCE="${DEPLOY_SOURCE:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet|-q) QUIET=true; shift ;;
    --pull-only) PULL_ONLY=true; shift ;;
    --deploy-only) DEPLOY_ONLY=true; shift ;;
    --skills-only) SKILLS_ONLY=true; shift ;;
    --from-dev) FROM_DEV="$2"; shift 2 ;;
    -h|--help)
      cat <<'USAGE'
Usage: sync-install-repo.sh [options]

Keep ~/.goal-pipeline-repo updated and redeploy runtime scripts to ~/.goal-state.

Options:
  --quiet         Minimal output
  --pull-only     Git sync only, skip deploy
  --deploy-only   Deploy from current install repo, skip git sync
  --skills-only   Redeploy skill symlinks only (from install repo)
  --from-dev PATH Fetch/merge from a local dev clone (e.g. Profession/goal)
  -h, --help      Show help

Environment:
  GOAL_PIPELINE_REPO  Install clone path (default: ~/.goal-pipeline-repo)
  GOAL_STATE_HOME     Runtime state path (default: ~/.goal-state)
  GOAL_DEV_REPO       Optional local dev repo for --from-dev auto-detect
  DEPLOY_SOURCE       Override deploy source (e.g. local Profession/goal checkout)
USAGE
      exit 0
      ;;
    *) echo "sync-install-repo: unknown option: $1" >&2; exit 2 ;;
  esac
done

log() {
  if [[ "$QUIET" != "true" ]]; then
    echo "$@"
  fi
}

warn() {
  echo "sync-install-repo: $*" >&2
}

repo_clean() {
  git -C "$REPO_DIR" diff --quiet && git -C "$REPO_DIR" diff --cached --quiet
}

resolve_from_dev() {
  if [[ -n "$FROM_DEV" ]]; then
    echo "$FROM_DEV"
    return
  fi
  if [[ -n "${GOAL_DEV_REPO:-}" && -d "${GOAL_DEV_REPO}/.git" ]]; then
    echo "$GOAL_DEV_REPO"
    return
  fi
  local cfg="$GOAL_STATE_HOME/config.json"
  if [[ -f "$cfg" ]]; then
    python3 - "$cfg" <<'PY'
import json, sys
from pathlib import Path
try:
    cfg = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    raise SystemExit
for key in ("dev_repo", "goal_dev_repo"):
    val = cfg.get(key) or (cfg.get("goal") or {}).get(key.replace("goal_", ""))
    if isinstance(val, str) and val.strip() and Path(val).expanduser().is_dir():
        print(str(Path(val).expanduser()))
        break
PY
  fi
}

sync_git() {
  [[ -d "$REPO_DIR/.git" ]] || {
    warn "install repo missing at $REPO_DIR — run install.sh first"
    return 1
  }

  local dev_path
  dev_path="$(resolve_from_dev || true)"
  if [[ -n "$dev_path" && -d "$dev_path/.git" ]]; then
    local branch
    branch="$(git -C "$dev_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
    if ! repo_clean; then
      warn "skip git sync — $REPO_DIR has local changes"
      return 0
    fi
    log "📦 Sync install repo from dev clone: $dev_path ($branch)"
    git -C "$REPO_DIR" fetch "$dev_path" "$branch" --quiet
    git -C "$REPO_DIR" merge --ff-only FETCH_HEAD --quiet
    return 0
  fi

  if ! repo_clean; then
    warn "skip git pull — $REPO_DIR has local changes (stash or reset first)"
    return 0
  fi

  log "📦 Pulling install repo: $REPO_DIR"
  git -C "$REPO_DIR" fetch origin --quiet
  git -C "$REPO_DIR" pull --ff-only --quiet
}

deploy_runtime() {
  local source_root="${DEPLOY_SOURCE:-$REPO_DIR}"
  [[ -d "$source_root" ]] || {
    warn "deploy source missing — cannot deploy"
    return 1
  }

  mkdir -p "$GOAL_STATE_HOME/projects" "$GOAL_STATE_HOME/archive" "$GOAL_STATE_HOME/scripts"

  rm -f "$GOAL_STATE_HOME/scripts/inject-docs-gitignore.sh"

  local scripts_dir="$source_root/goal-pipeline/scripts"
  [[ -d "$scripts_dir" ]] || {
    warn "scripts dir missing: $scripts_dir"
    return 1
  }

  # Deploy all top-level runtime scripts (*.sh, *.py, check-consistency).
  # Excludes fixtures/ — new pipeline scripts auto-sync on install/update.
  shopt -s nullglob
  local deployed=0
  for src in "$scripts_dir"/*.sh "$scripts_dir"/*.py "$scripts_dir"/check-consistency; do
    [[ -f "$src" ]] || continue
    local base
    base="$(basename "$src")"
    cp "$src" "$GOAL_STATE_HOME/scripts/$base"
    chmod +x "$GOAL_STATE_HOME/scripts/$base"
    deployed=$((deployed + 1))
  done
  shopt -u nullglob

  if [[ "$deployed" -eq 0 ]]; then
    warn "no runtime scripts deployed from $scripts_dir"
    return 1
  fi

  SCHEMA_SRC="$source_root/goal-pipeline/references/guazi-flow-artifact-schema"
  SCHEMA_DST="$GOAL_STATE_HOME/references/guazi-flow-artifact-schema"
  if [[ -d "$SCHEMA_SRC" ]]; then
    mkdir -p "$SCHEMA_DST"
    cp -R "$SCHEMA_SRC/"* "$SCHEMA_DST/" 2>/dev/null || true
  fi

  # Four-plane product refs (Kernel / doctor / failure codes)
  REF_SRC="$source_root/goal-pipeline/references"
  REF_DST="$GOAL_STATE_HOME/references"
  mkdir -p "$REF_DST"
  for ref in failure-codes.json failure-code-dictionary.md four-planes-checklist.json \
             migration-compat.md measure-field-template.json plan-before-code.md; do
    [[ -f "$REF_SRC/$ref" ]] || continue
    cp "$REF_SRC/$ref" "$REF_DST/$ref"
  done

  GATE_SRC="$source_root/goal-pipeline/scripts/gate-guazi-flow-stage.sh"
  GATE_HASH="$(shasum -a 256 "$GATE_SRC" 2>/dev/null | cut -c1-16 || sha256sum "$GATE_SRC" 2>/dev/null | cut -c1-16 || echo unknown)"
  GIT_REV="$(git -C "$source_root" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  local sync_note="$REPO_DIR"
  [[ "$source_root" != "$REPO_DIR" ]] && sync_note="${source_root} -> ${REPO_DIR}"
  cat > "$GOAL_STATE_HOME/VERSION" <<VEREOF
{
  "goal_pipeline_version": "2.2.0-review-contract",
  "git_rev": "$GIT_REV",
  "gate_script_hash": "$GATE_HASH",
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "synced_from": "$sync_note"
}
VEREOF

  log "✅ Runtime scripts synced to $GOAL_STATE_HOME/scripts/ ($deployed files, git_rev=$GIT_REV)"
}

deploy_skills() {
  local deploy_script="$SCRIPT_DIR/deploy-skills.sh"
  if [[ ! -f "$deploy_script" ]]; then
    deploy_script="$REPO_DIR/goal-pipeline/scripts/deploy-skills.sh"
  fi
  if [[ ! -f "$deploy_script" ]]; then
    warn "deploy-skills.sh missing — skip skill redeploy"
    return 0
  fi
  local args=(--also-platform-native)
  [[ "$QUIET" == "true" ]] && args+=(--quiet)
  log "📋 Redeploying skills from install repo..."
  bash "$deploy_script" "${args[@]}"
}

main() {
  if [[ -z "${DEPLOY_SOURCE:-}" ]]; then
    local dev_path=""
    dev_path="$(resolve_from_dev || true)"
    if [[ -n "$dev_path" && -d "$dev_path/.git" ]]; then
      DEPLOY_SOURCE="$dev_path"
    else
      DEPLOY_SOURCE="$REPO_DIR"
    fi
  fi

  if [[ "$DEPLOY_ONLY" != "true" && "$SKILLS_ONLY" != "true" ]]; then
    sync_git || true
  fi
  if [[ "$PULL_ONLY" != "true" && "$SKILLS_ONLY" != "true" ]]; then
    deploy_runtime
  fi
  if [[ "$PULL_ONLY" != "true" ]]; then
    deploy_skills
  fi
}

main "$@"
