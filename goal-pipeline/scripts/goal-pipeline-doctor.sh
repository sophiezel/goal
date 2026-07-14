#!/bin/bash
# goal-pipeline-doctor.sh — Pipeline infra diagnostics + artifact migration
set -euo pipefail

GOAL_STATE_HOME="${GOAL_STATE_HOME:-$HOME/.goal-state}"
REPO_DIR="${GOAL_PIPELINE_REPO:-$HOME/.goal-pipeline-repo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT=""
MIGRATE=false
PURGE_REPO=false
MIGRATE_TASK_DIR=""
MIGRATE_STATE_FILE=""
MIGRATE_DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --migrate-artifacts) MIGRATE=true; shift ;;
    --purge-repo-tier-r) PURGE_REPO=true; shift ;;
    --task-dir) MIGRATE_TASK_DIR="$2"; shift 2 ;;
    --state-file) MIGRATE_STATE_FILE="$2"; shift 2 ;;
    --dry-run) MIGRATE_DRY_RUN=true; shift ;;
    -h|--help)
      echo "Usage: $0 [PROJECT_ROOT]"
      echo "       $0 --migrate-artifacts --task-dir PATH [--state-file PATH] [--dry-run]"
      echo "       $0 --purge-repo-tier-r --task-dir PATH [--state-file PATH] [--project-root PATH]"
      exit 0
      ;;
    *)
      PROJECT_ROOT="$1"
      shift
      ;;
  esac
done

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

SYNC="${GOAL_STATE_HOME}/scripts/sync-install-repo.sh"
if [[ -x "$SYNC" ]]; then
  bash "$SYNC" --quiet >/dev/null 2>&1 || true
fi

if [[ "$PURGE_REPO" == "true" ]]; then
  [[ -n "$MIGRATE_TASK_DIR" ]] || { echo "purge requires --task-dir" >&2; exit 2; }
  RESOLVER="$SCRIPT_DIR/resolve-artifact-paths.py"
  [[ -f "$RESOLVER" ]] || RESOLVER="$GOAL_STATE_HOME/scripts/resolve-artifact-paths.py"
  PURGE_ARGS=(--task-dir "$MIGRATE_TASK_DIR" --purge-repo-tier-r)
  [[ -n "$MIGRATE_STATE_FILE" ]] && PURGE_ARGS+=(--state-file "$MIGRATE_STATE_FILE")
  [[ -n "$PROJECT_ROOT" ]] && PURGE_ARGS+=(--project-root "$PROJECT_ROOT")
  python3 "$RESOLVER" "${PURGE_ARGS[@]}"
  exit 0
fi

if [[ "$MIGRATE" == "true" ]]; then
  [[ -n "$MIGRATE_TASK_DIR" ]] || { echo "migrate requires --task-dir" >&2; exit 2; }
  MIGRATE_SCRIPT="$SCRIPT_DIR/migrate-artifacts.py"
  [[ -f "$MIGRATE_SCRIPT" ]] || MIGRATE_SCRIPT="$GOAL_STATE_HOME/scripts/migrate-artifacts.py"
  ARGS=(--task-dir "$MIGRATE_TASK_DIR")
  [[ -n "$MIGRATE_STATE_FILE" ]] && ARGS+=(--state-file "$MIGRATE_STATE_FILE")
  [[ "$MIGRATE_DRY_RUN" == "true" ]] && ARGS+=(--dry-run)
  python3 "$MIGRATE_SCRIPT" "${ARGS[@]}"
  exit 0
fi

GATE_REPO="$REPO_DIR/goal-pipeline/scripts/gate-guazi-flow-stage.sh"
GATE_INST="$GOAL_STATE_HOME/scripts/gate-guazi-flow-stage.sh"
VERSION_FILE="$GOAL_STATE_HOME/VERSION"
CONFIG_FILE="$GOAL_STATE_HOME/config.json"
HOOKS_JSON="$HOME/.cursor/hooks.json"
DETECT="$GOAL_STATE_HOME/scripts/detect-review-channels"
DRIVER="$GOAL_STATE_HOME/scripts/goal-stage-driver.sh"
RESOLVER="$GOAL_STATE_HOME/scripts/resolve-artifact-paths.py"

python3 << PY
import json, os, hashlib, subprocess
from pathlib import Path

project_root = Path("${PROJECT_ROOT}").resolve()
goal_home = Path("${GOAL_STATE_HOME}")
repo = Path("${REPO_DIR}").resolve()
config_file = Path("${CONFIG_FILE}")
version_file = Path("${VERSION_FILE}")
hooks_json = Path("${HOOKS_JSON}")
gate_repo = Path("${GATE_REPO}")
gate_inst = Path("${GATE_INST}")
resolver = Path("${RESOLVER}")

checks = []

MANAGED_SKILLS = ("goal-pipeline", "guazi-flow-goal")
DUPLICATE_ONLY_DIRS = [
    Path.home() / ".cursor" / "skills",
    Path.home() / ".pi" / "skills",
    Path.home() / ".pi" / "agent" / "skills",
]

def status(name, ok, detail=""):
    checks.append({"check": name, "status": "ok" if ok else "fail", "detail": detail})

def resolve_dev_repo():
    if not config_file.is_file():
        return None
    try:
        cfg = json.loads(config_file.read_text(encoding="utf-8"))
    except Exception:
        return None
    for key in ("dev_repo", "goal_dev_repo"):
        val = cfg.get(key) or (cfg.get("goal") or {}).get(key.replace("goal_", ""))
        if isinstance(val, str) and val.strip():
            p = Path(val).expanduser().resolve()
            if p.is_dir() and (p / ".git").is_dir() and p != repo:
                return p
    return None

def skill_link_target(skills_dir: Path, name: str):
    link = skills_dir / name
    if not link.exists() and not link.is_symlink():
        return None
    try:
        return link.resolve()
    except Exception:
        return None

dev_repo = resolve_dev_repo()

for skill in MANAGED_SKILLS:
    ut = skill_link_target(Path.home() / ".agents" / "skills", skill)
    if ut is None:
        status(f"skill_symlink_{skill}_universal", False, "missing ~/.agents/skills/" + skill)
    else:
        ok = str(ut).startswith(str(repo) + os.sep) or ut == repo
        if dev_repo and (str(ut).startswith(str(dev_repo) + os.sep) or ut == dev_repo):
            ok = False
        status(f"skill_symlink_{skill}_universal", ok, str(ut))

    for dup_dir in DUPLICATE_ONLY_DIRS:
        try:
            if dup_dir.resolve() == (Path.home() / ".agents" / "skills").resolve():
                continue
        except Exception:
            pass
        dt = skill_link_target(dup_dir, skill)
        if dt is not None:
            status(
                f"skill_symlink_{skill}_duplicate",
                False,
                f"remove duplicate {dup_dir / skill} -> {dt}",
            )

# VERSION drift
if version_file.is_file() and gate_repo.is_file():
    try:
        v = json.loads(version_file.read_text())
        installed_hash = v.get("gate_script_hash", "")
        current_hash = hashlib.sha256(gate_repo.read_bytes()).hexdigest()[:16]
        drift = installed_hash != current_hash
        status("version_gate_hash", not drift,
               f"installed={installed_hash} repo={current_hash} git_rev={v.get('git_rev','?')}")
    except Exception as e:
        status("version_gate_hash", False, str(e))
else:
    status("version_gate_hash", False, "VERSION or gate script missing")

# Artifact path resolver
status("resolve_artifact_paths", resolver.is_file(), str(resolver))

# Required scripts
for s in ("goal-stage-driver.sh", "goal-run-review-chain.sh", "goal-pipeline-recover.sh",
          "gate-guazi-flow-stage.sh", "goal-pipeline-stop-hook.sh", "resolve-artifact-paths.py",
          "migrate-artifacts.py", "source-artifact-paths.sh",
          "index_contract_hash.py", "refresh-handoffs-after-index.sh"):
    p = goal_home / "scripts" / s
    status(f"script_{s}", p.is_file(), str(p))

# hooks.json stop hook + loop_limit
if hooks_json.is_file():
    try:
        h = json.loads(hooks_json.read_text())
        stop = (h.get("hooks") or {}).get("stop") or []
        hook = next((x for x in stop if "goal-pipeline-stop-hook" in x.get("command","")), None)
        if hook:
            ll = hook.get("loop_limit", 0)
            status("stop_hook", True, f"loop_limit={ll}")
            status("stop_hook_loop_limit", ll >= 10, f"loop_limit={ll} (recommend >=10)")
        else:
            status("stop_hook", False, "not in hooks.json")
    except Exception as e:
        status("stop_hook", False, str(e))
else:
    status("stop_hook", False, "hooks.json missing")

# Review channels
detect = Path("${DETECT}")
if detect.is_file():
    try:
        r = subprocess.run([str(detect), "--json"], capture_output=True, text=True, timeout=15)
        d = json.loads(r.stdout or "{}")
        sel = (d.get("selected") or {}).get("provider", "deterministic")
        only_det = sel == "deterministic"
        status("review_channels", True, f"selected={sel}")
        if only_det:
            status("review_unified_ready", False, "only deterministic — configure API key or Ollama; review-chain will degrade (skip L2)")
        else:
            status("review_unified_ready", True, sel)
    except Exception as e:
        status("review_channels", False, str(e))
else:
    status("review_channels", False, "detect-review-channels missing")

# plan_code_order hard guard + state validator
scripts_dir = goal_home / "scripts"
assert_pbc = scripts_dir / "assert-plan-before-code.sh"
if not assert_pbc.is_file():
    assert_pbc = repo / "goal-pipeline" / "scripts" / "assert-plan-before-code.sh"
status("plan_before_code_guard", assert_pbc.is_file(), str(assert_pbc) if assert_pbc.is_file() else "assert-plan-before-code.sh missing")
vsp = scripts_dir / "validate-state-path.sh"
if not vsp.is_file():
    vsp = repo / "goal-pipeline" / "scripts" / "validate-state-path.sh"
status("validate_state_path", vsp.is_file(), str(vsp) if vsp.is_file() else "validate-state-path.sh missing")
timing_py = scripts_dir / "record-pipeline-timing.py"
if not timing_py.is_file():
    timing_py = repo / "goal-pipeline" / "scripts" / "record-pipeline-timing.py"
status("pipeline_timing", timing_py.is_file(), "UTC pipeline-timing recorder")

# Active goal + driver snapshot
states_dir = goal_home / "projects"
active = []
if states_dir.is_dir():
    for sf in states_dir.rglob("state.json"):
        try:
            st = json.loads(sf.read_text())
            if st.get("status") in ("active", "blocked"):
                root = st.get("project_root") or ""
                if root and Path(root).resolve() == project_root:
                    layout = st.get("artifact_layout") or {}
                    active.append({"state_file": str(sf), "task": st.get("guazi_flow_task",""),
                                   "current_stage": st.get("current_stage",""),
                                   "artifact_mode": layout.get("mode", "repo_full"),
                                   "artifact_layout": layout})
        except Exception:
            pass

status("active_goals", True, json.dumps(active, ensure_ascii=False) if active else "none")

# Freshness playbook for active goals
hash_py = goal_home / "scripts" / "index_contract_hash.py"
refresh_sh = goal_home / "scripts" / "refresh-handoffs-after-index.sh"
for ag in active[:3]:
    sf = Path(ag["state_file"])
    try:
        layout = ag.get("artifact_layout") or {}
        repo_task = layout.get("repo_task_dir") or ""
        runtime = layout.get("runtime_root") or ""
        if not repo_task:
            continue
        idx = Path(repo_task) / "index.md"
        plan_json = Path(runtime) / "handoff" / "plan.json" if runtime else Path(repo_task) / "handoff" / "plan.json"
        packet = Path(runtime) / "handoff" / "review-packet.json" if runtime else Path(repo_task) / "handoff" / "review-packet.json"
        playbook = []
        if hash_py.is_file() and idx.is_file() and plan_json.is_file():
            r = subprocess.run(
                ["python3", str(hash_py), "--json", str(idx), str(plan_json)],
                capture_output=True, text=True, timeout=15,
            )
            if r.returncode == 0 and r.stdout.strip():
                fresh = json.loads(r.stdout)
                if fresh.get("contract_changed"):
                    playbook.append({
                        "diag": "plan_handoff_stale",
                        "cause": "index contract sections changed",
                        "fix": f"{refresh_sh} --task-dir {repo_task} --state-file {sf} --cascade plan",
                        "NOT": "append-only execution record is NOT mini-replan",
                    })
                elif fresh.get("execution_changed"):
                    playbook.append({
                        "diag": "plan_handoff_stale_execution",
                        "cause": "index execution record changed (contract unchanged)",
                        "fix": f"{refresh_sh} --task-dir {repo_task} --state-file {sf} --cascade implement",
                        "NOT": "mini-replan unless contract_hash changed",
                    })
        if ag.get("current_stage") in ("review", "complete") and not packet.is_file():
            playbook.append({
                "diag": "review_packet_missing",
                "fix": f"{refresh_sh} --task-dir {repo_task} --state-file {sf} --cascade packet",
            })
        if playbook:
            status(f"freshness_{Path(ag.get('task') or 'task').name}", False, json.dumps(playbook, ensure_ascii=False))
        else:
            status(f"freshness_{Path(ag.get('task') or 'task').name}", True, "fresh or N/A")
    except Exception as e:
        status("freshness_check", False, str(e)[:200])

for ag in active[:1]:
    driver = Path("${DRIVER}")
    if driver.is_file() and ag.get("task"):
        try:
            r = subprocess.run([
                str(driver), "--state-file", ag["state_file"],
                "--task-dir", ag["task"], "--project-root", str(project_root), "--format", "json"
            ], capture_output=True, text=True, timeout=20)
            wo = json.loads(r.stdout) if r.returncode == 0 else {}
            status("stage_driver_snapshot", True,
                   f"next_stage={wo.get('next_stage')} blocked={wo.get('blocked')}")
        except Exception as e:
            status("stage_driver_snapshot", False, str(e))

fails = [c for c in checks if c["status"] != "ok"]
report = {
    "schema_version": 1,
    "project_root": str(project_root),
    "conclusion": "可继续" if not fails else ("可继续但有 warning" if len(fails) < 3 else "需修复"),
    "checks": checks,
    "fail_count": len(fails),
}
print(json.dumps(report, ensure_ascii=False, indent=2))
PY
