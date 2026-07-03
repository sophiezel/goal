#!/bin/bash
# goal-pipeline-doctor.sh — Pipeline infra diagnostics (VERSION drift, hooks, channels, active goal)
set -euo pipefail

GOAL_STATE_HOME="${GOAL_STATE_HOME:-$HOME/.goal-state}"
REPO_DIR="${GOAL_PIPELINE_REPO:-$HOME/.goal-pipeline-repo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${1:-$(pwd)}"

GATE_REPO="$REPO_DIR/goal-pipeline/scripts/gate-guazi-flow-stage.sh"
GATE_INST="$GOAL_STATE_HOME/scripts/gate-guazi-flow-stage.sh"
VERSION_FILE="$GOAL_STATE_HOME/VERSION"
HOOKS_JSON="$HOME/.cursor/hooks.json"
DETECT="$GOAL_STATE_HOME/scripts/detect-review-channels"
DRIVER="$GOAL_STATE_HOME/scripts/goal-stage-driver.sh"

python3 << PY
import json, os, hashlib, subprocess
from pathlib import Path

project_root = Path("${PROJECT_ROOT}").resolve()
goal_home = Path("${GOAL_STATE_HOME}")
repo = Path("${REPO_DIR}")
version_file = Path("${VERSION_FILE}")
hooks_json = Path("${HOOKS_JSON}")
gate_repo = Path("${GATE_REPO}")
gate_inst = Path("${GATE_INST}")

checks = []

def status(name, ok, detail=""):
    checks.append({"check": name, "status": "ok" if ok else "fail", "detail": detail})

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

# Required scripts
for s in ("goal-stage-driver.sh", "goal-run-review-chain.sh", "goal-pipeline-recover.sh",
          "gate-guazi-flow-stage.sh", "goal-pipeline-stop-hook.sh"):
    p = goal_home / "scripts" / s
    status(f"script_{s}", p.is_file() and os.access(p, os.X_OK), str(p))

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
            status("review_dual_ready", False, "only deterministic — configure API key or Ollama")
        else:
            status("review_dual_ready", True, sel)
    except Exception as e:
        status("review_channels", False, str(e))
else:
    status("review_channels", False, "detect-review-channels missing")

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
                    active.append({"state_file": str(sf), "task": st.get("guazi_flow_task",""),
                                   "current_stage": st.get("current_stage","")})
        except Exception:
            pass

status("active_goals", True, json.dumps(active, ensure_ascii=False) if active else "none")
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
