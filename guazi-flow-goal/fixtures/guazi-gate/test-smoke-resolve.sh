#!/bin/bash
set -euo pipefail
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/package.json" << 'PJ'
{"scripts":{"dev":"npm run serve","serve":"vue-cli-service serve"}}
PJ
touch "$TMP/yarn.lock"
cd "$TMP"
OUT=$(bash /Users/xuwei/Profession/goal/goal-pipeline/scripts/runtime-smoke.sh --repo-root "$TMP" --task-dir "$TMP/task" --skip-install 2>/dev/null | head -1 || true)
# Should not contain "yarn run npm"
if echo "$OUT" | grep -q 'yarn run npm'; then
  echo "FAIL dev_cmd wrapped npm incorrectly"; exit 1
fi
echo "OK dev_cmd boundary"
