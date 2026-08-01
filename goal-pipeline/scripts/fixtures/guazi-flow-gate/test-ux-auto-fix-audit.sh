#!/bin/bash
# test-ux-auto-fix-audit.sh — D2/D5 valid pass; policy breach fails strict + evidence
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
AUDIT="$SCRIPTS/ux-auto-fix-audit.py"
FIX="$DIR/contract-iq10-good"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 "$AUDIT" --repo-root "$FIX" --handoff-dir "$FIX/handoff" --format text | grep -q "ok=True"

# --- git fixture: valid D2-only change in write_set ---
cd "$TMP"
git init -q
git config user.email t@t && git config user.name t
mkdir -p handoff src/components
cat > handoff/plan.json << 'JSON'
{
  "stage": "plan",
  "schema_version": 1,
  "write_set": ["src/components/Button.tsx"],
  "task_tier": "S"
}
JSON
cat > src/components/Button.tsx << 'TS'
export function Button() {
  return <button>Go</button>;
}
TS
git add -A && git commit -qm base
perl -pi -e 's/<button>Go<\/button>/<button disabled={loading}>Go<\/button>/' src/components/Button.tsx
EV_PASS="$TMP/evidence-pass.json"
python3 "$AUDIT" \
  --repo-root "$TMP" \
  --handoff-dir "$TMP/handoff" \
  --evidence "$EV_PASS" \
  --format text | grep -q "ok=True"
python3 - "$EV_PASS" << 'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
assert doc.get("ok") is True, doc
assert doc.get("violations") == [], doc
assert doc.get("generated_by") == "ux-auto-fix-audit.py"
assert "src/components/Button.tsx" in doc.get("audited_files", [])
print("OK valid D2 autofix pass")
PY

# --- invalid: D2/D5 change outside write_set (strict blocks) ---
git checkout -q -- src/components/Button.tsx
mkdir -p src/other
cat > src/other/extra.tsx << 'TS'
export function Extra() {
  return <button disabled={loading}>x</button>;
}
TS
git add src/other/extra.tsx
EV_FAIL="$TMP/evidence-fail.json"
if python3 "$AUDIT" \
  --repo-root "$TMP" \
  --handoff-dir "$TMP/handoff" \
  --evidence "$EV_FAIL" \
  --strict \
  --format text 2>/dev/null; then
  echo "FAIL expected strict audit to exit non-zero for out-of-write_set" >&2
  exit 1
fi
python3 - "$EV_FAIL" << 'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
assert doc.get("ok") is False, doc
ids = {v.get("id") for v in doc.get("violations", [])}
assert "AUTOFIX-WS" in ids, doc
assert any(v.get("severity") == "blocker" for v in doc["violations"]), doc
print("OK invalid diff strict + violations recorded")
PY

# --- feature implement in write_set (strict must not block) ---
git checkout -q -- src/other/extra.tsx 2>/dev/null || true
rm -rf src/other
perl -pi -e 's/<button>Go<\/button>/<button>Go feature<\/button>/' src/components/Button.tsx
if ! python3 "$AUDIT" \
  --repo-root "$TMP" \
  --handoff-dir "$TMP/handoff" \
  --strict \
  --format text | grep -q "ok=True"; then
  echo "FAIL strict audit should pass feature-only change in write_set" >&2
  exit 1
fi
echo "OK feature implement in write_set passes strict"

# --- docs/guazi-flow changes excluded from scope ---
mkdir -p docs/guazi-flow/task-a
echo "task doc" > docs/guazi-flow/task-a/index.md
git add docs/guazi-flow/task-a/index.md
python3 "$AUDIT" \
  --repo-root "$TMP" \
  --handoff-dir "$TMP/handoff" \
  --strict \
  --format text | grep -q "ok=True"
echo "OK docs/guazi-flow excluded from autofix scope"

# --- non-strict: D2 outside write_set warns, gate may continue (exit 0) ---
mkdir -p src/other
cat > src/other/extra.tsx << 'TS'
export function Extra() {
  return <button disabled={loading}>x</button>;
}
TS
git add src/other/extra.tsx
EV_WARN="$TMP/evidence-warn.json"
python3 "$AUDIT" \
  --repo-root "$TMP" \
  --handoff-dir "$TMP/handoff" \
  --evidence "$EV_WARN" \
  --format text | grep -q "ok=True"
python3 - "$EV_WARN" << 'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
assert doc.get("ok") is True, doc
warns = [v for v in doc.get("violations", []) if v.get("severity") == "warn"]
assert warns, doc
print("OK non-strict severity warn")
PY

echo "test-ux-auto-fix-audit passed"
