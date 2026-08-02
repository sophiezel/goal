#!/usr/bin/env bash
# goal-pipeline-kernel — Single public control-plane CLI for guazi-flow-goal
# Facade over driver / gate / advance / doctor. See docs/architecture/goal-runtime.md
#
# Usage:
#   goal-pipeline-kernel init   --project-root R --task-dir T [--branch B] [--goal-id ID]
#   goal-pipeline-kernel next   --state-file S --task-dir T --project-root R [--attempt-stage ST] [--format json|text]
#   goal-pipeline-kernel gate   --state-file S --task-dir T --project-root R --stage ST [--pre|--post] [--mode guazi|degraded]
#   goal-pipeline-kernel status --state-file S --task-dir T --project-root R
#   goal-pipeline-kernel doctor --project-root R [--task-dir T] [--state-file S]
#   goal-pipeline-kernel complete --state-file S --task-dir T --project-root R
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOAL_STATE_HOME="${GOAL_STATE_HOME:-${GOAL_HOME:-$HOME/.goal-pipeline}/state}"

resolve_bin() {
  local name="$1"
  local p="$GOAL_STATE_HOME/scripts/$name"
  [[ -f "$p" ]] || p="$SCRIPT_DIR/$name"
  echo "$p"
}

DRIVER="$(resolve_bin goal-stage-driver.sh)"
GATE="$(resolve_bin gate-goal-stage.sh)"
[[ -f "$GATE" ]] || GATE="$(resolve_bin gate-guazi-flow-stage.sh)"
ADVANCE="$(resolve_bin goal-advance-stage.sh)"
DOCTOR="$(resolve_bin goal-pipeline-doctor.sh)"
ASSERT="$(resolve_bin assert-plan-before-code.sh)"
VALIDATE_STATE="$(resolve_bin validate-state-path.sh)"

CMD="${1:-}"
[[ -n "$CMD" ]] || { echo "Usage: $0 init|next|gate|status|doctor|complete ..." >&2; exit 2; }
shift || true

STATE_FILE=""
TASK_DIR=""
PROJECT_ROOT=""
ATTEMPT_STAGE=""
FORMAT="json"
STAGE=""
PHASE="post"
MODE="guazi"
BRANCH=""
GOAL_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --attempt-stage) ATTEMPT_STAGE="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    --stage) STAGE="$2"; shift 2 ;;
    --pre) PHASE="pre"; shift ;;
    --post) PHASE="post"; shift ;;
    --mode) MODE="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --goal-id) GOAL_ID="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,14p' "$0" | tr -d '#'
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

abs() {
  local p="$1" base="${2:-.}"
  if [[ "$p" != /* ]]; then p="$base/$p"; fi
  local dir base_name
  dir="$(cd "$(dirname "$p")" && pwd)"
  base_name="$(basename "$p")"
  echo "${dir}/${base_name}"
}

case "$CMD" in
  init)
    [[ -n "$PROJECT_ROOT" && -n "$TASK_DIR" ]] || {
      echo "kernel init: --project-root and --task-dir required" >&2
      exit 2
    }
    # Canonicalize with Path.resolve() (same as resolve-artifact-paths.project_id)
    # so macOS /var vs /private/var cannot split state SSOT.
    eval "$(python3 - "$PROJECT_ROOT" "$TASK_DIR" <<'PY'
import os, sys
from pathlib import Path
root = Path(sys.argv[1]).resolve()
task = Path(sys.argv[2])
if not task.is_absolute():
    task = (root / task).resolve()
else:
    task = task.resolve()
task.mkdir(parents=True, exist_ok=True)
rel = os.path.relpath(str(task), str(root)).replace("\\", "/")
import hashlib
pid = hashlib.sha256(str(root).encode()).hexdigest()[:12]
def sh(s):
    return "'" + s.replace("'", "'\"'\"'") + "'"
print(f"PROJECT_ROOT={sh(str(root))}")
print(f"TASK_DIR={sh(str(task))}")
print(f"PID={sh(pid)}")
print(f"REL={sh(rel)}")
PY
)"
    BRANCH="${BRANCH:-$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"
    GOAL_ID="${GOAL_ID:-$(basename "$TASK_DIR")}"
    STATE_DIR="$GOAL_STATE_HOME/projects/$PID/$BRANCH/$(basename "$TASK_DIR")"
    mkdir -p "$STATE_DIR/artifacts/handoff" "$STATE_DIR/artifacts/evidence"
    STATE_FILE="$STATE_DIR/state.json"
    if [[ -f "$STATE_FILE" ]]; then
      echo "{\"ok\":true,\"action\":\"exists\",\"state_file\":\"$STATE_FILE\",\"project_id\":\"$PID\"}"
      exit 0
    fi
    python3 - "$STATE_FILE" "$PID" "$PROJECT_ROOT" "$BRANCH" "$GOAL_ID" "$REL" "$SCRIPT_DIR" <<'PY'
import json, sys
from datetime import datetime, timezone
path, pid, root, branch, goal_id, rel = sys.argv[1:7]
sys.path.insert(0, sys.argv[7])
from atomic_json import write_state_atomic
doc = {
  "schema_version": 1,
  "goal_id": goal_id,
  "project_id": pid,
  "project_root": root,
  "branch": branch,
  "status": "active",
  "current_stage": "plan",
  "pipeline_track": "compatibility",
  "guazi_flow_available": True,
  "guazi_flow_task": rel,
  "guazi_flow_stages": {},
  "artifact_layout": {
    "mode": "split",
    "runtime_root": str(__import__("pathlib").Path(path).parent / "artifacts"),
    "repo_task_dir": rel,
  },
  "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
  "kernel": {"entrypoint": "goal-pipeline-kernel", "protocol_version": 1},
}
write_state_atomic(path, doc)
print(json.dumps({"ok": True, "action": "created", "state_file": path, "project_id": pid}, ensure_ascii=False))
PY
    ;;

  next)
    [[ -n "$STATE_FILE" && -n "$TASK_DIR" && -n "$PROJECT_ROOT" ]] || {
      echo "kernel next: --state-file --task-dir --project-root required" >&2
      exit 2
    }
    PROJECT_ROOT="$(python3 -c "from pathlib import Path; print(Path('$PROJECT_ROOT').resolve())")"
    if [[ -f "$VALIDATE_STATE" && -f "$STATE_FILE" ]]; then
      bash "$VALIDATE_STATE" --state-file "$STATE_FILE" --project-root "$PROJECT_ROOT" --format json >/dev/null \
        || { echo '{"ok":false,"failure_code":"project_id_mismatch","plane":"data"}' >&2; exit 2; }
    fi
    ARGS=(--state-file "$STATE_FILE" --task-dir "$TASK_DIR" --project-root "$PROJECT_ROOT" --format "$FORMAT")
    [[ -n "$ATTEMPT_STAGE" ]] && ARGS+=(--attempt-stage "$ATTEMPT_STAGE")
    OUT=$(GOAL_KERNEL_INTERNAL=1 "$DRIVER" "${ARGS[@]}") || RC=$?
    RC=${RC:-0}
    # Enrich work_order with kernel envelope + capability
    export OUT STATE_FILE TASK_DIR PROJECT_ROOT ASSERT SCRIPT_DIR
    python3 <<'PY'
import json, os, subprocess
wo = json.loads(os.environ["OUT"])
stage = wo.get("next_stage") or ""
capability = {
  "plan": {"allowed_write_globs": ["docs/guazi-flow/**"], "deny_write_globs": ["src/**"], "code_writes_allowed": False},
  "implement": {"allowed_write_globs": ["$write_set"], "deny_write_globs": [], "code_writes_allowed": True},
  "quality": {"allowed_write_globs": ["docs/guazi-flow/**/evidence/**", "docs/guazi-flow/**/smoke.json"], "code_writes_allowed": False},
  "runtime_smoke": {"allowed_write_globs": ["docs/guazi-flow/**/evidence/**"], "code_writes_allowed": False},
  "review": {"allowed_write_globs": ["docs/guazi-flow/**/evidence/**"], "deny_write_globs": ["src/**"], "code_writes_allowed": False},
  "complete": {"allowed_write_globs": ["docs/guazi-flow/**"], "code_writes_allowed": False},
}
cap = capability.get(stage, {"code_writes_allowed": False})
# Harden: if plan stage, never claim code writes
if stage == "plan":
    wo["code_writes_allowed"] = False
    # strip any mandatory that looks like implement skill load for writing
elif stage in ("blocked",) or wo.get("blocked"):
    wo["code_writes_allowed"] = False
else:
    wo.setdefault("code_writes_allowed", cap.get("code_writes_allowed", False))

wo["kernel"] = {
  "schema_version": 1,
  "entrypoint": "goal-pipeline-kernel",
  "protocol": "next → execute work_order → gate",
  "plane": "control",
  "host_guard": os.environ.get("GOAL_HOST_GUARD", "off"),
  "deprecated_direct_scripts": [
    "goal-stage-driver.sh",
    "gate-guazi-flow-stage.sh",
    "goal-advance-stage.sh",
  ],
}
wo["capability"] = cap
wo["planes"] = ["control", "data", "quality", "efficiency"]
# Control invariant: plan without gate → assert not dirty if we can
assert_sh = os.environ.get("ASSERT") or ""
if stage == "plan" and assert_sh and os.path.isfile(assert_sh):
    try:
        r = subprocess.run(
            ["bash", assert_sh, "--task-dir", os.environ["TASK_DIR"],
             "--project-root", os.environ["PROJECT_ROOT"],
             "--state-file", os.environ["STATE_FILE"], "--mode", "json"],
            capture_output=True, text=True, timeout=60,
        )
        if r.returncode == 2:
            try:
                ad = json.loads(r.stdout or "{}")
            except json.JSONDecodeError:
                ad = {}
            wo["blocked"] = True
            wo["blocked_reason"] = ad.get("failure_code") or "plan_code_order"
            wo["code_writes_allowed"] = False
            wo["failure_code"] = wo["blocked_reason"]
            wo["mandatory_commands"] = [
                "stash or reset guarded src/write_set diffs",
                "complete guazi-flow-plan contract only under docs/guazi-flow/**",
                "goal-pipeline-kernel gate --stage plan --post ...",
            ]
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        pass
print(json.dumps(wo, ensure_ascii=False, indent=2))
PY
    exit "$RC"
    ;;

  gate)
    [[ -n "$STATE_FILE" && -n "$TASK_DIR" && -n "$PROJECT_ROOT" && -n "$STAGE" ]] || {
      echo "kernel gate: --state-file --task-dir --project-root --stage required" >&2
      exit 2
    }
    exec bash "$GATE" \
      --task-dir "$TASK_DIR" \
      --stage "$STAGE" \
      --"$PHASE" \
      --mode "$MODE" \
      --state-file "$STATE_FILE" \
      --project-root "$PROJECT_ROOT"
    ;;

  status)
    [[ -n "$STATE_FILE" && -n "$TASK_DIR" && -n "$PROJECT_ROOT" ]] || {
      echo "kernel status: --state-file --task-dir --project-root required" >&2
      exit 2
    }
    ADV=$("$ADVANCE" --state-file "$STATE_FILE" --task-dir "$TASK_DIR" --project-root "$PROJECT_ROOT" --format json 2>/dev/null) || true
    python3 - "$STATE_FILE" "$ADV" <<'PY'
import json, sys
from pathlib import Path
st = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")) if Path(sys.argv[1]).is_file() else {}
try:
    adv = json.loads(sys.argv[2] or "{}")
except json.JSONDecodeError:
    adv = {}
print(json.dumps({
    "kernel": "goal-pipeline-kernel",
    "status": st.get("status"),
    "current_stage": st.get("current_stage"),
    "project_id": st.get("project_id"),
    "branch": st.get("branch"),
    "failure_code": st.get("failure_code"),
    "next_stage": adv.get("next_stage"),
    "blocked": adv.get("blocked"),
    "host_guard": __import__("os").environ.get("GOAL_HOST_GUARD", "off"),
    "planes": ["control", "data", "quality", "efficiency"],
}, ensure_ascii=False, indent=2))
PY
    ;;

  doctor)
    [[ -n "$PROJECT_ROOT" ]] || PROJECT_ROOT="$(pwd)"
    if [[ -f "$DOCTOR" ]]; then
      bash "$DOCTOR" "$PROJECT_ROOT" 2>/dev/null || true
    fi
    python3 "$SCRIPT_DIR/four_planes_doctor.py" \
      --project-root "$PROJECT_ROOT" \
      ${STATE_FILE:+--state-file "$STATE_FILE"} \
      ${TASK_DIR:+--task-dir "$TASK_DIR"} \
      --format json
    # Optional per-plane deep checks when paths provided
    if [[ -n "$TASK_DIR" && -n "$PROJECT_ROOT" ]]; then
      python3 "$SCRIPT_DIR/data_plane_check.py" --task-dir "$TASK_DIR" --project-root "$PROJECT_ROOT" ${STATE_FILE:+--state-file "$STATE_FILE"} --format json || true
      python3 "$SCRIPT_DIR/efficiency_plane_check.py" ${TASK_DIR:+--task-dir "$TASK_DIR"} --format json || true
    fi
    ;;

  complete)
    [[ -n "$STATE_FILE" && -n "$TASK_DIR" && -n "$PROJECT_ROOT" ]] || {
      echo "kernel complete: --state-file --task-dir --project-root required" >&2
      exit 2
    }
    # Block degraded-as-pass silent
    python3 "$SCRIPT_DIR/quality_plane_check.py" \
      --task-dir "$TASK_DIR" \
      --state-file "$STATE_FILE" \
      --project-root "$PROJECT_ROOT" \
      --mode complete || exit $?
    exec bash "$GATE" --assert-complete \
      --state-file "$STATE_FILE" \
      --task-dir "$TASK_DIR" \
      --project-root "$PROJECT_ROOT"
    ;;

  *)
    echo "Unknown command: $CMD (want init|next|gate|status|doctor|complete)" >&2
    exit 2
    ;;
esac
