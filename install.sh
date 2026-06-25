#!/bin/bash
set -e

REPO_URL="https://github.com/sophiezel/goal-pipeline.git"
REPO_DIR="$HOME/.goal-pipeline"
SKILLS_DIR="$HOME/.agents/skills"
SKILLS=("goal-pipeline" "guazi-flow-goal" "guazi-flow-goal-core")
MODE="${1:---symlink}"  # default: symlink, alternative: --copy

usage() {
  echo "Usage: $0 [--symlink|--copy]"
  echo "  --symlink  创建符号链接（默认，git pull 后自动生效）"
  echo "  --copy     复制文件（兼容不支持 symlink 的平台）"
  exit 1
}

case "$MODE" in
  --symlink|--copy) ;;
  *) usage ;;
esac

# Step 1: Clone or update repo
if [ ! -d "$REPO_DIR/.git" ]; then
  echo "📦 Cloning repository..."
  git clone "$REPO_URL" "$REPO_DIR"
else
  echo "📦 Updating repository..."
  cd "$REPO_DIR" && git pull
fi

# Step 2: Ensure skills directory exists
mkdir -p "$SKILLS_DIR"

# Step 3: Deploy each skill
for skill in "${SKILLS[@]}"; do
  target="$SKILLS_DIR/$skill"
  source="$REPO_DIR/$skill"

  if [ ! -d "$source" ]; then
    echo "⚠️  Warning: $source not found, skipping"
    continue
  fi

  # Remove existing deployment
  if [ -L "$target" ]; then
    rm "$target"
  elif [ -d "$target" ]; then
    echo "🗑️  Removing existing directory: $target"
    rm -rf "$target"
  fi

  if [ "$MODE" = "--symlink" ]; then
    ln -sfn "$source" "$target"
    echo "✅ $skill → symlink created"
  else
    cp -r "$source" "$target"
    echo "✅ $skill → copied"
  fi
done

echo ""
echo "🎉 Installation complete!"
echo "   Skills deployed to: $SKILLS_DIR"
echo "   Mode: $MODE"
if [ "$MODE" = "--symlink" ]; then
  echo "   Update: cd $REPO_DIR && git pull"
fi
