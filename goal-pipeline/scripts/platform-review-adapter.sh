#!/bin/bash
# platform-review-adapter.sh — Pluggable backends for independent review
# Usage: platform-review-adapter.sh --provider <name> --packet <path> [--verify-json JSON] [--model M] [--channel unified|goal]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE="$SCRIPT_DIR/platform_review_adapter_core.py"

PROVIDER="deterministic"
PACKET=""
VERIFY_JSON="{}"
MODEL=""
CHANNEL="unified"

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
  mock-unified)
    python3 - "$PACKET" << 'PYMOCK'
import json, sys
packet = json.load(open(sys.argv[1], encoding="utf-8"))
checklist_gf = [{"case_id": c if isinstance(c, str) else c.get("id", "C01"), "passed": True, "detail": "mock"}
                for c in (packet.get("verification_checklist") or ["C01"])[:3]]
checklist_goal = [{"id": item.get("id", "scope_compliant"), "passed": True, "detail": "mock"}
                  for item in (packet.get("goal_checklist") or [])[:6]]
if not checklist_goal:
    checklist_goal = [{"id": "scope_compliant", "passed": True, "detail": "mock"}]
has_gf = bool(packet.get("guazi_flow_rubric"))
out = {
    "schema_version": 1,
    "result": "pass",
    "checklist_goal": checklist_goal,
    "checklist_gf": checklist_gf if has_gf else [],
    "issues": [],
    "gf_skill_attested": has_gf,
    "model": "mock-unified",
    "tokens": {},
}
print(json.dumps(out, ensure_ascii=False))
PYMOCK
    ;;
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
      echo "{\"result\":\"review_undetermined\",\"model\":\"cursor-task-stub\",\"issues\":[],\"checklist_goal\":[],\"checklist_gf\":[]}"
    else
      echo "{\"result\":\"review_undetermined\",\"model\":\"cursor-task-unavailable\",\"issues\":[{\"id\":\"ADP-01\",\"severity\":\"medium\",\"summary\":\"cursor-task backend not configured (GOAL_REVIEW_CURSOR_TASK=1)\",\"channel\":\"goal\"}],\"checklist_goal\":[],\"checklist_gf\":[]}"
    fi
    ;;
  *)
    echo "{\"result\":\"not_pass\",\"issues\":[{\"id\":\"ADP-99\",\"severity\":\"high\",\"summary\":\"unknown provider: $PROVIDER\",\"channel\":\"goal\"}],\"checklist_goal\":[],\"checklist_gf\":[]}"
    ;;
esac
