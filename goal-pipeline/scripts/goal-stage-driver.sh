#!/bin/bash
# goal-stage-driver.sh — Single work order for goal-pipeline Agent turns
set -euo pipefail

_gf_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_self="${BASH_SOURCE[0]}"
while [[ -L "$_self" ]]; do
  _link_dir="$(cd "$(dirname "$_self")" && pwd)"
  _self="$(readlink "$_self")"
  [[ "$_self" != /* ]] && _self="${_link_dir}/${_self}"
done
SCRIPT_DIR="$(cd "$(dirname "$_self")" && pwd)"
GOAL_STATE_HOME="${GOAL_STATE_HOME:-${GOAL_HOME:-$HOME/.goal-pipeline}/state}"
ADVANCE="$GOAL_STATE_HOME/scripts/goal-advance-stage.sh"
[[ -x "$ADVANCE" ]] || ADVANCE="$SCRIPT_DIR/goal-advance-stage.sh"
GATE="$GOAL_STATE_HOME/scripts/gate-goal-stage.sh"
[[ -x "$GATE" ]] || GATE="$SCRIPT_DIR/gate-goal-stage.sh"

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

# Compat window: prefer goal-pipeline-kernel next (Wave 5 deprecate warn)
if [[ "${GOAL_KERNEL_COMPAT_WARN:-1}" != "0" && "${GOAL_KERNEL_INTERNAL:-0}" != "1" ]]; then
  echo "DEPRECATED: call goal-pipeline-kernel next (driver is Kernel-internal). Set GOAL_KERNEL_COMPAT_WARN=0 to silence." >&2
fi

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
    "plan": "goal-plan",
    "implement": "goal-implement",
    "quality": "goal-quality",
    "runtime_smoke": "goal-quality",
    "review": "goal-review",
    "postmerge": "goal-postmerge",
    "complete": "goal-complete",
}

STAGE_PROGRESS_FALLBACK = {
    "postmerge": "[postmerge] delivery",
    "done": "[done] complete",
}

def load_stage_graph_doc():
    import sys as _sys
    gp_root = os.path.normpath(os.path.join(script_dir, ".."))
    if gp_root not in _sys.path:
        _sys.path.insert(0, gp_root)
    from kernel.profile.stage_graph import load_stage_graph, progress_for_stage

    plan_path = os.path.join(task_dir, "handoff", "plan.json")
    plan_doc = None
    if os.path.isfile(plan_path):
        with open(plan_path, encoding="utf-8") as f:
            plan_doc = json.load(f)
    graph_doc = load_stage_graph(plan_json=plan_doc)
    return graph_doc, progress_for_stage

stage_graph_doc, progress_for_stage_fn = load_stage_graph_doc()

def stage_progress_label(stage):
    if stage in STAGE_PROGRESS_FALLBACK:
        return STAGE_PROGRESS_FALLBACK[stage]
    return progress_for_stage_fn(stage, stage_graph_doc)

def gate_cmd(stage, phase):
    return (
        f"{gate} --task-dir {task_dir!r} --stage {stage} --{phase} "
        f"--state-file {state_file!r} --project-root {project_root!r}"
    )

# Review single-track (B8): default single — goal-review only.
def load_review_track():
    import subprocess, sys as _sys
    try:
        rt_script = os.path.join(script_dir, "review_track.py")
        if os.path.isfile(rt_script):
            out = subprocess.check_output(
                [_sys.executable, rt_script, "--state-file", state_file, "--format", "json"],
                text=True,
            )
            return json.loads(out).get("track", "single")
    except Exception:
        pass
    return "single"

review_track = load_review_track()

def build_mandatory(stage):
    plan_skill = STAGE_SKILL.get("plan", "goal-plan")
    impl_skill = STAGE_SKILL.get("implement", "goal-implement")
    assert_pbc = (
        f"bash {script_dir}/assert-plan-before-code.sh --task-dir {task_dir!r} "
        f"--project-root {project_root!r} --state-file {state_file!r} --mode json"
    )
    if stage == "plan":
        return [
            gate_cmd("plan", "pre"),
            assert_pbc + "  # must stay OK — NEVER write src/ until gate --post plan",
            f"Load {plan_skill}/SKILL.md and execute full plan flow (docs/contracts only)",
            "HARD: do NOT create Todo items that write src/** until plan gate passes",
            "HARD: write_set bullets = pure paths only; put exclusions/不做项 in a separate section (not mixed into write_set list)",
            gate_cmd("plan", "post"),
            f"{script_dir}/goal-advance-stage.sh --state-file {state_file!r} --task-dir {task_dir!r} --project-root {project_root!r}",
        ]
    if stage == "implement":
        return [
            gate_cmd("implement", "pre"),
            f"Load {impl_skill}/SKILL.md and implement within write_set",
            "HARD: ship acceptance-matrix RTL/unit tests (Cxx/Vxx) with feature code in the same commit when possible — avoid review round-trip for missing C01–C10 coverage",
            "(optional Dev Loop) findRelatedTests / scoped unit tests only — DO NOT run yarn build:beta locally (UVO once at gate --post; efficiency: never duplicate full build in Dev Loop)",
            gate_cmd("implement", "post"),
            f"{script_dir}/goal-advance-stage.sh --state-file {state_file!r} --task-dir {task_dir!r} --project-root {project_root!r}",
        ]
    if stage in ("quality", "runtime_smoke"):
        return [
            f"{script_dir}/runtime-smoke.sh --repo-root {project_root!r} --task-dir {task_dir!r} "
            f"--state-file {state_file!r} --project-root {project_root!r} "
            f"(skip if verification-oracle.json smoke_required=false)",
            gate_cmd("quality", "post"),
            f"{script_dir}/goal-advance-stage.sh --state-file {state_file!r} --task-dir {task_dir!r} --project-root {project_root!r}",
        ]
    if stage == "review":
        review_chain = f"{script_dir}/goal-run-review-chain.sh"
        refresh = f"{script_dir}/refresh-handoffs-after-index.sh"
        cmds = [
            # Refresh handoffs if index execution/contract drifted (no-op when fresh)
            f"{refresh} --task-dir {task_dir!r} --state-file {state_file!r} --project-root {project_root!r}",
            gate_cmd("review", "pre"),
            f"{review_chain} --task-dir {task_dir!r} --state-file {state_file!r} --project-root {project_root!r}",
            gate_cmd("review", "post"),
            f"{script_dir}/goal-advance-stage.sh --state-file {state_file!r} --task-dir {task_dir!r} --project-root {project_root!r}",
        ]
        if review_track == "single":
            cmds.insert(2, "# single-track: load goal-review/SKILL.md; rubric embedded in review-packet via assemble-review-packet.sh")
        return cmds
    if stage == "postmerge":
        return [
            "# postmerge_policy=required — review pass → postmerge → complete",
            "Load project postmerge skill",
            "Write evidence/postmerge.md (stage=postmerge, result=pass, review_subject_hash fresh)",
            f"{script_dir}/goal-advance-stage.sh --state-file {state_file!r} --task-dir {task_dir!r} --project-root {project_root!r}",
        ]
    if stage == "complete":
        complete_skill = STAGE_SKILL.get("complete", "goal-complete")
        return [
            gate_cmd("complete", "pre"),
            f"Load {complete_skill}/SKILL.md",
            gate_cmd("complete", "post"),
            f"{gate} --assert-complete --state-file {state_file!r} --task-dir {task_dir!r} --project-root {project_root!r}",
        ]
    if stage == "done":
        return [f"{gate} --assert-complete --state-file {state_file!r} --task-dir {task_dir!r} --project-root {project_root!r}"]
    return list(required) if required else [f"goal-advance-stage reported next_stage={stage}"]

wrong_stage = False
if attempt and next_stage not in ("done", "blocked") and attempt != next_stage:
    aliases = {("runtime_smoke", "smoke"), ("smoke", "runtime_smoke"), ("runtime_smoke", "quality"), ("quality", "runtime_smoke")}
    if (attempt, next_stage) not in aliases and (next_stage, attempt) not in aliases:
        wrong_stage = True
        blocked_reason = blocked_reason or "wrong_stage"

mandatory = build_mandatory(next_stage) if next_stage != "done" else build_mandatory("done")

fe_argus_plan_post = {"required": False, "skill": None}
skills_to_load: list[str] = []
if next_stage == "plan":
    pol = os.path.join(script_dir, "argus_plan_post_policy.py")
    if os.path.isfile(pol):
        import subprocess
        import sys as _sys

        try:
            tr = json.loads(
                subprocess.check_output(
                    [_sys.executable, pol, "--resolve-from-task-dir", "--task-dir", task_dir],
                    text=True,
                    timeout=30,
                )
            )
            required = bool(tr.get("fe_argus_skill_required"))
            handoff_dir = os.path.join(task_dir, "handoff")
            block = json.loads(
                subprocess.check_output(
                    [
                        _sys.executable,
                        pol,
                        "--work-order-json",
                        "--task-dir",
                        task_dir,
                        "--handoff-dir",
                        handoff_dir,
                        "--script-dir",
                        script_dir,
                    ],
                    text=True,
                    timeout=30,
                )
            )
            fe_argus_plan_post = block.get("fe_argus_plan_post") or fe_argus_plan_post
            suffix = block.get("argus_mandatory_suffix") or []
            if required and suffix:
                injected: list[str] = []
                for c in mandatory:
                    injected.append(c)
                    if "--stage plan" in c and "--post" in c:
                        injected.extend(suffix)
                mandatory = injected
                skills_to_load = list(block.get("skills_to_load") or [])
        except (subprocess.CalledProcessError, json.JSONDecodeError, OSError):
            pass

# Review single-track: skill_to_load=goal-review (skip guazi-flow-review Agent turn)
resolved_skill = STAGE_SKILL.get(next_stage)
if next_stage == "review" and review_track == "single":
    resolved_skill = "goal-review"

engineering_pack_doc = {
    "engineering_pack": "none",
    "source": "profile:default",
    "skills_to_load": [],
    "skill_paths": [],
}
if next_stage == "plan":
    plan_path_ep = os.path.join(task_dir, "handoff", "plan.json")
    plan_doc_ep = None
    if os.path.isfile(plan_path_ep):
        with open(plan_path_ep, encoding="utf-8") as f:
            plan_doc_ep = json.load(f)
    from kernel.profile.engineering_pack import merge_plan_phase_skills, resolve_engineering_pack

    engineering_pack_doc = resolve_engineering_pack(plan_json=plan_doc_ep)

primary_skills: list[str] = []
if resolved_skill:
    primary_skills.append(resolved_skill)
if next_stage == "plan":
    primary_skills = merge_plan_phase_skills(resolved_skill, engineering_pack_doc)
    if engineering_pack_doc.get("engineering_pack") not in (None, "none"):
        pack = engineering_pack_doc["engineering_pack"]
        paths = ", ".join(engineering_pack_doc.get("skill_paths") or [])
        mandatory.insert(
            2,
            f"# engineering_pack={pack}: soft-load {paths} (R1/R2 enhance only; PQ/plan gate unchanged)",
        )
for s in skills_to_load:
    if s and s not in primary_skills:
        primary_skills.append(s)

stage_node = None
for _n in stage_graph_doc.get("stage_graph") or []:
    if _n.get("id") == next_stage or (next_stage in ("runtime_smoke", "smoke") and _n.get("id") == "quality"):
        stage_node = _n
        break

work_order = {
    "schema_version": 1,
    "pipeline_profile": stage_graph_doc.get("profile_id"),
    "stage_graph_source": stage_graph_doc.get("source"),
    "stage_graph_ids": [n.get("id") for n in stage_graph_doc.get("stage_graph") or []],
    "stage_meta": stage_node,
    "next_stage": next_stage,
    "blocked": blocked or wrong_stage,
    "blocked_reason": blocked_reason,
    "wrong_stage": wrong_stage,
    "skill_to_load": resolved_skill,
    "skills_to_load": primary_skills,
    "fe_argus_plan_post": fe_argus_plan_post,
    "review_track": review_track,
    "engineering_pack": engineering_pack_doc.get("engineering_pack"),
    "engineering_pack_source": engineering_pack_doc.get("source"),
    "engineering_skill_paths": engineering_pack_doc.get("skill_paths") or [],
    "progress": stage_progress_label(next_stage),
    "mandatory_commands": mandatory,
    "required_commands_from_advance": required,
    "never": [
        "询问用户是否继续 review",
        "在未读 evidence/review-fix-input.json 时修复 review 问题",
        "在未读 evidence/<stage>-gate-fix-input.json 时修复 plan/implement gate 失败",
        "gate 失败时由 Judge 会话直接改 index.md 或 diff（须读 fix-input 后由 Executor 修）",
        "gate --post 未 exit 0 时输出阶段 ✅",
        "plan post 触发 fe-argus 时跳过 fe-argus INDEX merge（须 merge manifest 且 argus_enrich_status≠rule_only）",
        "手写 handoff/*.json",
        "在 gate --post plan 之前写 src/** 或 write_set 业务代码（failure_code: plan_code_order）",
        "将 plan Todo 与 implement/写代码 Todo 并列；仅 [1/5] plan ✅ 后才可新增写代码 Todo",
        "blocked(noop_fix) 后原命令盲重试——必须先实质性改产物",
        "implement 期连跑全量 yarn build:beta（留给 UVO 一次）",
        "写集 bullet 混入排除/不做项/散文（exclusions 须单独 section）",
        "验收矩阵 C01–C10 有行为却不补 RTL/单测，留到 review 第一轮才补",
        "把 review_undetermined / ADP-ERR / 网络超时当业务缺陷去改 write_set（应 switch_to_cursor_task / fix_channel）",
    ],
    "plan_before_code": True,
    "code_writes_allowed": next_stage in ("implement", "quality", "runtime_smoke", "review", "postmerge", "complete", "done")
        and not (blocked or wrong_stage)
        and next_stage != "plan",
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
