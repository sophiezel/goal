#!/bin/bash
# test-secret-in-diff.sh — P0: quality-gate secret scan on git-diff changed files (rg + grep fallback)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_SCRIPTS:-${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts}"
QG="$SCRIPTS/quality-gate.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Minimal git repo with a committed clean baseline, then an unstaged secret.
cd "$TMP"
git init -q
git config user.email t@t && git config user.name t
mkdir -p src evidence handoff
echo "export const ok = 1;" > src/clean.ts
git add -A && git commit -qm base

# Introduce an AWS-style key in a changed file.
printf 'const k = "AKIA%s";\n' "ABCDEFGHIJKLMNOP" > src/leak.ts

# Build the minimal evidence quality-gate needs so it reaches the secret check.
cat > evidence/verification-oracle.json << 'JSON'
{"overall":"pass"}
JSON
cat > evidence/runtime-smoke.md << 'MD'
---
result: skipped
---
MD

# quality-gate requires a chain validator + IQ; skip those to isolate secret scan.
OUT=$(GOAL_SKIP_IQ=1 bash "$QG" --task-dir "$TMP" --repo-root "$TMP" --skip-iq 2>&1 || true)
echo "$OUT" | grep -q "QG-L0-secret" || { echo "FAIL secret in diff not detected:"; echo "$OUT"; exit 1; }
echo "OK secret in changed file detected"

# Remove the leak → should no longer flag secret.
rm -f src/leak.ts
OUT2=$(bash "$QG" --task-dir "$TMP" --repo-root "$TMP" --skip-iq 2>&1 || true)
echo "$OUT2" | grep -q "QG-L0-secret" && { echo "FAIL false positive after removing leak:"; echo "$OUT2"; exit 1; }
echo "OK clean tree has no secret flag"

echo "test-secret-in-diff passed"
