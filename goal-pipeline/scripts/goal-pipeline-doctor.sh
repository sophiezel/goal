#!/bin/bash
# goal-pipeline-doctor.sh — Pipeline infra diagnostics + artifact migration
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/source-goal-install-paths.sh"
_goal_install_paths
GOAL_STATE_HOME="$GOAL_STATE_HOME"
REPO_DIR="$GOAL_PIPELINE_REPO"
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

# Kernel package (deployed beside scripts under GOAL_STATE_HOME)
kernel_init = goal_home / "kernel" / "__init__.py"
status("kernel_package", kernel_init.is_file(), str(kernel_init))

status("install_layout.repository", (repo / ".git").exists(), str(repo))
status("install_layout.state_runtime", (goal_home / "scripts").is_dir(), str(goal_home))
if version_file.is_file() and kernel_init.is_file():
    try:
        v = json.loads(version_file.read_text())
        installed_kh = v.get("kernel_tree_hash", "")
        if installed_kh:
            h = hashlib.sha256()
            kroot = goal_home / "kernel"
            for p in sorted(kroot.rglob("*")):
                if not p.is_file() or "__pycache__" in p.parts or p.suffix == ".pyc":
                    continue
                h.update(p.relative_to(kroot).as_posix().encode())
                h.update(p.read_bytes())
            current_kh = h.hexdigest()[:16]
            drift_k = installed_kh != current_kh
            status("version_kernel_tree_hash", not drift_k,
                   f"installed={installed_kh} current={current_kh} kernel_version={v.get('kernel_version','?')}")
        else:
            status("version_kernel_tree_hash", True, "no kernel_tree_hash in VERSION (legacy manifest)")
    except Exception as e:
        status("version_kernel_tree_hash", False, str(e))
elif not kernel_init.is_file():
    status("version_kernel_tree_hash", False, "kernel/__init__.py missing")

# Install channel / update hints
install_cfg = {}
if config_file.is_file():
    try:
        install_cfg = json.loads(config_file.read_text(encoding="utf-8")).get("install") or {}
    except Exception:
        install_cfg = {}
inst_ch = install_cfg.get("channel") or "stable"
if (repo / ".git").is_dir():
    try:
        desc = subprocess.run(
            ["git", "-C", str(repo), "describe", "--tags", "--always"],
            capture_output=True, text=True, timeout=10,
        )
        describe = (desc.stdout or "").strip() or "?"
        status(
            "install_channel",
            True,
            f"channel={inst_ch} ref={install_cfg.get('ref') or ''} describe={describe}",
        )
        lib = goal_home / "scripts" / "goal-install-lib.sh"
        if not lib.is_file():
            lib = repo / "goal-pipeline" / "scripts" / "goal-install-lib.sh"
        if lib.is_file() and inst_ch == "stable":
            r = subprocess.run(
                [
                    "bash", "-c",
                    f"source '{lib}'; _goal_list_remote_tags '' '{repo}' | _goal_semver_pick_stable_tag",
                ],
                capture_output=True, text=True, timeout=60,
            )
            remote_stable = (r.stdout or "").strip()
            current_tag = subprocess.run(
                ["git", "-C", str(repo), "describe", "--tags", "--exact-match"],
                capture_output=True, text=True, timeout=5,
            )
            cur = (current_tag.stdout or "").strip()
            if remote_stable and cur and remote_stable != cur:
                status(
                    "install_stable_update_available",
                    False,
                    f"current={cur} remote_stable={remote_stable} — run goal-install.sh --update",
                )
            else:
                status("install_stable_update_available", True, remote_stable or cur or "n/a")
        if inst_ch == "latest":
            subprocess.run(
                ["git", "-C", str(repo), "fetch", "origin", "main", "--quiet"],
                timeout=60,
                capture_output=True,
            )
            behind = subprocess.run(
                ["git", "-C", str(repo), "rev-list", "--count", "HEAD..origin/main"],
                capture_output=True, text=True, timeout=10,
            )
            n = (behind.stdout or "0").strip()
            if n.isdigit() and int(n) > 0:
                status(
                    "install_latest_behind_main",
                    False,
                    f"behind origin/main by {n} commits — run goal-install.sh --update",
                )
            else:
                status("install_latest_behind_main", True, "up to date with origin/main")
    except Exception as e:
        status("install_channel", False, str(e)[:200])
else:
    status("install_channel", False, "repository not cloned")

# Artifact path resolver
status("resolve_artifact_paths", resolver.is_file(), str(resolver))

# Required scripts
for s in ("goal-pipeline-kernel.sh", "goal-stage-driver.sh", "gf-stage-driver.sh",
          "goal-run-review-chain.sh",
          "goal-pipeline-recover.sh",
          "gate-guazi-flow-stage.sh", "gate-gf-stage.sh", "goal-pipeline-stop-hook.sh", "resolve-artifact-paths.py",
          "migrate-artifacts.py", "source-artifact-paths.sh",
          "index_contract_hash.py", "refresh-handoffs-after-index.sh",
          "four_planes_doctor.py", "quality_plane_check.py", "data_plane_check.py",
          "efficiency_plane_check.py", "validate-state-path.sh", "assert-plan-before-code.sh",
          "goal-install.sh", "goal-install-lib.sh"):
    p = goal_home / "scripts" / s
    status(f"script_{s}", p.is_file(), str(p))
# Plane refs
for s in ("failure-codes.json", "four-planes-checklist.json", "migration-compat.md", "release-channel.md"):
    p = goal_home / "references" / s
    status(f"ref_{s}", p.is_file(), str(p))

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

# Review channels (config vs reachability split)
detect = Path("${DETECT}")
if detect.is_file():
    try:
        det_env = os.environ.copy()
        det_env["GOAL_STATE_HOME"] = str(goal_home)
        r = subprocess.run(
            [str(detect), "--json", "--no-probe"],
            capture_output=True,
            text=True,
            timeout=30,
            env=det_env,
        )
        d = json.loads(r.stdout or "{}")
        sel = (d.get("selected") or {}).get("provider")
        has_ranked = bool(d.get("ranked"))
        configured = bool(d.get("configured_keys")) or has_ranked
        status(
            "review_channel_configured",
            configured,
            f"configured_keys={d.get('configured_keys', False)} has_candidates={d.get('has_candidates', False)}",
        )
        if d.get("configured_but_unreachable"):
            status("review_channel_reachable", False, "keys configured but unreachable (run with --probe)")
        elif d.get("has_candidates"):
            status("review_channel_reachable", True, f"selected={sel}")
        else:
            status(
                "review_channel_reachable",
                not d.get("configured_keys"),
                "no ranked channel — add api_keys to config.json or env",
            )
        status("review_channels", d.get("has_candidates", False), f"selected={sel or 'none'}")
        only_det = not sel or sel == "deterministic"
        if only_det or not d.get("has_candidates"):
            status("review_unified_ready", False, "no independent channel — configure API key or Ollama")
        else:
            status("review_unified_ready", True, sel)
    except Exception as e:
        status("review_channel_configured", False, str(e))
        status("review_channel_reachable", False, str(e))
        status("review_channels", False, str(e))
else:
    status("review_channel_configured", False, "detect-review-channels missing")
    status("review_channel_reachable", False, "detect-review-channels missing")
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
