#!/bin/bash
# platform-review-adapter.sh — Pluggable backends for independent review
# Usage: platform-review-adapter.sh --provider <name> --packet <path> [--verify-json JSON] [--model M] [--channel goal|guazi-flow-review|dual]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE="$SCRIPT_DIR/platform_review_adapter_core.py"

PROVIDER="deterministic"
PACKET=""
VERIFY_JSON="{}"
MODEL=""
CHANNEL="goal"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider) PROVIDER="$2"; shift 2 ;;
    --packet) PACKET="$2"; shift 2 ;;
    --verify-json) VERIFY_JSON="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --channel) CHANNEL="$2"; shift 2 ;;
    *) shift ;;
  esac
done

case "$PROVIDER" in
  deterministic)
    echo "{}"
    ;;
  openai|openai-api)
    python3 "$CORE" --provider openai --packet "$PACKET" --channel "$CHANNEL" ${MODEL:+--model "$MODEL"}
    ;;
  anthropic|claude-native)
    python3 "$CORE" --provider anthropic --packet "$PACKET" --channel "$CHANNEL" ${MODEL:+--model "$MODEL"}
    ;;
  deepseek)
    python3 "$CORE" --provider deepseek --packet "$PACKET" --channel "$CHANNEL" ${MODEL:+--model "$MODEL"}
    ;;
  gemini)
    python3 "$CORE" --provider gemini --packet "$PACKET" --channel "$CHANNEL" ${MODEL:+--model "$MODEL"}
    ;;
  groq)
    python3 "$CORE" --provider groq --packet "$PACKET" --channel "$CHANNEL" ${MODEL:+--model "$MODEL"}
    ;;
  ollama)
    python3 "$CORE" --provider ollama --packet "$PACKET" --channel "$CHANNEL" ${MODEL:+--model "$MODEL"}
    ;;
  cursor-task)
    if [[ "${GOAL_REVIEW_CURSOR_TASK:-}" == "1" ]] && command -v cursor &>/dev/null; then
      echo "{\"result\":\"review_undetermined\",\"model\":\"cursor-task-stub\",\"issues\":[],\"checklist\":[],\"tokens\":{}}"
    else
      echo "{\"result\":\"review_undetermined\",\"model\":\"cursor-task-unavailable\",\"issues\":[{\"id\":\"ADP-01\",\"severity\":\"medium\",\"summary\":\"cursor-task backend not configured (GOAL_REVIEW_CURSOR_TASK=1)\"}],\"checklist\":[]}"
    fi
    ;;
  *)
    echo "{\"result\":\"not_pass\",\"issues\":[{\"id\":\"ADP-99\",\"severity\":\"high\",\"summary\":\"unknown provider: $PROVIDER\"}],\"checklist\":[]}"
    ;;
esac
