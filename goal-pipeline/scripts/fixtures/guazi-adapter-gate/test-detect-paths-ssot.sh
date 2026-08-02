#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATHS_PY="$SCRIPT_DIR/../../goal_state_paths.py"
DETECT="$SCRIPT_DIR/../../detect-review-channels"

echo "=== goal_state_paths default state_home ==="
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
DEFAULT=$(env -u GOAL_STATE_HOME -u GOAL_HOME python3 "$PATHS_PY" --json | python3 -c "import json,sys; print(json.load(sys.stdin)['state_home'])")
expected="${HOME}/.goal-pipeline/state"
if [[ "$DEFAULT" != "$expected" ]]; then
  echo "FAIL expected state_home=$expected got $DEFAULT"; exit 1
fi
echo "OK default state_home"

echo "=== detect reads config via GOAL_STATE_HOME SSOT ==="
mkdir -p "$tmp"
cat > "$tmp/config.json" <<'JSON'
{"api_keys": {"DEEPSEEK_API_KEY": "fixture-key"}}
JSON
OUT=$(env -u DEEPSEEK_API_KEY -u OPENAI_API_KEY -u ANTHROPIC_API_KEY -u GEMINI_API_KEY -u GROQ_API_KEY \
  GOAL_STATE_HOME="$tmp" GOAL_REVIEW_PROBE=0 GOAL_EXEC_PROVIDER= GOAL_EXEC_MODEL= \
  python3 "$DETECT" --json --no-probe)
HAS=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('has_candidates'), d.get('configured_keys'))" <<<"$OUT")
if [[ "$HAS" != "True True" ]]; then
  echo "FAIL detect did not see config: $HAS"; echo "$OUT"; exit 1
fi
echo "OK detect has_candidates with isolated GOAL_STATE_HOME"

echo "=== runtime_env shell exports from state file ==="
state="$tmp/state.json"
python3 -c "import json; json.dump({'runtime_env': {'state_home': '$tmp', 'goal_home': '${HOME}/.goal-pipeline'}}, open('$state','w'))"
exports=$(env -u GOAL_STATE_HOME python3 "$PATHS_PY" --apply-state-file "$state")
eval "$exports"
if [[ "$(cd "$GOAL_STATE_HOME" && pwd -P)" != "$(cd "$tmp" && pwd -P)" ]]; then
  echo "FAIL bootstrap export GOAL_STATE_HOME=$GOAL_STATE_HOME (tmp=$tmp)"; exit 1
fi
echo "OK runtime_env apply-state-file"

echo "OK detect-paths-ssot"
