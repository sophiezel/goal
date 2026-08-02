#!/bin/bash
# test-am-extend.sh — AM-07..10 ratchet + implement write_set pre-BLOCK (v3 §10.2 D15, W1.5)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_SCRIPTS:-${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts}"
RATCHET="$SCRIPTS/acceptance-matrix-ratchet.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' exit

# --- Setup: a fake repo + task with plan.json + index.md ---
REPO="$TMP/repo"
mkdir -p "$REPO/src/pages" "$REPO/task/handoff" "$REPO/task/evidence"
echo "export default function Page(){return <div data-testid='btn-save'>save</div>}" > "$REPO/src/pages/Save.tsx"
echo '{"name":"app","dependencies":{"lodash":"4.0.0"}}' > "$REPO/package.json"

cat > "$REPO/task/handoff/plan.json" <<JSON
{
  "write_set": ["src/pages/Save.tsx", "src/nonexistent.tsx"],
  "reference_branch": "main...HEAD",
  "quality_tier": "standard"
}
JSON

cat > "$REPO/task/index.md" <<MD
---
version: 1
current_stage: implement
profile: h5
plan_profile: full
---

## 概览
save button

## 任务目标
add save button

## 范围与写集
- src/pages/Save.tsx

## 完整伪代码
function Page(){ return <button data-testid="btn-save">save</button> }

## 验收与验证矩阵
| ID | 描述 | verify_command | data-testid |
|----|------|-----------------|------------|
| C1 | save btn | yarn test save | btn-save |

## 执行记录
- guazi-flow-implement done
MD

# Fake UVO evidence (so AM-05 skips cleanly)
echo '{"overall":"pass","commands":[]}' > "$REPO/task/evidence/verification-oracle.json"

# Fake diff: simulate Save.tsx changed + package.json unchanged-forbidden
cd "$REPO"
git init -q 2>/dev/null || true
git config user.email t@t.t 2>/dev/null || true
git config user.name t 2>/dev/null || true
git add -A 2>/dev/null || true
git commit -qm base 2>/dev/null || true
# modify Save.tsx to produce a diff
echo "// changed" >> "$REPO/src/pages/Save.tsx"
git add -A 2>/dev/null || true

# Run ratchet
OUT=$(python3 "$RATCHET" --task-dir "$REPO/task" --repo-root "$REPO" --json 2>&1 || true)

# AM-07: phantom path src/nonexistent.tsx → not pass (warning, standard tier)
AM07=$(echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); a=[c for c in d['checks'] if c['id']=='AM-07']; print(a[0]['pass'] if a else 'MISSING')")
[[ "$AM07" == "False" ]] || { echo "FAIL: AM-07 expected False (phantom path) got $AM07"; echo "$OUT"; exit 1; }
echo "OK: AM-07 detects phantom write_set path"

# AM-09: data-testid btn-save IS in diff (Save.tsx contains it) → pass
AM09=$(echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); a=[c for c in d['checks'] if c['id']=='AM-09']; print(a[0]['pass'] if a else 'MISSING')")
[[ "$AM09" == "True" ]] || { echo "FAIL: AM-09 expected True (testid present) got $AM09"; echo "$OUT"; exit 1; }
echo "OK: AM-09 passes when declared data-testid in diff"

# AM-08: no forbidden deps → pass
AM08=$(echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); a=[c for c in d['checks'] if c['id']=='AM-08']; print(a[0]['pass'] if a else 'MISSING')")
[[ "$AM08" == "True" ]] || { echo "FAIL: AM-08 expected True (no forbidden) got $AM08"; exit 1; }
echo "OK: AM-08 passes with no forbidden deps"

# AM-10: write_set touches package.json? No (write_set is src/pages). → skipped/pass
AM10=$(echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); a=[c for c in d['checks'] if c['id']=='AM-10']; print(a[0]['pass'] if a else 'MISSING')")
[[ "$AM10" == "True" ]] || { echo "FAIL: AM-10 expected True got $AM10"; exit 1; }
echo "OK: AM-10 skipped (no package.json in write_set)"

# --- AM-07 strict tier → block severity ---
cat > "$REPO/task/handoff/plan.json" <<JSON
{
  "write_set": ["src/pages/Save.tsx", "src/nonexistent.tsx"],
  "reference_branch": "main...HEAD",
  "quality_tier": "strict"
}
JSON
OUT2=$(python3 "$RATCHET" --task-dir "$REPO/task" --repo-root "$REPO" --json 2>&1 || true)
AM07_SEV=$(echo "$OUT2" | python3 -c "import json,sys; d=json.load(sys.stdin); a=[c for c in d['checks'] if c['id']=='AM-07']; print(a[0].get('severity','') if a else 'MISSING')")
[[ "$AM07_SEV" == "block" ]] || { echo "FAIL: AM-07 strict expected block severity got '$AM07_SEV'"; exit 1; }
echo "OK: AM-07 strict tier → block severity"

# --- AM-08 forbidden dep → block ---
echo '{"name":"app","dependencies":{"react-native-camera":"1.0"}}' > "$REPO/package.json"
git add -A 2>/dev/null || true
OUT3=$(python3 "$RATCHET" --task-dir "$REPO/task" --repo-root "$REPO" --json 2>&1 || true)
AM08_PASS=$(echo "$OUT3" | python3 -c "import json,sys; d=json.load(sys.stdin); a=[c for c in d['checks'] if c['id']=='AM-08']; print(a[0]['pass'] if a else 'MISSING')")
AM08_SEV=$(echo "$OUT3" | python3 -c "import json,sys; d=json.load(sys.stdin); a=[c for c in d['checks'] if c['id']=='AM-08']; print(a[0].get('severity','') if a else 'MISSING')")
[[ "$AM08_PASS" == "False" && "$AM08_SEV" == "block" ]] || { echo "FAIL: AM-08 forbidden dep expected False/block got $AM08_PASS/$AM08_SEV"; exit 1; }
echo "OK: AM-08 detects forbidden dep → block"

echo "test-am-extend passed"
