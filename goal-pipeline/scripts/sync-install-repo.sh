#!/bin/bash
# sync-install-repo.sh — Keep install repository and GOAL_STATE_HOME in sync
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/source-goal-install-paths.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/goal-install-lib.sh"
_goal_install_paths
REPO_DIR="$GOAL_PIPELINE_REPO"

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

Keep GOAL_HOME updated: repository git sync + redeploy runtime to GOAL_STATE_HOME.

Options:
  --quiet         Minimal output
  --pull-only     Git sync only, skip deploy
  --deploy-only   Deploy from current install repo, skip git sync
  --skills-only   Redeploy skill symlinks only (from install repo)
  --from-dev PATH Fetch/merge from a local dev clone (e.g. Profession/goal)
  -h, --help      Show help

Environment:
  GOAL_HOME           Application root (default: ~/.goal-pipeline)
  GOAL_PIPELINE_REPO  Install clone (default: $GOAL_HOME/repository)
  GOAL_STATE_HOME     Runtime state (default: $GOAL_HOME/state)
  GOAL_DEV_REPO       Optional local dev repo for --from-dev auto-detect
  DEPLOY_SOURCE       Override deploy source (e.g. local dev checkout)
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
    warn "skip git sync — $REPO_DIR has local changes (stash or reset first)"
    return 0
  fi

  local origin_url
  origin_url="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || true)"
  log "📦 Syncing install repo (install channel from config): $REPO_DIR"
  goal_sync_git_from_install_config "$REPO_DIR" "$origin_url" || true
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

  # Deploy all top-level runtime scripts (*.sh, *.py, check-consistency, extensionless helpers).
  # Excludes fixtures/ — new pipeline scripts auto-sync on install/update.
  shopt -s nullglob
  local deployed=0
  for src in "$scripts_dir"/*.sh "$scripts_dir"/*.py "$scripts_dir"/check-consistency \
    "$scripts_dir"/detect-review-channels "$scripts_dir"/detect-platform; do
    [[ -f "$src" ]] || continue
    local base
    base="$(basename "$src")"
    cp "$src" "$GOAL_STATE_HOME/scripts/$base"
    chmod +x "$GOAL_STATE_HOME/scripts/$base"
    deployed=$((deployed + 1))
  done
  shopt -u nullglob

  # Stage gate bodies (sourced by gate-guazi-flow-stage.sh)
  if [[ -d "$scripts_dir/gate-lib" ]]; then
    mkdir -p "$GOAL_STATE_HOME/scripts/gate-lib"
    rm -f "$GOAL_STATE_HOME/scripts/gate-lib/"*.sh 2>/dev/null || true
    for src in "$scripts_dir"/gate-lib/*.sh; do
      [[ -f "$src" ]] || continue
      cp "$src" "$GOAL_STATE_HOME/scripts/gate-lib/$(basename "$src")"
      chmod +x "$GOAL_STATE_HOME/scripts/gate-lib/$(basename "$src")"
      deployed=$((deployed + 1))
    done
  fi

  if [[ "$deployed" -eq 0 ]]; then
    warn "no runtime scripts deployed from $scripts_dir"
    return 1
  fi

  local kernel_src="$source_root/goal-pipeline/kernel"
  local kernel_dst="$GOAL_STATE_HOME/kernel"
  local kernel_files=0
  if [[ ! -d "$kernel_src" ]]; then
    warn "kernel dir missing: $kernel_src"
    return 1
  fi
  rm -rf "$kernel_dst"
  mkdir -p "$kernel_dst"
  cp -R "$kernel_src/." "$kernel_dst/"
  kernel_files="$(find "$kernel_dst" -type f ! -path '*/__pycache__/*' ! -name '*.pyc' 2>/dev/null | wc -l | tr -d ' ')"

  local schemas_src="$source_root/goal-pipeline/schemas"
  if [[ -d "$schemas_src" ]]; then
    rm -rf "$GOAL_STATE_HOME/schemas"
    mkdir -p "$GOAL_STATE_HOME/schemas"
    cp -R "$schemas_src/." "$GOAL_STATE_HOME/schemas/"
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
             migration-compat.md measure-field-template.json plan-before-code.md \
             plan-quality-rules.json index-lite-protocol.md p2-eval-runbook.md \
             response-playbook.md escape-register.template.json release-channel.md; do
    [[ -f "$REF_SRC/$ref" ]] || continue
    cp "$REF_SRC/$ref" "$REF_DST/$ref"
  done

  GATE_SRC="$source_root/goal-pipeline/scripts/gate-guazi-flow-stage.sh"
  GATE_HASH="$(shasum -a 256 "$GATE_SRC" 2>/dev/null | cut -c1-16 || sha256sum "$GATE_SRC" 2>/dev/null | cut -c1-16 || echo unknown)"
  GIT_REV="$(git -C "$source_root" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  KERNEL_VERSION="$(python3 - "$kernel_src/__init__.py" <<'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
if not p.is_file():
    raise SystemExit(1)
for line in p.read_text(encoding="utf-8").splitlines():
    m = re.match(r"__version__\s*=\s*['\"]([^'\"]+)['\"]", line.strip())
    if m:
        print(m.group(1))
        break
PY
)"
  KERNEL_VERSION="${KERNEL_VERSION:-unknown}"
  KERNEL_TREE_HASH="$(python3 - "$kernel_src" <<'PY'
import hashlib, sys
from pathlib import Path
root = Path(sys.argv[1])
if not root.is_dir():
    raise SystemExit(1)
h = hashlib.sha256()
for p in sorted(root.rglob("*")):
    if not p.is_file() or "__pycache__" in p.parts or p.suffix == ".pyc":
        continue
    rel = p.relative_to(root).as_posix().encode()
    h.update(rel)
    h.update(p.read_bytes())
print(h.hexdigest()[:16])
PY
)"
  KERNEL_TREE_HASH="${KERNEL_TREE_HASH:-unknown}"
  local pipeline_version git_tag install_channel install_ref
  pipeline_version="$(goal_get_pipeline_version_from_repo "$source_root")"
  git_tag="$(git -C "$source_root" describe --tags --exact-match 2>/dev/null || true)"
  install_channel=""
  install_ref=""
  if [[ -f "$GOAL_STATE_HOME/config.json" ]]; then
    eval "$(python3 - "$GOAL_STATE_HOME/config.json" <<'PY'
import json, sys
try:
    inst = (json.load(open(sys.argv[1], encoding="utf-8")).get("install") or {})
except Exception:
    inst = {}
print(f'install_channel={json.dumps(inst.get("channel") or "")}')
print(f'install_ref={json.dumps(inst.get("ref") or "")}')
PY
)"
  fi
  local sync_note="$REPO_DIR"
  [[ "$source_root" != "$REPO_DIR" ]] && sync_note="${source_root} -> ${REPO_DIR}"
  cat > "$GOAL_STATE_HOME/VERSION" <<VEREOF
{
  "goal_pipeline_version": "$pipeline_version",
  "kernel_version": "$KERNEL_VERSION",
  "kernel_tree_hash": "$KERNEL_TREE_HASH",
  "git_rev": "$GIT_REV",
  "git_tag": "$git_tag",
  "install_channel": "$install_channel",
  "install_ref": "$install_ref",
  "gate_script_hash": "$GATE_HASH",
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "synced_from": "$sync_note"
}
VEREOF

  log "✅ Runtime synced to $GOAL_STATE_HOME (scripts=$deployed, kernel_files=$kernel_files, git_rev=$GIT_REV)"
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
