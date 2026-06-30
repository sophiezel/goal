#!/bin/bash
# run-independent-review.sh — Independent review with provenance (review-run.json)
# Usage: run-independent-review.sh --task-dir <path> [--provider NAME] [--mode goal|dual] [--packet PATH]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR=""
PROVIDER="${GOAL_REVIEW_PROVIDER:-}"
MODE="${GOAL_REVIEW_MODE:-dual}"
PACKET=""
MODEL=""
ADAPTER="$SCRIPT_DIR/platform-review-adapter.sh"
DETECT="$SCRIPT_DIR/detect-review-channels"
ASSEMBLE="$SCRIPT_DIR/assemble-review-packet.sh"
VERIFY="$SCRIPT_DIR/verify-review.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --provider) PROVIDER="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --packet) PACKET="$2"; shift 2 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$TASK_DIR" ]] || { echo "Usage: $0 --task-dir <path> [--provider ...] [--mode goal|dual]" >&2; exit 2; }
[[ "$TASK_DIR" != /* ]] && TASK_DIR="$(pwd)/$TASK_DIR"
TASK_DIR="$(cd "$TASK_DIR" && pwd)"

EVIDENCE="$TASK_DIR/evidence"
HANDOFF="$TASK_DIR/handoff"
PACKET="${PACKET:-$HANDOFF/review-packet.json}"
OUT_GOAL="$EVIDENCE/review-goal.json"
OUT_GF="$EVIDENCE/review-gf.json"
OUT_RUN="$EVIDENCE/review-run.json"

mkdir -p "$EVIDENCE" "$HANDOFF"
START_MS=$(python3 -c "import time; print(int(time.time()*1000))")

if [[ ! -f "$PACKET" ]]; then
  [[ -x "$ASSEMBLE" ]] || { echo "review-packet missing and assemble script not found" >&2; exit 1; }
  "$ASSEMBLE" --task-dir "$TASK_DIR" >/dev/null
fi
[[ -f "$PACKET" ]] || { echo "review-packet.json missing" >&2; exit 1; }

# Channel / provider selection
if [[ -z "$PROVIDER" ]]; then
  if [[ -x "$DETECT" ]] || [[ -f "$DETECT" ]]; then
    SEL=$(python3 "$DETECT" --json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); s=d.get('selected') or {}; print(s.get('provider','deterministic')+':'+s.get('model',''))" 2>/dev/null || echo "deterministic:")
    PROVIDER="${SEL%%:*}"
    [[ -z "$MODEL" ]] && MODEL="${SEL#*:}"
  fi
fi
PROVIDER="${PROVIDER:-deterministic}"

# CI fixture override: explicit deterministic only when GOAL_REVIEW_FORCE_DETERMINISTIC=1
if [[ "${GOAL_REVIEW_FORCE_DETERMINISTIC:-}" == "1" ]]; then
  PROVIDER="deterministic"
  MODE="goal"
fi

PACKET_HASH=$(shasum -a 256 "$PACKET" 2>/dev/null | cut -c1-16 || sha256sum "$PACKET" 2>/dev/null | cut -c1-16)
WRITE_SET=$(python3 -c "import json; print(chr(44).join(json.load(open(\"$TASK_DIR/handoff/plan.json\")).get(\"write_set\",[])))" 2>/dev/null || echo "")
VERIFY_JSON=$("$VERIFY" "$TASK_DIR" "$WRITE_SET" json 2>/dev/null || echo "{\"overall\":\"not_pass\"}")

CHANNEL_ARG="goal"
[[ "$MODE" == "dual" ]] && CHANNEL_ARG="dual"

REVIEW_BODY=""
if [[ -x "$ADAPTER" ]]; then
  ADAPTER_ARGS=(--provider "$PROVIDER" --packet "$PACKET" --verify-json "$VERIFY_JSON" --channel "$CHANNEL_ARG")
  [[ -n "$MODEL" ]] && ADAPTER_ARGS+=(--model "$MODEL")
  REVIEW_BODY=$("$ADAPTER" "${ADAPTER_ARGS[@]}" 2>/dev/null || echo "{}")
fi

export TASK_DIR PACKET PACKET_HASH VERIFY_JSON PROVIDER MODEL MODE START_MS OUT_GOAL OUT_GF OUT_RUN REVIEW_BODY CHANNEL_ARG
python3 << 'PY'
import json, sys, os, hashlib
from datetime import datetime, timezone

task_dir = os.environ["TASK_DIR"]
packet_path = os.environ["PACKET"]
packet_hash = os.environ["PACKET_HASH"]
verify_json_s = os.environ["VERIFY_JSON"]
provider = os.environ["PROVIDER"]
model = os.environ.get("MODEL", "")
mode = os.environ.get("MODE", "dual")
start_ms = int(os.environ["START_MS"])
out_goal = os.environ["OUT_GOAL"]
out_gf = os.environ["OUT_GF"]
out_run = os.environ["OUT_RUN"]
adapter_body = os.environ.get("REVIEW_BODY", "")

try:
    verify = json.loads(verify_json_s) if verify_json_s.strip() else {"overall": "not_pass"}
except json.JSONDecodeError:
    verify = {"overall": "not_pass", "parse_error": True}

def base_checklist():
    issues, checklist = [], []
    for name, chk in (verify.get("checks") or {}).items():
        passed = bool(chk.get("pass"))
        checklist.append({"id": name, "passed": passed, "detail": str(chk.get("output", ""))[:200]})
        if not passed:
            issues.append({
                "id": f"CHK-{name.upper()}",
                "severity": "high" if name in ("secret", "scope") else "medium",
                "summary": f"verify-review {name} failed",
                "source": "verify-review",
                "root_cause": "implement_error",
            })
    return issues, checklist

issues_goal, checklist_goal = base_checklist()
issues_gf = []
gf_doc = {}
adapter_result = None
dual = None

if adapter_body.strip():
    try:
        parsed = json.loads(adapter_body)
        if "goal" in parsed and "guazi-flow-review" in parsed:
            dual = parsed
        else:
            adapter_result = parsed
    except json.JSONDecodeError:
        pass

if dual:
    gr = dual.get("goal", {})
    gf = dual.get("guazi-flow-review", {})
    for iss in gr.get("issues", gr.get("issues_goal", [])):
        issues_goal.append(iss)
    for item in gr.get("checklist", []):
        if isinstance(item, dict):
            checklist_goal.append(item)
    issues_gf = list(gf.get("issues", []))
    gf_doc = {
        "schema_version": 1,
        "skill": "guazi-flow-review",
        "skill_attested": bool(gf.get("skill_attested", True)),
        "result": gf.get("result", "not_pass" if issues_gf else "pass"),
        "issues": issues_gf,
        "issues_count": len(issues_gf),
        "model": gf.get("model", model or provider),
        "provider": provider,
        "packet_hash": packet_hash,
    }
elif adapter_result:
    for iss in adapter_result.get("issues", adapter_result.get("issues_goal", [])):
        issues_goal.append(iss)
    for item in adapter_result.get("checklist", []):
        if isinstance(item, dict):
            checklist_goal.append(item)
    if adapter_result.get("skill") == "guazi-flow-review":
        issues_gf = list(adapter_result.get("issues", []))
        gf_doc = {
            "schema_version": 1,
            "skill": "guazi-flow-review",
            "skill_attested": bool(adapter_result.get("skill_attested", True)),
            "result": adapter_result.get("result", "not_pass"),
            "issues": issues_gf,
            "issues_count": len(issues_gf),
        }

result_goal = "pass" if verify.get("overall") == "pass" and not issues_goal else "not_pass"
if adapter_result and adapter_result.get("result") and adapter_result["result"] != "pass":
    result_goal = "not_pass"
if dual and dual.get("goal", {}).get("result") == "not_pass":
    result_goal = "not_pass"

gf_result = gf_doc.get("result", "pass" if not issues_gf else "not_pass")
merged_pass = result_goal == "pass" and gf_result == "pass" and not issues_goal and not issues_gf

separation_confidence = "high" if provider not in ("deterministic",) else "low"
if separation_confidence == "low" and result_goal == "pass" and mode != "dual":
    result_goal = "review_undetermined"

end_ms = int(__import__("time").time() * 1000)
run_id = hashlib.sha256(f"{packet_hash}:{start_ms}".encode()).hexdigest()[:16]

goal_doc = {
    "schema_version": 1,
    "result": result_goal,
    "issues": issues_goal,
    "checklist": checklist_goal,
    "separation_confidence": separation_confidence,
    "provider": provider,
    "model": model or (adapter_result or {}).get("model", provider),
    "packet_hash": packet_hash,
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
with open(out_goal, "w", encoding="utf-8") as f:
    json.dump(goal_doc, f, indent=2, ensure_ascii=False)

if gf_doc:
    with open(out_gf, "w", encoding="utf-8") as f:
        json.dump(gf_doc, f, indent=2, ensure_ascii=False)

channels = ["goal"]
if gf_doc:
    channels.append("guazi-flow-review")

run_doc = {
    "schema_version": 1,
    "run_id": run_id,
    "provider": provider,
    "model": goal_doc.get("model", provider),
    "mode": mode,
    "channels": channels,
    "gf_skill_attested": bool(gf_doc.get("skill_attested")) if gf_doc else False,
    "packet_hash": packet_hash,
    "packet_path": os.path.relpath(packet_path, task_dir),
    "latency_ms": end_ms - start_ms,
    "tokens": (adapter_result or {}).get("tokens", {}) if adapter_result else {},
    "output_hash": hashlib.sha256(json.dumps(goal_doc, sort_keys=True).encode()).hexdigest()[:16],
    "started_at": datetime.fromtimestamp(start_ms / 1000, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "finished_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
with open(out_run, "w", encoding="utf-8") as f:
    json.dump(run_doc, f, indent=2, ensure_ascii=False)

print(json.dumps({
    "result": result_goal,
    "review_goal": out_goal,
    "review_gf": out_gf if gf_doc else None,
    "review_run": out_run,
    "issues_goal_count": len(issues_goal),
    "issues_gf_count": len(issues_gf),
    "gf_skill_attested": run_doc["gf_skill_attested"],
}))
PY
