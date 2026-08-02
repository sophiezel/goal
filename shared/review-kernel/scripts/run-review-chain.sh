#!/bin/bash
# run-review-chain.sh — Atomic review script chain (pipeline-agnostic)
set -euo pipefail

if [[ -z "${REVIEW_KERNEL_HOME:-}" ]]; then
  _RK_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REVIEW_KERNEL_HOME="$(cd "$_RK_SCRIPT/.." && pwd)"
fi
export REVIEW_KERNEL_HOME
KERNEL_SCRIPTS="$REVIEW_KERNEL_HOME/scripts"
KERNEL_CLI="$REVIEW_KERNEL_HOME/kernel/review/cli.py"

TASK_DIR=""
STATE_FILE=""
PROJECT_ROOT=""
MODE="${GOAL_REVIEW_MODE:-unified}"
PIPELINE_SCRIPTS="${GOAL_PIPELINE_SCRIPTS:-${GOAL_STATE_HOME:-}/scripts}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --pipeline-scripts) PIPELINE_SCRIPTS="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --task-dir <path> [--state-file PATH] [--project-root PATH] [--mode unified|goal] [--pipeline-scripts DIR]"
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$TASK_DIR" ]] || { echo "review-chain: --task-dir required" >&2; exit 2; }
[[ "$TASK_DIR" != /* ]] && TASK_DIR="$(pwd)/$TASK_DIR"
TASK_DIR="$(cd "$TASK_DIR" && pwd)"

resolve_pipeline_script() {
  local name="$1"
  if [[ -n "$PIPELINE_SCRIPTS" && -f "$PIPELINE_SCRIPTS/$name" ]]; then
    echo "$PIPELINE_SCRIPTS/$name"
    return
  fi
  if [[ -f "${GOAL_STATE_HOME:-}/scripts/$name" ]]; then
    echo "${GOAL_STATE_HOME}/scripts/$name"
    return
  fi
  echo "$KERNEL_SCRIPTS/$name"
}

if [[ -f "$(resolve_pipeline_script goal-env-bootstrap.sh)" ]]; then
  GOAL_BOOTSTRAP_STATE_FILE="${STATE_FILE:-}"
  # shellcheck disable=SC1091
  source "$(resolve_pipeline_script goal-env-bootstrap.sh)"
fi

RESOLVER=$(resolve_pipeline_script resolve-artifact-paths.py)
_RESOLVE_ARGS=(--task-dir "$TASK_DIR" --format shell --ensure-state)
[[ -n "$STATE_FILE" ]] && _RESOLVE_ARGS+=(--state-file "$STATE_FILE")
[[ -n "$PROJECT_ROOT" ]] && _RESOLVE_ARGS+=(--project-root "$PROJECT_ROOT")
eval "$(python3 "$RESOLVER" "${_RESOLVE_ARGS[@]}")"

COMMON_ARGS=(--task-dir "$REPO_TASK_DIR")
[[ -n "$STATE_FILE" ]] && COMMON_ARGS+=(--state-file "$STATE_FILE")
[[ -n "$PROJECT_ROOT" ]] && COMMON_ARGS+=(--project-root "$PROJECT_ROOT")
[[ -n "$GOAL_STATE_FILE" && -z "$STATE_FILE" ]] && COMMON_ARGS+=(--state-file "$GOAL_STATE_FILE")

ASSEMBLE="$KERNEL_SCRIPTS/assemble-review-packet.sh"
REVIEW="$KERNEL_SCRIPTS/run-independent-review.sh"
MERGE="$KERNEL_SCRIPTS/merge-review-issues.sh"
GUARD="$KERNEL_SCRIPTS/review-channel-guard.py"

[[ -f "$ASSEMBLE" ]] || { echo "review-chain: assemble-review-packet.sh missing under $REVIEW_KERNEL_HOME" >&2; exit 1; }
[[ -f "$REVIEW" ]] || { echo "review-chain: run-independent-review.sh missing" >&2; exit 1; }
[[ -f "$MERGE" ]] || { echo "review-chain: merge-review-issues.sh missing" >&2; exit 1; }
[[ -f "$GUARD" ]] || { echo "review-chain: review-channel-guard.py missing" >&2; exit 1; }

_run_independent_review() {
  local extra_mode="${1:-$MODE}"
  if [[ -f "$KERNEL_CLI" ]]; then
    python3 "$KERNEL_CLI" invoke --task-dir "$REPO_TASK_DIR" --mode "$extra_mode" \
      ${STATE_FILE:+--state-file "$STATE_FILE"} \
      ${PROJECT_ROOT:+--project-root "$PROJECT_ROOT"}
  else
    bash "$REVIEW" "${COMMON_ARGS[@]}" --mode "$extra_mode"
  fi
}

assert_review_packet_preflight() {
  local packet="$HANDOFF_DIR/review-packet.json"
  local uvo="$GOAL_EVIDENCE_DIR/verification-oracle.json"
  local pf="$KERNEL_SCRIPTS/review_packet_preflight.py"
  [[ -f "$packet" ]] || { echo "review-chain: review-packet.json missing after assemble" >&2; return 1; }
  [[ -f "$pf" ]] || return 0
  if ! python3 "$pf" --packet "$packet" --uvo "$uvo" >/dev/null 2>&1; then
    python3 "$pf" --packet "$packet" --uvo "$uvo" --json 2>&1 | head -20 >&2 || true
    echo "review-chain: packet preflight failed (PKT-01..04)" >&2
    return 1
  fi
  return 0
}

_run_kernel_review() {
  python3 "$KERNEL_CLI" run --task-dir "$REPO_TASK_DIR" --mode "$MODE" \
    ${STATE_FILE:+--state-file "$STATE_FILE"} \
    ${PROJECT_ROOT:+--project-root "$PROJECT_ROOT"}
}

export GOAL_REVIEW_DETECT_CACHE="${GOAL_REVIEW_DETECT_CACHE:-$(mktemp -t goal-review-detect.XXXXXX.json)}"
trap 'rm -f "${GOAL_REVIEW_DETECT_CACHE:-}"' EXIT

echo "review-chain [1/4] review-channel-guard (artifact_mode=$ARTIFACT_MODE)"
CHANNEL_JSON=$(python3 "$GUARD" --resolve --provider "" --model "" --force-det 0 --mode "$MODE" --format json 2>/dev/null || echo '{"has_candidates":false}')
HAS_CH=$(echo "$CHANNEL_JSON" | python3 -c "import json,sys; print('1' if json.load(sys.stdin).get('has_candidates') else '0')" 2>/dev/null || echo 0)
UNREACH=$(echo "$CHANNEL_JSON" | python3 -c "import json,sys; print('1' if json.load(sys.stdin).get('configured_but_unreachable') else '0')" 2>/dev/null || echo 0)

if [[ "${GOAL_REVIEW_FORCE_DETERMINISTIC:-}" == "1" ]]; then
  echo "review-chain [2/4] assemble-review-packet (forced deterministic)"
  bash "$ASSEMBLE" "${COMMON_ARGS[@]}"
  assert_review_packet_preflight || exit 1
  python3 "$GUARD" --check --force-det 1 --provider deterministic
  bash "$REVIEW" "${COMMON_ARGS[@]}" --mode goal --provider deterministic
elif [[ "$UNREACH" == "1" ]]; then
  echo "review-chain: WARN — review APIs configured but unreachable" >&2
  bash "$ASSEMBLE" "${COMMON_ARGS[@]}"
  assert_review_packet_preflight || exit 1
  mkdir -p "$GOAL_EVIDENCE_DIR"
  python3 - "$GOAL_EVIDENCE_DIR/review-channel-degraded.json" <<'PY'
import json, sys
from datetime import datetime, timezone
path = sys.argv[1]
open(path, "w", encoding="utf-8").write(json.dumps({
    "separation": "blocked",
    "review_mode": "channel_unreachable",
    "reason": "review_channel_unreachable",
    "suggested_action": "switch_to_cursor_task",
    "checked_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}, ensure_ascii=False, indent=2) + "\n")
PY
  export REVIEW_CHANNEL_UNREACHABLE=1
  export GOAL_REVIEW_CURSOR_TASK_HINT=1
  _run_independent_review "$MODE"
elif [[ "$HAS_CH" != "1" ]]; then
  echo "review-chain: WARN — 0 usable review channels; deterministic_scope_only" >&2
  bash "$ASSEMBLE" "${COMMON_ARGS[@]}"
  assert_review_packet_preflight || exit 1
  mkdir -p "$GOAL_EVIDENCE_DIR"
  python3 - "$GOAL_EVIDENCE_DIR/review-channel-degraded.json" <<'PY'
import json, sys
from datetime import datetime, timezone
path = sys.argv[1]
open(path, "w", encoding="utf-8").write(json.dumps({
    "separation": "degraded",
    "review_mode": "deterministic_scope_only",
    "reason": "zero_usable_review_channels",
    "checked_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}, ensure_ascii=False, indent=2) + "\n")
PY
  export GOAL_REVIEW_FORCE_DETERMINISTIC=1
  bash "$REVIEW" "${COMMON_ARGS[@]}" --mode goal --provider deterministic
elif [[ -f "$KERNEL_CLI" ]]; then
  echo "review-chain [2/4] kernel.review.cli run --mode $MODE"
  _run_kernel_review
  TIMING_SYNC="$(resolve_pipeline_script sync_timing_substeps.py)"
  if [[ -f "$TIMING_SYNC" ]]; then
    SYNC_ARGS=(--task-dir "$REPO_TASK_DIR" --source review)
    [[ -n "$STATE_FILE" ]] && SYNC_ARGS+=(--state-file "$STATE_FILE")
    [[ -n "$PROJECT_ROOT" ]] && SYNC_ARGS+=(--project-root "$PROJECT_ROOT")
    python3 "$TIMING_SYNC" "${SYNC_ARGS[@]}" >/dev/null 2>&1 || true
  fi
  echo "review-chain [4/4] done — run gate --post review next"
  exit 0
else
  bash "$ASSEMBLE" "${COMMON_ARGS[@]}"
  assert_review_packet_preflight || exit 1
  _run_independent_review "$MODE"
fi

UNIFIED_JSON="$GOAL_EVIDENCE_DIR/review-unified.json"
echo "review-chain [3/4] merge-review-issues -> $UNIFIED_JSON"
bash "$MERGE" "${COMMON_ARGS[@]}" --unified-json "$UNIFIED_JSON"

TIMING_SYNC="$(resolve_pipeline_script sync_timing_substeps.py)"
if [[ -f "$TIMING_SYNC" ]]; then
  SYNC_ARGS=(--task-dir "$REPO_TASK_DIR" --source review)
  [[ -n "$STATE_FILE" ]] && SYNC_ARGS+=(--state-file "$STATE_FILE")
  [[ -n "$PROJECT_ROOT" ]] && SYNC_ARGS+=(--project-root "$PROJECT_ROOT")
  python3 "$TIMING_SYNC" "${SYNC_ARGS[@]}" >/dev/null 2>&1 || true
fi

echo "review-chain [4/4] done — run gate --post review next"
exit 0
