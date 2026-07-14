#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/../../review-channel-guard.py"
# Fixtures assert key presence / anti-downgrade — skip live HTTPS probe.
export GOAL_REVIEW_PROBE=0

tmp_home=$(mktemp -d)
trap 'rm -rf "$tmp_home"' EXIT

write_config() {
  cat > "$tmp_home/config.json" <<'JSON'
{
  "api_keys": {
    "DEEPSEEK_API_KEY": "test-key-not-real"
  },
  "review_model": "deepseek/deepseek-v4-flash"
}
JSON
}

run_guard() {
  # Isolate from host env keys so "no config" cases are not polluted.
  env -u DEEPSEEK_API_KEY -u OPENAI_API_KEY -u ANTHROPIC_API_KEY -u GEMINI_API_KEY -u GROQ_API_KEY \
    GOAL_STATE_HOME="$tmp_home" GOAL_REVIEW_PROBE=0 GOAL_EXEC_PROVIDER= GOAL_EXEC_MODEL= \
    python3 "$GUARD" "$@"
}

echo "=== review-channel-guard blocks deterministic when configured ==="
write_config
if run_guard --check --provider deterministic; then
  echo "FAIL expected block for deterministic"; exit 1
fi
echo "OK deterministic blocked"

echo "=== review-channel-guard blocks FORCE_DETERMINISTIC when configured ==="
if run_guard --check --force-det 1 --provider deterministic; then
  echo "FAIL expected block for force deterministic"; exit 1
fi
echo "OK force deterministic blocked"

echo "=== review-channel-guard resolves configured provider ==="
RESOLVE=$(run_guard --resolve --provider "" --model "" --force-det 0 --mode unified)
eval "$RESOLVE"
if [[ "$RESOLVED_REVIEW_PROVIDER" != "deepseek" ]]; then
  echo "FAIL expected deepseek got $RESOLVED_REVIEW_PROVIDER"; exit 1
fi
echo "OK resolve -> $RESOLVED_REVIEW_PROVIDER/$RESOLVED_REVIEW_MODEL"

echo "=== review-channel-guard allows CI deterministic without config ==="
rm -f "$tmp_home/config.json"
if ! run_guard --check --force-det 1 --provider deterministic; then
  echo "FAIL expected allow force deterministic without config"; exit 1
fi
echo "OK CI deterministic allowed without config"

echo "OK review-channel-guard"
