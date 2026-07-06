#!/bin/bash
# setup-dev-sync-hooks.sh — Enable auto-sync of ~/.goal-pipeline-repo for this dev clone
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$ROOT/.githooks"

chmod +x "$HOOKS_DIR/pre-push" "$ROOT/goal-pipeline/scripts/sync-install-repo.sh"

git -C "$ROOT" config core.hooksPath .githooks

DEV_REPO="$ROOT"
STATE_HOME="${GOAL_STATE_HOME:-$HOME/.goal-state}"
mkdir -p "$STATE_HOME"
python3 - "$STATE_HOME/config.json" "$DEV_REPO" <<'PY'
import json, os, sys
from pathlib import Path

cfg_path = Path(sys.argv[1])
dev_repo = sys.argv[2]
cfg = {}
if cfg_path.is_file():
    try:
        cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
    except Exception:
        cfg = {}
cfg.setdefault("version", 1)
cfg["dev_repo"] = dev_repo
cfg_path.parent.mkdir(parents=True, exist_ok=True)
cfg_path.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"  dev_repo -> {dev_repo}")
PY

echo "✅ git hooksPath -> .githooks (pre-push syncs ~/.goal-pipeline-repo)"
echo "✅ dev_repo written to $STATE_HOME/config.json"
echo ""
echo "Run once now:"
bash "$ROOT/goal-pipeline/scripts/sync-install-repo.sh" --from-dev "$ROOT"
