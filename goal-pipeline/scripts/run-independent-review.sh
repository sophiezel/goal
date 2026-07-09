#!/bin/bash
# run-independent-review.sh — Independent review with provenance (review-run.json)
# Usage: run-independent-review.sh --task-dir <path> [--provider NAME] [--mode unified|goal] [--packet PATH]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR=""
STATE_FILE=""
PROJECT_ROOT=""
PROVIDER="${GOAL_REVIEW_PROVIDER:-}"
MODE="${GOAL_REVIEW_MODE:-unified}"
PACKET=""
MODEL=""
ADAPTER="$SCRIPT_DIR/platform-review-adapter.sh"
GUARD="$SCRIPT_DIR/review-channel-guard.py"
ASSEMBLE="$SCRIPT_DIR/assemble-review-packet.sh"
VERIFY="$SCRIPT_DIR/verify-review.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --provider) PROVIDER="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --packet) PACKET="$2"; shift 2 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$TASK_DIR" ]] || { echo "Usage: $0 --task-dir <path> [--provider ...] [--mode unified|goal]" >&2; exit 2; }
[[ "$TASK_DIR" != /* ]] && TASK_DIR="$(pwd)/$TASK_DIR"
TASK_DIR="$(cd "$TASK_DIR" && pwd)"

RESOLVER="$SCRIPT_DIR/resolve-artifact-paths.py"
_RESOLVE_ARGS=(--task-dir "$TASK_DIR" --format shell --ensure-state)
[[ -n "$STATE_FILE" ]] && _RESOLVE_ARGS+=(--state-file "$STATE_FILE")
[[ -n "$PROJECT_ROOT" ]] && _RESOLVE_ARGS+=(--project-root "$PROJECT_ROOT")
eval "$(python3 "$RESOLVER" "${_RESOLVE_ARGS[@]}")"

EVIDENCE="$GOAL_EVIDENCE_DIR"
HANDOFF="$HANDOFF_DIR"
PACKET="${PACKET:-$HANDOFF/review-packet.json}"
OUT_UNIFIED="$EVIDENCE/review-unified.json"
OUT_RUN="$EVIDENCE/review-run.json"

mkdir -p "$EVIDENCE" "$HANDOFF"
START_MS=$(python3 -c "import time; print(int(time.time()*1000))")

if [[ ! -f "$PACKET" ]]; then
  [[ -x "$ASSEMBLE" ]] || { echo "review-packet missing and assemble script not found" >&2; exit 1; }
  ASSEMBLE_ARGS=(--task-dir "$REPO_TASK_DIR")
  [[ -n "$STATE_FILE" ]] && ASSEMBLE_ARGS+=(--state-file "$STATE_FILE")
  [[ -n "$PROJECT_ROOT" ]] && ASSEMBLE_ARGS+=(--project-root "$PROJECT_ROOT")
  "$ASSEMBLE" "${ASSEMBLE_ARGS[@]}" >/dev/null
fi
[[ -f "$PACKET" ]] || { echo "review-packet.json missing" >&2; exit 1; }

# Auto mode: unified when guazi rubric present, else goal-only
if [[ "$MODE" == "unified" ]]; then
  HAS_RUBRIC=$(python3 -c "import json; p=json.load(open('$PACKET')); r=p.get('guazi_flow_rubric') or {}; print('1' if r and any(r.values()) else '0')" 2>/dev/null || echo "0")
  [[ "$HAS_RUBRIC" == "1" ]] || MODE="goal"
fi

[[ -f "$GUARD" ]] || { echo "run-independent-review: review-channel-guard.py missing" >&2; exit 1; }
_FORCE_DET="${GOAL_REVIEW_FORCE_DETERMINISTIC:-0}"
eval "$(python3 "$GUARD" --resolve --provider "${PROVIDER}" --model "${MODEL}" --force-det "$_FORCE_DET" --mode "$MODE")"
PROVIDER="$RESOLVED_REVIEW_PROVIDER"
[[ -n "$MODEL" ]] || MODEL="$RESOLVED_REVIEW_MODEL"

if [[ "${GOAL_REVIEW_DETERMINISTIC_ONLY:-0}" == "1" ]]; then
  if [[ -f "$HANDOFF_DIR/plan.json" ]] || [[ -f "$REPO_TASK_DIR/index.md" ]]; then
    echo "run-independent-review: WARN — unified mode but only deterministic channel available" >&2
    echo "run-independent-review: configure API key/Ollama or set GOAL_REVIEW_FORCE_DETERMINISTIC=1 for CI" >&2
  fi
fi

if [[ "${GOAL_REVIEW_FORCE_DETERMINISTIC:-}" == "1" && "${REVIEW_HAS_CANDIDATES:-0}" != "1" ]]; then
  PROVIDER="deterministic"
  MODE="goal"
fi

PACKET_HASH=$(shasum -a 256 "$PACKET" 2>/dev/null | cut -c1-16 || sha256sum "$PACKET" 2>/dev/null | cut -c1-16)
WRITE_SET=$(python3 -c "import json; print(chr(44).join(json.load(open(\"$HANDOFF_DIR/plan.json\")).get(\"write_set\",[])))" 2>/dev/null || echo "")
VERIFY_JSON=$("$VERIFY" "$REPO_TASK_DIR" "$WRITE_SET" json 2>/dev/null || echo "{\"overall\":\"not_pass\"}")

CHANNEL_ARG="unified"
[[ "$MODE" == "goal" ]] && CHANNEL_ARG="goal"

REVIEW_BODY=""
if [[ -x "$ADAPTER" && "$PROVIDER" != "deterministic" ]]; then
  ADAPTER_ARGS=(--provider "$PROVIDER" --packet "$PACKET" --verify-json "$VERIFY_JSON" --channel "$CHANNEL_ARG")
  [[ -n "$MODEL" ]] && ADAPTER_ARGS+=(--model "$MODEL")
  REVIEW_BODY=$("$ADAPTER" "${ADAPTER_ARGS[@]}" 2>/dev/null || echo "{}")
fi

export TASK_DIR="$REPO_TASK_DIR" PACKET PACKET_HASH VERIFY_JSON PROVIDER MODEL MODE START_MS OUT_UNIFIED OUT_RUN REVIEW_BODY CHANNEL_ARG REVIEW_HAS_CANDIDATES
python3 << 'PY'
import json, sys, os, hashlib
from datetime import datetime, timezone

task_dir = os.environ["TASK_DIR"]
packet_path = os.environ["PACKET"]
packet_doc = json.load(open(packet_path, encoding="utf-8")) if os.path.isfile(packet_path) else {}
packet_hash = os.environ["PACKET_HASH"]
verify_json_s = os.environ["VERIFY_JSON"]
provider = os.environ["PROVIDER"]
model = os.environ.get("MODEL", "")
mode = os.environ.get("MODE", "unified")
has_candidates = os.environ.get("REVIEW_HAS_CANDIDATES", "0") == "1"
start_ms = int(os.environ["START_MS"])
out_unified = os.environ["OUT_UNIFIED"]
out_run = os.environ["OUT_RUN"]
adapter_body = os.environ.get("REVIEW_BODY", "")

try:
    verify = json.loads(verify_json_s) if verify_json_s.strip() else {"overall": "not_pass"}
except json.JSONDecodeError:
    verify = {"overall": "not_pass", "parse_error": True}

def verify_issues():
    issues, checklist = [], []
    for name, chk in (verify.get("checks") or {}).items():
        passed = bool(chk.get("pass"))
        checklist.append({"id": name, "passed": passed, "detail": str(chk.get("output", ""))[:200]})
        if not passed:
            issues.append({
                "id": f"CHK-{name.upper()}",
                "channel": "goal",
                "severity": "blocker" if name in ("secret", "scope") else "warning",
                "summary": f"verify-review {name} failed",
                "file": "",
                "evidence": str(chk.get("output", ""))[:200],
                "root_cause": "implement_error",
            })
    return issues, checklist

chk_issues, chk_checklist = verify_issues()
unified = {
    "schema_version": 1,
    "skill": "goal-pipeline-unified-review",
    "gf_skill_attested": bool((packet_doc.get("guazi_flow_rubric") or {}) and any((packet_doc.get("guazi_flow_rubric") or {}).values())),
    "result": "pass" if verify.get("overall") == "pass" else "not_pass",
    "checklist_goal": chk_checklist,
    "checklist_gf": [],
    "issues": list(chk_issues),
    "provider": provider,
    "model": model or provider,
    "packet_hash": packet_hash,
    "invocation_count": 0 if provider == "deterministic" else 1,
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}

adapter_parsed = {}
if adapter_body.strip():
    try:
        adapter_parsed = json.loads(adapter_body)
        if adapter_parsed:
            for key in ("result", "checklist_goal", "checklist_gf", "issues", "root_cause_summary"):
                if key in adapter_parsed:
                    val = adapter_parsed[key]
                    # Coerce checklist arrays to list[dict]; drop/flag malformed items
                    if key in ("checklist_goal", "checklist_gf") and isinstance(val, list):
                        cleaned = []
                        for item in val:
                            if isinstance(item, dict):
                                cleaned.append(item)
                            elif isinstance(item, str):
                                cleaned.append({"id": item[:80], "result": "unknown", "summary": item[:200]})
                            else:
                                unified.setdefault("issues", []).append({
                                    "id": "ADP-CHECKLIST",
                                    "channel": "goal",
                                    "severity": "warning",
                                    "summary": f"malformed {key} item type={type(item).__name__}",
                                    "root_cause": "implement_error",
                                })
                        unified[key] = cleaned
                    elif key == "issues" and isinstance(val, list):
                        cleaned_iss = []
                        for iss in val:
                            if isinstance(iss, dict):
                                cleaned_iss.append(iss)
                            else:
                                cleaned_iss.append({
                                    "id": "ADP-ISSUE",
                                    "channel": "goal",
                                    "severity": "warning",
                                    "summary": str(iss)[:200],
                                })
                        unified[key] = cleaned_iss
                    else:
                        unified[key] = val
            if adapter_parsed.get("gf_skill_attested") is not None:
                unified["gf_skill_attested"] = bool(adapter_parsed["gf_skill_attested"])
            if adapter_parsed.get("model"):
                unified["model"] = adapter_parsed["model"]
            unified["invocation_count"] = 1
            for iss in unified.get("issues", []):
                if isinstance(iss, dict):
                    iss.setdefault("channel", "goal")
            for iss in chk_issues:
                if iss["id"] not in {i.get("id") for i in unified.get("issues", []) if isinstance(i, dict)}:
                    unified["issues"].append(iss)
            for item in chk_checklist:
                goal_list = [c for c in unified.get("checklist_goal", []) if isinstance(c, dict)]
                ids = {c.get("id") for c in goal_list}
                if item.get("id") not in ids:
                    unified.setdefault("checklist_goal", []).append(item)
    except json.JSONDecodeError:
        pass

# Final sanitize: ensure checklist_goal items are dicts before .get
unified["checklist_goal"] = [
    c if isinstance(c, dict) else {"id": str(c)[:80], "result": "unknown"}
    for c in (unified.get("checklist_goal") or [])
]
unified["checklist_gf"] = [
    c if isinstance(c, dict) else {"id": str(c)[:80], "result": "unknown"}
    for c in (unified.get("checklist_gf") or [])
]
unified["issues"] = [i for i in (unified.get("issues") or []) if isinstance(i, dict)]

blockers = [i for i in unified.get("issues", []) if i.get("severity") == "blocker"]
if verify.get("overall") != "pass":
    unified["result"] = "not_pass"
elif blockers:
    unified["result"] = "not_pass"
elif unified.get("result") not in ("pass", "not_pass", "review_undetermined"):
    unified["result"] = "pass"

separation_confidence = "high" if provider not in ("deterministic",) else "low"
if separation_confidence == "low" and unified["result"] == "pass" and provider == "deterministic":
    unified["result"] = "review_undetermined"

issues_goal = [i for i in unified.get("issues", []) if i.get("channel", "goal") == "goal"]
issues_gf = [i for i in unified.get("issues", []) if i.get("channel") == "guazi-flow-review"]

end_ms = int(__import__("time").time() * 1000)
run_id = hashlib.sha256(f"{packet_hash}:{start_ms}".encode()).hexdigest()[:16]

with open(out_unified, "w", encoding="utf-8") as f:
    json.dump(unified, f, indent=2, ensure_ascii=False)

channels = ["goal"]
if unified.get("gf_skill_attested") or issues_gf or unified.get("checklist_gf"):
    channels.append("guazi-flow-review")

run_doc = {
    "schema_version": 1,
    "run_id": run_id,
    "provider": provider,
    "model": unified.get("model", provider),
    "mode": mode,
    "channels": channels,
    "invocation_count": unified.get("invocation_count", 1 if provider != "deterministic" else 0),
    "gf_skill_attested": bool(unified.get("gf_skill_attested")),
    "gf_rubric_source": packet_doc.get("guazi_flow_rubric", {}).get("rubric_hash", ""),
    "packet_hash": packet_hash,
    "packet_path": os.path.relpath(packet_path, task_dir),
    "latency_ms": end_ms - start_ms,
    "tokens": adapter_parsed.get("tokens", {}),
    "output_hash": hashlib.sha256(json.dumps(unified, sort_keys=True).encode()).hexdigest()[:16],
    "started_at": datetime.fromtimestamp(start_ms / 1000, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "finished_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "channel_guard": {
        "has_candidates": has_candidates,
        "selected_provider": provider if has_candidates else "",
        "selected_model": unified.get("model", model or provider) if has_candidates else "",
        "downgrade_blocked": has_candidates and provider == "deterministic",
    },
}
with open(out_run, "w", encoding="utf-8") as f:
    json.dump(run_doc, f, indent=2, ensure_ascii=False)

print(json.dumps({
    "result": unified["result"],
    "review_unified": out_unified,
    "review_run": out_run,
    "issues_goal_count": len(issues_goal),
    "issues_gf_count": len(issues_gf),
    "gf_skill_attested": run_doc["gf_skill_attested"],
}))
PY
