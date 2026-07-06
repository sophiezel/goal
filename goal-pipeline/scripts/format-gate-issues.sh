#!/usr/bin/env bash
# format-gate-issues.sh — structured Issue Board for gate failures
# Usage: format-gate-issues.sh --stage-label PLAN --fix-input evidence/plan-gate-fix-input.json
# Optional stdin: JSON issues array (if --fix-input absent or empty issues)
set -euo pipefail

STAGE_LABEL=""
FIX_INPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage-label) STAGE_LABEL="$2"; shift 2 ;;
    --fix-input) FIX_INPUT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$STAGE_LABEL" ]] || { echo "--stage-label required" >&2; exit 2; }

STDIN_JSON=""
if [[ -z "$FIX_INPUT" && ! -t 0 ]]; then
  STDIN_JSON=$(cat)
fi

python3 - "$STAGE_LABEL" "$FIX_INPUT" "$STDIN_JSON" << 'PY'
import json, os, sys

stage_label = sys.argv[1]
fix_input = sys.argv[2]
stdin_json = sys.argv[3] if len(sys.argv) > 3 else ""

issues = []
if fix_input and os.path.isfile(fix_input):
    issues = json.load(open(fix_input, encoding="utf-8")).get("issues", [])
if not issues and stdin_json.strip():
    issues = json.loads(stdin_json)

blockers = [i for i in issues if i.get("severity") == "blocker"]
warnings = [i for i in issues if i.get("severity") not in ("blocker",)]
count_label = f"{len(blockers)} 阻断"
if warnings:
    count_label += f" · {len(warnings)} 警告"

print("══════════════════════════════════════")
print(f"  {stage_label} GATE 未通过 · {count_label}")
print("══════════════════════════════════════")
print("  # | ID   | 问题")
print("  --+------+------------------------------------------")
for n, it in enumerate(issues, 1):
    iid = it.get("id", "?")
    summary = it.get("summary", "").replace("|", "/")
    print(f"  {n} | {iid:<4} | {summary}")
if fix_input:
    print(f"  fix-input: {fix_input}")
print("══════════════════════════════════════")
PY
