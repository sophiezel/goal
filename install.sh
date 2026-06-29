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
REPO_DIR="$HOME/.goal-pipeline-repo"
GOAL_STATE_HOME="${GOAL_STATE_HOME:-$HOME/.goal-state}"
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
  --agent X    Force agent platform (skip auto-detection)
               If omitted, installs to ALL detected agents
               Supported: claude_code, cursor, codex, pi, windsurf, qoder, hermes, continue, roo, generic
  --no-guazi  Install goal-pipeline only, skip guazi-flow-goal skill
  --uninstall Remove skills from all detected agents (use with --agent to target one)
  --purge     With --uninstall: also remove repo and state directory
  -h, --help   Show this help

Examples:
  curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/main/install.sh | bash
  bash install.sh --ssh --agent cursor
  bash install.sh --no-guazi --copy
  bash install.sh --uninstall            # Remove skills from all agents
  bash install.sh --uninstall --purge   # Also remove repo + state
  bash install.sh --uninstall --agent qoder  # Remove from Qoder only
USAGE
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

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

  if [ "$PURGE" = true ]; then
    echo ""
    echo "🗑️  Purging repo and state..."
    if [ -d "$REPO_DIR" ]; then
      rm -rf "$REPO_DIR"
      echo "  ✅ Removed repo: $REPO_DIR"
    fi
    if [ -d "$GOAL_STATE_HOME" ]; then
      rm -rf "$GOAL_STATE_HOME"
      echo "  ✅ Removed state: $GOAL_STATE_HOME"
    fi
  else
    echo ""
    echo "  ℹ️  Repo ($REPO_DIR) and state ($GOAL_STATE_HOME) preserved."
    echo "     Use --purge to also remove them."
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
echo "  State dir:       $GOAL_STATE_HOME"
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

# === Step 1: Clone or update repo ===
REPO_URL="$REPO_URL_HTTPS"
[ "$USE_SSH" = true ] && REPO_URL="$REPO_URL_SSH"

if [ ! -d "$REPO_DIR/.git" ]; then
  echo "📦 Cloning repository..."
  git clone "$REPO_URL" "$REPO_DIR"
else
  echo "📦 Updating repository..."
  cd "$REPO_DIR" && git pull
fi

# === Step 2: Deploy skills to all detected agents ===
SKILLS=("goal-pipeline")
if [ "$NO_GUAZI" = false ]; then
  SKILLS+=("guazi-flow-goal")
fi

echo ""
echo "📋 Deploying skills..."

for AGENT in $AGENTS; do
  SKILLS_DIR=$(get_skills_dir "$AGENT")
  mkdir -p "$SKILLS_DIR"
  echo "  → $AGENT: $SKILLS_DIR"

  for skill in "${SKILLS[@]}"; do
    target="$SKILLS_DIR/$skill"
    source="$REPO_DIR/$skill"

    if [ ! -d "$source" ]; then
      echo "    ⚠️  $source not found, skipping"
      continue
    fi

    # Remove existing deployment
    if [ -L "$target" ]; then
      rm "$target"
    elif [ -d "$target" ]; then
      echo "    🗑️  Removing existing: $target"
      rm -rf "$target"
    fi

    if [ "$MODE" = "--symlink" ]; then
      ln -sfn "$source" "$target"
      echo "    ✅ $skill → symlink"
    else
      cp -r "$source" "$target"
      echo "    ✅ $skill → copied"
    fi
  done
done

# === Step 4: Migrate old paths (before skeleton creation) ===
if [ -d "$HOME/.guazi-flow-goal" ]; then
  echo ""
  echo "🔄 Migrating from ~/.guazi-flow-goal/ to $GOAL_STATE_HOME/..."
  mkdir -p "$GOAL_STATE_HOME/projects" "$GOAL_STATE_HOME/archive"
  if [ -d "$HOME/.guazi-flow-goal/projects" ]; then
    cp -r "$HOME/.guazi-flow-goal/projects"/* "$GOAL_STATE_HOME/projects/" 2>/dev/null || true
  fi
  if [ -d "$HOME/.guazi-flow-goal/archive" ]; then
    cp -r "$HOME/.guazi-flow-goal/archive"/* "$GOAL_STATE_HOME/archive/" 2>/dev/null || true
  fi
  echo "  ✅ Migration complete (old directory preserved at ~/.guazi-flow-goal/)"
fi

# === Step 5: Initialize ~/.goal-state/ skeleton ===
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

# Deploy scripts
for script in verify.sh verify-review.sh detect-review-channels detect-platform check-consistency runtime-smoke.sh gate-guazi-flow-stage.sh assemble-review-packet.sh merge-review-issues.sh; do
  src="$REPO_DIR/goal-pipeline/scripts/$script"
  dst="$GOAL_STATE_HOME/scripts/$script"
  if [ -f "$src" ]; then
    cp "$src" "$dst"
    chmod +x "$dst"
  fi
done
echo "  ✅ Scripts deployed to $GOAL_STATE_HOME/scripts/"
# Sync guazi-flow artifact schema (read-only copy for gates)
SCHEMA_SRC="$REPO_DIR/goal-pipeline/references/guazi-flow-artifact-schema"
SCHEMA_DST="$GOAL_STATE_HOME/references/guazi-flow-artifact-schema"
if [ -d "$SCHEMA_SRC" ]; then
  mkdir -p "$SCHEMA_DST"
  cp -R "$SCHEMA_SRC/"* "$SCHEMA_DST/" 2>/dev/null || true
  echo "  ✅ guazi-flow-artifact-schema synced"
fi


# === Done ===
echo ""
echo "=========================================="
echo "  🎉 Installation complete!"
echo "=========================================="
echo ""
echo "  State:      $GOAL_STATE_HOME"
echo "  Repo:       $REPO_DIR"
echo "  Agents:     $(echo $AGENTS | tr ' ' ', ')"
echo "  Skills dirs:"
for AGENT in $AGENTS; do
  echo "    $(get_skills_dir "$AGENT")"
done
echo ""
if [ "$MODE" = "--symlink" ]; then
  echo "  Update:     cd $REPO_DIR && git pull"
fi
echo ""
echo "  Usage:"
echo "    /goal-pipeline <目标>          Start a new goal"
echo "    /goal-pipeline-status          Check current goal"
echo "    /goal-pipeline-pause           Pause execution"
echo "    /goal-pipeline-resume          Resume from pause"
echo "    /goal-pipeline-clear           Archive current goal"
echo "    /goal-pipeline-list            List history"
echo ""
