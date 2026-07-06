#!/bin/bash
# goal-stage-driver.sh — Single work order for guazi-flow-goal Agent turns
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOAL_STATE_HOME="${GOAL_STATE_HOME:-$HOME/.goal-state}"
ADVANCE="$GOAL_STATE_HOME/scripts/goal-advance-stage.sh"
[[ -x "$ADVANCE" ]] || ADVANCE="$SCRIPT_DIR/goal-advance-stage.sh"
GATE="$GOAL_STATE_HOME/scripts/gate-guazi-flow-stage.sh"
[[ -x "$GATE" ]] || GATE="$SCRIPT_DIR/gate-guazi-flow-stage.sh"

STATE_FILE=""
TASK_DIR=""
PROJECT_ROOT=""
ATTEMPT_STAGE=""
FORMAT="json"

usage() {
  echo "Usage: $0 --state-file <path> --task-dir <path> --project-root <path> [--attempt-stage STAGE] [--format json|text]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --attempt-stage) ATTEMPT_STAGE="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$STATE_FILE" && -n "$TASK_DIR" && -n "$PROJECT_ROOT" ]] || usage

if [[ "$STATE_FILE" != /* ]]; then STATE_FILE="$(cd "$(dirname "$STATE_FILE")" && pwd)/$(basename "$STATE_FILE")"; fi
if [[ "$TASK_DIR" != /* ]]; then TASK_DIR="$PROJECT_ROOT/$TASK_DIR"; fi
TASK_DIR="$(cd "$TASK_DIR" 2>/dev/null && pwd)" || { echo '{"error":"task_dir not found"}' >&2; exit 2; }
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

ADV_OUT=$("$ADVANCE" --state-file "$STATE_FILE" --task-dir "$TASK_DIR" --project-root "$PROJECT_ROOT" --format json 2>/dev/null) || ADV_RC=$?
ADV_RC=${ADV_RC:-0}

export ADV_OUT TASK_DIR PROJECT_ROOT STATE_FILE ATTEMPT_STAGE GATE SCRIPT_DIR FORMAT
python3 << 'PY'
import json, os

adv = json.loads(os.environ["ADV_OUT"])
next_stage = adv.get("next_stage", "unknown")
blocked = bool(adv.get("blocked"))
blocked_reason = adv.get("blocked_reason")
required = adv.get("required_commands") or []

task_dir = os.environ["TASK_DIR"]
project_root = os.environ["PROJECT_ROOT"]
state_file = os.environ["STATE_FILE"]
attempt = os.environ.get("ATTEMPT_STAGE", "")
gate = os.environ["GATE"]
script_dir = os.environ["SCRIPT_DIR"]

STAGE_SKILL = {
    "plan": "guazi-flow-plan",
    "implement": "guazi-flow-implement",
    "runtime_smoke": None,
    "review": "guazi-flow-review",
    "complete": "guazi-flow-complete",
}

STAGE_PROGRESS = {
    "plan": "[1/5] guazi-flow-plan",
    "implement": "[2/5] guazi-flow-implement",
    "runtime_smoke": "[3/5] runtime_smoke",
    "review": "[4/5] review",
    "complete": "[5/5] guazi-flow-complete",
    "done": "[5/5] complete",
}

def gate_cmd(stage, phase):
    return (
        f"{gate} --task-dir {task_dir!r} --stage {stage} --{phase} "
        f"--mode guazi --state-file {state_file!r} --project-root {project_root!r}"
    )

def build_mandatory(stage):
    if stage == "plan":
        return [
            gate_cmd("plan", "pre"),
            "Load guazi-flow-plan/SKILL.md and execute full 9-step plan flow",
            gate_cmd("plan", "post"),
            f"{script_dir}/validate-pipeline-chain.sh --task-dir {task_dir!r} --state-file {state_file!r}",
            f"{script_dir}/goal-advance-stage.sh --state-file {state_file!r} --task-dir {task_dir!r} --project-root {project_root!r}",
        ]
    if stage == "implement":
        return [
            gate_cmd("implement", "pre"),
            "Load guazi-flow-implement/SKILL.md and implement within write_set",
            "CI=true yarn test --watchAll=false (or project equivalent)",
            gate_cmd("implement", "post"),
            f"{script_dir}/validate-pipeline-chain.sh --task-dir {task_dir!r} --state-file {state_file!r}",
            f"{script_dir}/goal-advance-stage.sh --state-file {state_file!r} --task-dir {task_dir!r} --project-root {project_root!r}",
        ]
    if stage == "runtime_smoke":
        return [
            f"{script_dir}/runtime-smoke.sh --repo-root {project_root!r} --task-dir {task_dir!r}",
            gate_cmd("smoke", "post"),
            f"{script_dir}/goal-advance-stage.sh --state-file {state_file!r} --task-dir {task_dir!r} --project-root {project_root!r}",
        ]
    if stage == "review":
        review_chain = f"{script_dir}/goal-run-review-chain.sh"
        return [
            gate_cmd("review", "pre"),
            f"{review_chain} --task-dir {task_dir!r} --state-file {state_file!r} --project-root {project_root!r}",
            gate_cmd("review", "post"),
            f"{script_dir}/goal-advance-stage.sh --state-file {state_file!r} --task-dir {task_dir!r} --project-root {project_root!r}",
        ]
    if stage == "complete":
        return [
            gate_cmd("complete", "pre"),
            "Load guazi-flow-complete/SKILL.md",
            gate_cmd("complete", "post"),
            f"{gate} --assert-complete --state-file {state_file!r} --task-dir {task_dir!r} --project-root {project_root!r}",
        ]
    if stage == "done":
        return [f"{gate} --assert-complete --state-file {state_file!r} --task-dir {task_dir!r} --project-root {project_root!r}"]
    return list(required) if required else [f"goal-advance-stage reported next_stage={stage}"]

wrong_stage = False
if attempt and next_stage not in ("done", "blocked") and attempt != next_stage:
    aliases = {("runtime_smoke", "smoke"), ("smoke", "runtime_smoke")}
    if (attempt, next_stage) not in aliases and (next_stage, attempt) not in aliases:
        wrong_stage = True
        blocked_reason = blocked_reason or "wrong_stage"

mandatory = build_mandatory(next_stage) if next_stage != "done" else build_mandatory("done")

work_order = {
    "schema_version": 1,
    "next_stage": next_stage,
    "blocked": blocked or wrong_stage,
    "blocked_reason": blocked_reason,
    "wrong_stage": wrong_stage,
    "skill_to_load": STAGE_SKILL.get(next_stage),
    "progress": STAGE_PROGRESS.get(next_stage, f"[?] {next_stage}"),
    "mandatory_commands": mandatory,
    "required_commands_from_advance": required,
    "never": [
        "询问用户是否继续 review",
        "在未读 evidence/review-fix-input.json 时修复 review 问题",
        "在未读 evidence/<stage>-gate-fix-input.json 时修复 plan/implement gate 失败",
        "gate 失败时由 Judge 会话直接改 index.md 或 diff（须读 fix-input 后由 Executor 修）",
        "gate --post 未 exit 0 时输出阶段 ✅",
        "手写 handoff/*.json",
    ],
    "turn_exit_condition": (
        f"{gate} --assert-complete --state-file {state_file!r} "
        f"--task-dir {task_dir!r} --project-root {project_root!r} exit 0"
    ),
}

fmt = os.environ.get("FORMAT", "json")
if fmt == "text":
    print(f"next_stage={work_order['next_stage']}")
    print(f"progress={work_order['progress']}")
    if work_order["skill_to_load"]:
        print(f"skill_to_load={work_order['skill_to_load']}")
    for i, c in enumerate(work_order["mandatory_commands"][:6], 1):
        print(f"cmd_{i}={c}")
else:
    print(json.dumps(work_order, ensure_ascii=False, indent=2))
PY
