#!/bin/bash
# deploy-skills.sh — Deploy goal-pipeline skills from install repository only
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/source-goal-install-paths.sh"
_goal_install_paths
REPO_DIR="$GOAL_PIPELINE_REPO"
SKILLS_DEPLOY_MODE="${SKILLS_DEPLOY_MODE:-universal}"
MODE="--symlink"
NO_GUAZI=false
ALSO_PLATFORM_NATIVE=false
QUIET=false
UNINSTALL=false

SKILL_NAMES=("goal-pipeline")
DUPLICATE_DIRS=(
  "$HOME/.cursor/skills"
  "$HOME/.pi/skills"
  "$HOME/.pi/agent/skills"
  "$HOME/.codex/skills"
  "$HOME/.windsurf/skills"
  "$HOME/.qoder/skills"
  "$HOME/.hermes/skills"
  "$HOME/.continue/skills"
  "$HOME/.roo/skills"
)

usage() {
  cat <<'USAGE'
Usage: deploy-skills.sh [options]

Deploy goal-pipeline / guazi-flow-goal skills from GOAL_PIPELINE_REPO (default: ~/.goal-pipeline/repository).
Skill symlinks MUST NOT point at a dev checkout.

**Consumers:**
  - **goal-pipeline (default):** deploys `goal-pipeline` only (`--no-guazi`). Does NOT require guazi-flow-* marketplace.
  - **guazi adapter:** omit `--no-guazi` to also deploy `guazi-flow-goal` for `pipeline_track=guazi` / `docs/guazi-flow` tasks.

Options:
  --symlink              Symlink skills (default)
  --copy                 Copy skill directories
  --also-platform-native Also deploy to per-agent native dirs (all still point at install repo)
  --no-guazi             Skip guazi-flow-goal
  --uninstall            Remove goal-pipeline skills from managed paths
  --quiet|-q             Minimal output
  -h, --help             Show help

Environment:
  GOAL_HOME              Application root (default: ~/.goal-pipeline)
  GOAL_PIPELINE_REPO     Install clone (default: $GOAL_HOME/repository)
  SKILLS_DEPLOY_MODE     universal (default) | platform-native

Note: Pure goal consumers should use `--no-guazi` (or set NO_GUAZI=1). Guazi adapter requires
guazi-flow-* marketplace skills in addition to guazi-flow-goal.
USAGE
}

log() {
  if [[ "$QUIET" != "true" ]]; then
    echo "$@"
  fi
}

warn() {
  echo "deploy-skills: $*" >&2
}

get_skills_dir() {
  local agent="$1"
  case "$agent" in
    pi)          echo "$HOME/.pi/agent/skills" ;;
    codex)       echo "$HOME/.codex/skills" ;;
    claude_code) echo "$HOME/.claude/skills" ;;
    cursor)      echo "$HOME/.cursor/skills" ;;
    windsurf)    echo "$HOME/.windsurf/skills" ;;
    qoder)       echo "$HOME/.qoder/skills" ;;
    hermes)      echo "$HOME/.hermes/skills" ;;
    continue)    echo "$HOME/.continue/skills" ;;
    roo)         echo "$HOME/.roo/skills" ;;
    *)           echo "$HOME/.agents/skills" ;;
  esac
}

detect_all_agents() {
  local agents=()
  if [ -n "${PI_HOME:-}" ] || [ -d "$HOME/.pi" ] || [ -n "${PI_AGENT:-}" ]; then
    agents+=("pi")
  fi
  if [ -n "${CODEX_HOME:-}" ] || [ -d "$HOME/.codex" ]; then
    agents+=("codex")
  fi
  if [ -d "$HOME/.claude" ] || [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    agents+=("claude_code")
  fi
  if [ -d "$HOME/.cursor" ]; then
    agents+=("cursor")
  fi
  if [ -d "$HOME/.windsurf" ] || [ -n "${WINDSURF_HOME:-}" ]; then
    agents+=("windsurf")
  fi
  if [ -d "$HOME/.qoder" ]; then
    agents+=("qoder")
  fi
  if [ -d "$HOME/.hermes" ]; then
    agents+=("hermes")
  fi
  if [ -d "$HOME/.continue" ]; then
    agents+=("continue")
  fi
  if [ -d "$HOME/.roo" ]; then
    agents+=("roo")
  fi
  if [ ${#agents[@]} -eq 0 ]; then
    echo "generic"
  else
    echo "${agents[@]}"
  fi
}

resolve_dev_repo() {
  if [[ -n "${GOAL_DEV_REPO:-}" && -d "${GOAL_DEV_REPO}/.git" ]]; then
    echo "$(cd "${GOAL_DEV_REPO}" && pwd)"
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
    if isinstance(val, str) and val.strip():
        p = Path(val).expanduser().resolve()
        if p.is_dir() and (p / ".git").is_dir():
            print(p)
            break
PY
  fi
}

canonical_path() {
  local p="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$p" <<'PY'
import os, sys
print(os.path.realpath(os.path.expanduser(sys.argv[1])))
PY
  else
    readlink -f "$p" 2>/dev/null || echo "$p"
  fi
}

is_forbidden_skill_target() {
  local target
  target="$(canonical_path "$1")"
  local repo_real dev_real
  repo_real="$(canonical_path "$REPO_DIR")"

  # Must live under install repo
  case "$target" in
    "$repo_real"/*) ;;
    *)
      return 0
      ;;
  esac

  # Separate DEV clone must not be the skill target; install-repo itself is allowed.
  # When GOAL_DEV_REPO == install repo (pre-push --from-dev $ROOT), do not treat
  # install-repo paths as forbidden.
  dev_real="$(resolve_dev_repo || true)"
  if [[ -n "$dev_real" ]]; then
    dev_real="$(canonical_path "$dev_real")"
    if [[ "$dev_real" != "$repo_real" ]]; then
      case "$target" in
        "$dev_real"/*) return 0 ;;
      esac
    fi
  fi

  return 1
}

remove_skill_at() {
  local target="$1"
  local skill="$2"
  local path="$target/$skill"
  if [[ -L "$path" ]]; then
    rm -f "$path"
    log "    🗑️  removed duplicate: $path"
  elif [[ -d "$path" ]]; then
    rm -rf "$path"
    log "    🗑️  removed duplicate: $path"
  fi
}

deploy_to_dir() {
  local skills_dir="$1"
  local label="${2:-$skills_dir}"

  mkdir -p "$skills_dir"
  log "  → $label"

  for skill in "${SKILL_NAMES[@]}"; do
    local target="$skills_dir/$skill"
    local source="$REPO_DIR/$skill"

    if [[ ! -d "$source" ]]; then
      warn "    ⚠️  $source not found, skipping $skill"
      continue
    fi

    if [[ -e "$target" ]]; then
      local existing_resolved
      existing_resolved="$(canonical_path "$target")"
      if is_forbidden_skill_target "$existing_resolved"; then
        log "    ⚠️  replacing forbidden symlink: $target -> $existing_resolved"
      fi
    fi

    if [[ -L "$target" ]]; then
      rm -f "$target"
    elif [[ -d "$target" ]]; then
      log "    🗑️  removing existing: $target"
      rm -rf "$target"
    fi

    if [[ "$MODE" == "--symlink" ]]; then
      ln -sfn "$source" "$target"
      log "    ✅ $skill → symlink ($source)"
    else
      cp -R "$source" "$target"
      log "    ✅ $skill → copied"
    fi

    if is_forbidden_skill_target "$(canonical_path "$target")"; then
      warn "post-deploy validation failed for $target"
      exit 1
    fi
  done
}

remove_duplicates() {
  local universal_dir
  universal_dir="$(canonical_path "$HOME/.agents/skills")"
  log "  cleaning platform duplicates..."
  for skill in "${SKILL_NAMES[@]}"; do
    for dir in "${DUPLICATE_DIRS[@]}"; do
      [[ -d "$dir" ]] || continue
      local dir_real
      dir_real="$(canonical_path "$dir")"
      if [[ "$dir_real" == "$universal_dir" ]]; then
        continue
      fi
      remove_skill_at "$dir" "$skill"
    done
  done
}

uninstall_skills() {
  log "🗑️  Removing goal-pipeline skills..."
  remove_skill_at "$HOME/.agents/skills" "goal-pipeline"
  remove_skill_at "$HOME/.agents/skills" "guazi-flow-goal"
  for skill in "${SKILL_NAMES[@]}"; do
    for dir in "${DUPLICATE_DIRS[@]}" "$HOME/.claude/skills"; do
      [[ -d "$dir" ]] || continue
      remove_skill_at "$dir" "$skill"
    done
  done
  if [[ "$ALSO_PLATFORM_NATIVE" == "true" ]]; then
    local agents
    agents="$(detect_all_agents)"
    for agent in $agents; do
      local dir
      dir="$(get_skills_dir "$agent")"
      for skill in "${SKILL_NAMES[@]}"; do
        remove_skill_at "$dir" "$skill"
      done
    done
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --symlink) MODE="--symlink"; shift ;;
    --copy) MODE="--copy"; shift ;;
    --also-platform-native) ALSO_PLATFORM_NATIVE=true; shift ;;
    --no-guazi) NO_GUAZI=true; shift ;;
    --uninstall) UNINSTALL=true; shift ;;
    --quiet|-q) QUIET=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) warn "unknown option: $1"; usage >&2; exit 2 ;;
  esac
done

if [[ "$NO_GUAZI" != "true" ]]; then
  SKILL_NAMES+=("guazi-flow-goal")
fi

[[ -d "$REPO_DIR" ]] || {
  warn "install repo missing at $REPO_DIR — run install.sh first"
  exit 1
}

if [[ "$UNINSTALL" == "true" ]]; then
  uninstall_skills
  exit 0
fi

log "📋 Deploying skills from install repo: $REPO_DIR"
log "   mode: ${SKILLS_DEPLOY_MODE}${ALSO_PLATFORM_NATIVE:+ + platform-native}"

deploy_to_dir "$HOME/.agents/skills" "universal: ~/.agents/skills"

if [[ "$SKILLS_DEPLOY_MODE" == "universal" ]]; then
  remove_duplicates
fi

if [[ "$ALSO_PLATFORM_NATIVE" == "true" ]]; then
  # Claude Code may not read ~/.agents/skills; deploy native copy only for claude.
  if [[ -d "$HOME/.claude" ]] || [[ -n "${CLAUDE_CODE_SESSION_ID:-}" ]]; then
    deploy_to_dir "$HOME/.claude/skills" "claude_code: ~/.claude/skills"
  fi
fi

log "✅ Skills deployed"
