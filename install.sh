#!/bin/bash
# install.sh - goal-pipeline 一键安装脚本
# 支持: Claude Code / Cursor / Codex / Pi / Windsurf / Qoder / Hermes / Continue / Roo / Generic
# 用法:
#   curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/main/install.sh | bash
#   bash install.sh [选项]
#
set -e

# === 配置 ===
REPO_URL_HTTPS="https://github.com/sophiezel/goal.git"
REPO_URL_SSH="git@github.com-sophiezel:sophiezel/goal.git"
INSTALL_SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || INSTALL_SCRIPT_ROOT=""
MODE="--symlink"
USE_SSH=false
FORCE_AGENT=""
NO_GUAZI=false
UNINSTALL=false
PURGE=false

# === 参数解析 ===
while [ $# -gt 0 ]; do
  case "$1" in
    --symlink) MODE="--symlink"; shift ;;
    --copy)    MODE="--copy"; shift ;;
    --ssh)     USE_SSH=true; shift ;;
    --agent)   FORCE_AGENT="$2"; shift 2 ;;
    --no-guazi) NO_GUAZI=true; shift ;;
    --uninstall) UNINSTALL=true; shift ;;
    --purge)    PURGE=true; shift ;;
    --help|-h)
      cat <<'USAGE'
goal-pipeline installer

Usage: bash install.sh [options]

Options:
  --symlink    Create symlinks (default, git pull auto-updates)
  --copy       Copy files (for platforms that don't support symlinks)
  --ssh        Clone via SSH (requires configured SSH key)
  --agent X    Limit detected-agent list for display; skills always deploy to ~/.agents/skills
               Supported: claude_code, cursor, codex, pi, windsurf, qoder, hermes, continue, roo, generic
  --no-guazi  Install goal-pipeline only, skip guazi-flow-goal skill
  --uninstall Remove skills (universal ~/.agents/skills + duplicate cleanup + Claude copy)
               --agent only affects legacy fallback when deploy-skills.sh is missing
  --purge     With --uninstall: also remove repo and state directory
  -h, --help   Show this help

Examples:
  curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/main/install.sh | bash
  bash install.sh --ssh --agent cursor
  bash install.sh --no-guazi --copy
  bash install.sh --uninstall            # Universal skill cleanup
  bash install.sh --uninstall --purge   # Also remove repo + state
USAGE
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# === Unified install paths (~/.goal-pipeline/{repository,state}) ===
_goal_source_paths_sh() {
  local candidates=()
  [[ -n "$INSTALL_SCRIPT_ROOT" ]] && candidates+=("$INSTALL_SCRIPT_ROOT/goal-pipeline/scripts/source-goal-install-paths.sh")
  [[ -n "${GOAL_PIPELINE_REPO:-}" && -f "${GOAL_PIPELINE_REPO}/goal-pipeline/scripts/source-goal-install-paths.sh" ]] && \
    candidates+=("${GOAL_PIPELINE_REPO}/goal-pipeline/scripts/source-goal-install-paths.sh")
  local p
  for p in "${candidates[@]}"; do
    if [[ -f "$p" ]]; then
      # shellcheck disable=SC1090
      source "$p"
      return 0
    fi
  done
  return 1
}

if ! _goal_source_paths_sh; then
  GOAL_HOME="${GOAL_HOME:-$HOME/.goal-pipeline}"
  GOAL_PIPELINE_REPO="${GOAL_PIPELINE_REPO:-$GOAL_HOME/repository}"
  GOAL_STATE_HOME="${GOAL_STATE_HOME:-$GOAL_HOME/state}"
  export GOAL_HOME GOAL_PIPELINE_REPO GOAL_STATE_HOME
else
  _goal_install_paths
fi
REPO_DIR="$GOAL_PIPELINE_REPO"
mkdir -p "$GOAL_HOME" "$GOAL_STATE_HOME"

# === 平台检测 ===
detect_all_agents() {
  if [ -n "$FORCE_AGENT" ]; then
    echo "$FORCE_AGENT"
    return
  fi

  local agents=()

  # Pi
  if [ -n "${PI_HOME:-}" ] || [ -d "$HOME/.pi" ] || [ -n "${PI_AGENT:-}" ]; then
    agents+=("pi")
  fi
  # Codex
  if [ -n "${CODEX_HOME:-}" ] || [ -d "$HOME/.codex" ]; then
    agents+=("codex")
  fi
  # Claude Code
  if [ -d "$HOME/.claude" ] || [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    agents+=("claude_code")
  fi
  # Cursor
  if [ -d "$HOME/.cursor" ]; then
    agents+=("cursor")
  fi
  # Windsurf
  if [ -d "$HOME/.windsurf" ] || [ -n "${WINDSURF_HOME:-}" ]; then
    agents+=("windsurf")
  fi
  # Qoder
  if [ -d "$HOME/.qoder" ]; then
    agents+=("qoder")
  fi
  # Hermes
  if [ -d "$HOME/.hermes" ]; then
    agents+=("hermes")
  fi
  # Continue
  if [ -d "$HOME/.continue" ]; then
    agents+=("continue")
  fi
  # Roo (Roo Code / Roo Cline)
  if [ -d "$HOME/.roo" ]; then
    agents+=("roo")
  fi

  if [ ${#agents[@]} -eq 0 ]; then
    echo "generic"
  else
    echo "${agents[@]}"
  fi
}

# === Skills 目录映射 ===
get_skills_dir() {
  local agent="$1"
  case "$agent" in
    pi)          echo "$HOME/.pi/skills" ;;
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

# === 主流程 ===
AGENTS=$(detect_all_agents)

# === Uninstall mode ===
if [ "$UNINSTALL" = true ]; then
  echo "=========================================="
  echo "  goal-pipeline uninstaller"
  echo "=========================================="
  echo ""
  echo "  Target agents: $(echo $AGENTS | tr ' ' ', ')"
  echo ""

  SKILLS=("goal-pipeline" "guazi-flow-goal")
  echo "🗑️  Removing skills..."
  DEPLOY_SKILLS_UNINSTALL="$REPO_DIR/goal-pipeline/scripts/deploy-skills.sh"
  if [ ! -f "$DEPLOY_SKILLS_UNINSTALL" ]; then
    DEPLOY_SKILLS_UNINSTALL="$GOAL_STATE_HOME/scripts/deploy-skills.sh"
  fi
  if [ -f "$DEPLOY_SKILLS_UNINSTALL" ]; then
    bash "$DEPLOY_SKILLS_UNINSTALL" --uninstall --also-platform-native
  else
    for AGENT in $AGENTS; do
      SKILLS_DIR=$(get_skills_dir "$AGENT")
      echo "  → $AGENT: $SKILLS_DIR"
      for skill in "${SKILLS[@]}"; do
        target="$SKILLS_DIR/$skill"
        if [ -L "$target" ] || [ -d "$target" ]; then
          rm -rf "$target"
          echo "    ✅ Removed: $skill"
        else
          echo "    ⏭️  Not found: $skill"
        fi
      done
    done
    rm -rf "$HOME/.agents/skills/goal-pipeline" "$HOME/.agents/skills/guazi-flow-goal" 2>/dev/null || true
  fi

  if [ "$PURGE" = true ]; then
    echo ""
    echo "🗑️  Purging install home..."
    if [ -d "$GOAL_PIPELINE_REPO" ]; then
      rm -rf "$GOAL_PIPELINE_REPO"
      echo "  ✅ Removed repository: $GOAL_PIPELINE_REPO"
    fi
    if [ -d "$GOAL_STATE_HOME" ]; then
      rm -rf "$GOAL_STATE_HOME"
      echo "  ✅ Removed state: $GOAL_STATE_HOME"
    fi
    if [ -d "$GOAL_HOME" ]; then
      rmdir "$GOAL_HOME" 2>/dev/null || true
    fi
  else
    echo ""
    echo "  ℹ️  GOAL_HOME ($GOAL_HOME) preserved."
    echo "     Use --purge to remove repository + state under GOAL_HOME."
  fi

  echo ""
  echo "=========================================="
  echo "  🎉 Uninstall complete!"
  echo "=========================================="
  exit 0
fi

echo "=========================================="
echo "  goal-pipeline installer"
echo "=========================================="
echo ""
echo "  Detected agents: $(echo $AGENTS | tr ' ' ', ')"
echo "  GOAL_HOME:       $GOAL_HOME"
echo "  State dir:       $GOAL_STATE_HOME"
echo "  Repository:      $REPO_DIR"
echo "  Install mode:    $MODE"
if [ "$USE_SSH" = true ]; then
  echo "  Clone method:    SSH"
else
  echo "  Clone method:    HTTPS"
fi
if [ "$NO_GUAZI" = true ]; then
  echo "  guazi-flow:      skipped"
fi
echo ""

# === Step 1: Clone or update install repo (origin only; never merge local dev checkout) ===
REPO_URL="$REPO_URL_HTTPS"
[ "$USE_SSH" = true ] && REPO_URL="$REPO_URL_SSH"

if [ ! -d "$REPO_DIR/.git" ]; then
  echo "📦 Cloning repository..."
  git clone "$REPO_URL" "$REPO_DIR"
else
  echo "📦 Updating repository..."
  if ! git -C "$REPO_DIR" pull --ff-only 2>/dev/null; then
    echo "  ⚠️  git pull skipped (local changes or no remote); using existing clone"
  fi
fi

SYNC_SCRIPT="$REPO_DIR/goal-pipeline/scripts/sync-install-repo.sh"

# === Step 2: Deploy skills (universal ~/.agents/skills + Claude native) ===
echo ""
echo "📋 Deploying skills..."
DEPLOY_SKILLS="$REPO_DIR/goal-pipeline/scripts/deploy-skills.sh"
if [ -f "$DEPLOY_SKILLS" ]; then
  DEPLOY_ARGS=(--also-platform-native)
  [ "$MODE" = "--copy" ] && DEPLOY_ARGS+=(--copy)
  [ "$NO_GUAZI" = true ] && DEPLOY_ARGS+=(--no-guazi)
  bash "$DEPLOY_SKILLS" "${DEPLOY_ARGS[@]}"
else
  echo "  ⚠️  deploy-skills.sh not found — skip skill deploy"
fi

# === Initialize GOAL_STATE_HOME skeleton ===
echo ""
echo "📁 Initializing state directory..."

mkdir -p "$GOAL_STATE_HOME/projects"
mkdir -p "$GOAL_STATE_HOME/archive"
mkdir -p "$GOAL_STATE_HOME/scripts"

# Create config.json if not exists
if [ ! -f "$GOAL_STATE_HOME/config.json" ]; then
  cat > "$GOAL_STATE_HOME/config.json" <<'CONFIG'
{
  "version": 1,
  "api_keys": {},
  "review_model": "auto",
  "human_review_accepted": false,
  "channel_cache": {
    "last_probed": "",
    "channels": {}
  }
}
CONFIG
  echo "  ✅ config.json created"
else
  echo "  ✅ config.json already exists"
fi

rm -f "$GOAL_STATE_HOME/scripts/inject-docs-gitignore.sh"

# Deploy scripts from install repo only (ignore dev_repo in config.json)
SYNC_SCRIPT="$REPO_DIR/goal-pipeline/scripts/sync-install-repo.sh"
if [ -f "$SYNC_SCRIPT" ]; then
  env -u GOAL_DEV_REPO DEPLOY_SOURCE="$REPO_DIR" bash "$SYNC_SCRIPT" --deploy-only
else
  SCRIPTS_SRC="$REPO_DIR/goal-pipeline/scripts"
  KERNEL_SRC="$REPO_DIR/goal-pipeline/kernel"
  mkdir -p "$GOAL_STATE_HOME/scripts"
  deployed=0
  for src in "$SCRIPTS_SRC"/*.sh "$SCRIPTS_SRC"/*.py "$SCRIPTS_SRC"/check-consistency; do
    [ -f "$src" ] || continue
    base="$(basename "$src")"
    cp "$src" "$GOAL_STATE_HOME/scripts/$base"
    chmod +x "$GOAL_STATE_HOME/scripts/$base"
    deployed=$((deployed + 1))
  done
  if [ -d "$SCRIPTS_SRC/gate-lib" ]; then
    mkdir -p "$GOAL_STATE_HOME/scripts/gate-lib"
    rm -f "$GOAL_STATE_HOME/scripts/gate-lib/"*.sh 2>/dev/null || true
    for src in "$SCRIPTS_SRC"/gate-lib/*.sh; do
      [ -f "$src" ] || continue
      cp "$src" "$GOAL_STATE_HOME/scripts/gate-lib/$(basename "$src")"
      chmod +x "$GOAL_STATE_HOME/scripts/gate-lib/$(basename "$src")"
      deployed=$((deployed + 1))
    done
  fi
  if [ ! -d "$KERNEL_SRC" ]; then
    echo "  ❌ kernel missing: $KERNEL_SRC" >&2
    exit 1
  fi
  rm -rf "$GOAL_STATE_HOME/kernel"
  mkdir -p "$GOAL_STATE_HOME/kernel"
  cp -R "$KERNEL_SRC/." "$GOAL_STATE_HOME/kernel/"
  kernel_files=$(find "$GOAL_STATE_HOME/kernel" -type f ! -path '*/__pycache__/*' ! -name '*.pyc' 2>/dev/null | wc -l | tr -d ' ')
  SCHEMAS_SRC="$REPO_DIR/goal-pipeline/schemas"
  if [ -d "$SCHEMAS_SRC" ]; then
    rm -rf "$GOAL_STATE_HOME/schemas"
    mkdir -p "$GOAL_STATE_HOME/schemas"
    cp -R "$SCHEMAS_SRC/." "$GOAL_STATE_HOME/schemas/"
  fi
  echo "  ✅ Runtime deployed to $GOAL_STATE_HOME (scripts=$deployed, kernel_files=$kernel_files)"

  GATE_SRC="$REPO_DIR/goal-pipeline/scripts/gate-guazi-flow-stage.sh"
  GATE_HASH=$(shasum -a 256 "$GATE_SRC" 2>/dev/null | cut -c1-16 || sha256sum "$GATE_SRC" 2>/dev/null | cut -c1-16 || echo "unknown")
  GIT_REV=$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  KERNEL_VERSION=$(python3 - "$KERNEL_SRC/__init__.py" <<'PY'
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
)
  KERNEL_VERSION=${KERNEL_VERSION:-unknown}
  KERNEL_TREE_HASH=$(python3 - "$KERNEL_SRC" <<'PY'
import hashlib, sys
from pathlib import Path
root = Path(sys.argv[1])
if not root.is_dir():
    raise SystemExit(1)
h = hashlib.sha256()
for p in sorted(root.rglob("*")):
    if not p.is_file() or "__pycache__" in p.parts or p.suffix == ".pyc":
        continue
    h.update(p.relative_to(root).as_posix().encode())
    h.update(p.read_bytes())
print(h.hexdigest()[:16])
PY
)
  KERNEL_TREE_HASH=${KERNEL_TREE_HASH:-unknown}
  cat > "$GOAL_STATE_HOME/VERSION" << VEREOF
{
  "goal_pipeline_version": "2.3.0-dual-pipeline-kernel",
  "kernel_version": "$KERNEL_VERSION",
  "kernel_tree_hash": "$KERNEL_TREE_HASH",
  "git_rev": "$GIT_REV",
  "gate_script_hash": "$GATE_HASH",
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "synced_from": "$REPO_DIR"
}
VEREOF
  echo "  ✅ VERSION manifest ($GATE_HASH)"

  SCHEMA_SRC="$REPO_DIR/goal-pipeline/references/guazi-flow-artifact-schema"
  SCHEMA_DST="$GOAL_STATE_HOME/references/guazi-flow-artifact-schema"
  if [ -d "$SCHEMA_SRC" ]; then
    mkdir -p "$SCHEMA_DST"
    cp -R "$SCHEMA_SRC/"* "$SCHEMA_DST/" 2>/dev/null || true
    echo "  ✅ guazi-flow-artifact-schema synced"
  fi
  REF_SRC="$REPO_DIR/goal-pipeline/references"
  REF_DST="$GOAL_STATE_HOME/references"
  mkdir -p "$REF_DST"
  for ref in failure-codes.json failure-code-dictionary.md four-planes-checklist.json \
             migration-compat.md measure-field-template.json plan-before-code.md \
             plan-quality-rules.json index-lite-protocol.md p2-eval-runbook.md \
             response-playbook.md escape-register.template.json; do
    [ -f "$REF_SRC/$ref" ] || continue
    cp "$REF_SRC/$ref" "$REF_DST/$ref"
  done
  echo "  ✅ references synced"
fi


# === Done ===
echo ""
echo "=========================================="
echo "  🎉 Installation complete!"
echo "=========================================="
echo ""
echo "  GOAL_HOME:    $GOAL_HOME"
echo "  State:        $GOAL_STATE_HOME"
echo "  Repository:   $REPO_DIR"
echo "  Skills dir:    ~/.agents/skills (universal)"
echo "  Agents:     $(echo $AGENTS | tr ' ' ', ')"
echo "  Runtime:    $GOAL_STATE_HOME/scripts + kernel + references"
echo ""
if [ "$MODE" = "--symlink" ]; then
  echo "  Update skills:   cd $REPO_DIR && git pull"
  echo "  Update runtime:  bash $REPO_DIR/goal-pipeline/scripts/sync-install-repo.sh --deploy-only"
  echo "                   or re-run: bash install.sh"
fi
echo ""
echo "  Usage:"
echo "    /goal-pipeline <目标>          Start a new goal"
echo "    /goal-pipeline-status          Check current goal"
echo "    /goal-pipeline-pause           Pause execution"
echo "    /goal-pipeline-resume          Resume from pause"
echo "    /goal-pipeline-clear           Archive current goal"

# === Step 6: Deploy Stop Hook (optional, user-level) ===
STOP_HOOK_SRC="$REPO_DIR/goal-pipeline/scripts/goal-pipeline-stop-hook.sh"
STOP_HOOK_DST="$HOME/.cursor/hooks/goal-pipeline-stop-hook.sh"
if [ -f "$STOP_HOOK_SRC" ]; then
  mkdir -p "$HOME/.cursor/hooks"
  cp "$STOP_HOOK_SRC" "$STOP_HOOK_DST"
  chmod +x "$STOP_HOOK_DST"
  echo "  ✅ Stop hook deployed to $STOP_HOOK_DST"
  # Merge stop hook into ~/.cursor/hooks.json if missing
  if [ -f "$HOME/.cursor/hooks.json" ]; then
    python3 - "$HOME/.cursor/hooks.json" << 'PYMERGE'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
hooks = data.setdefault("hooks", {})
stop = hooks.setdefault("stop", [])
cmd = {"command": "./hooks/goal-pipeline-stop-hook.sh", "loop_limit": 10}
if not any(h.get("command","").endswith("goal-pipeline-stop-hook.sh") for h in stop):
    stop.append(cmd)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("  ✅ Merged stop hook into ~/.cursor/hooks.json")
PYMERGE
  else
    cat > "$HOME/.cursor/hooks.json" << 'HJSON'
{
  "version": 1,
  "hooks": {
    "stop": [
      {
        "command": "./hooks/goal-pipeline-stop-hook.sh",
        "loop_limit": 10
      }
    ]
  }
}
HJSON
    echo "  ✅ Created ~/.cursor/hooks.json with stop hook"
  fi
fi


echo "    /goal-pipeline-list            List history"
echo ""
