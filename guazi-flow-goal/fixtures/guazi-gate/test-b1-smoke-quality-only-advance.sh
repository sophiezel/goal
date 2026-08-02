#!/usr/bin/env bash
# v1.2 B1: smoke gate deprecated; advance + chain validate quality-only verify handoff
set -euo pipefail
export GOAL_ARTIFACT_MODE=repo_full
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts/guazi-gate-stage.sh"
ADVANCE="${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts/guazi-advance-stage.sh"

echo "=== B1: guazi-advance-stage ignores smoke-only handoff ==="
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)
mkdir -p "$REPO_ROOT/.cache"
tmpdir=$(mktemp -d "$REPO_ROOT/.cache/guazi-b1-advance-XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/handoff" "$tmpdir/evidence"
cp "$SCRIPT_DIR/smoke-good/handoff/implement.json" "$tmpdir/handoff/"
cp "$SCRIPT_DIR/smoke-good/handoff/smoke.json" "$tmpdir/handoff/"
cp "$SCRIPT_DIR/smoke-good/evidence/runtime-smoke.md" "$tmpdir/evidence/"
cp "$SCRIPT_DIR/plan-good/index.md" "$tmpdir/index.md"
REL_TASK="${tmpdir#$REPO_ROOT/}"
STATE="$tmpdir/state.json"
cat > "$STATE" <<'JSON'
{
  "status": "active",
  "project_root": "REPO_ROOT_PLACEHOLDER",
  "guazi_flow_task": "REL_TASK_PLACEHOLDER",
  "guazi_flow_stages": {
    "plan": {"gate": {"passed_at": "2026-01-01T00:00:00Z", "post_exit_code": 0}},
    "implement": {"gate": {"passed_at": "2026-01-01T00:00:00Z", "post_exit_code": 0}}
  }
}
JSON
python3 - "$STATE" "$REPO_ROOT" "$REL_TASK" <<'PY'
import json, sys
p, root, rel = sys.argv[1:4]
d = json.load(open(p))
d["project_root"] = root
d["guazi_flow_task"] = rel
json.dump(d, open(p, "w"))
PY
OUT=$("$ADVANCE" --state-file "$STATE" --task-dir "$tmpdir" --project-root "$REPO_ROOT" --format json)
NEXT=$(echo "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('next_stage'))")
REASON=$(echo "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('blocked_reason'))")
if [[ "$NEXT" != "quality" ]]; then
  echo "FAIL advance next_stage=$NEXT reason=$REASON expected quality"; echo "$OUT"; exit 1
fi
echo "OK advance requires quality.json (smoke handoff alone insufficient)"

echo "=== B1: validate-pipeline-chain rejects smoke-only verify handoff ==="
CHAIN="${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts/validate-pipeline-chain.py"
# plan-good + runtime-smoke, no quality.json
CHAIN_OUT=$(python3 "$CHAIN" --task-dir "$tmpdir" --state-file "$STATE" 2>/dev/null || true)
if echo "$CHAIN_OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
errs = d.get('errors') or []
assert any('quality' in e for e in errs), errs
"; then
  echo "OK chain requires quality.json"
else
  echo "FAIL chain should error without quality.json"; exit 1
fi

echo "=== B1: default profile blocks --stage smoke ==="
if "$GATE" --task-dir "$SCRIPT_DIR/smoke-good" --stage smoke --post --mode guazi 2>/dev/null; then
  echo "FAIL smoke gate should be blocked"; exit 1
fi
echo "OK smoke gate blocked by default"
