#!/usr/bin/env python3
"""assert_plan_before_code — fail-closed plan_code_order guard.

Exit 0: OK (plan gate passed, or no dirty src / write_set paths).
Exit 2: plan_code_order — plan not passed but src (or write_set) has working-tree changes.

Usage:
  assert_plan_before_code.py --task-dir PATH [--project-root PATH] [--state-file PATH]
                             [--mode check|json] [--require-plan-passed]
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def git_root(start: Path) -> Path | None:
    try:
        r = subprocess.run(
            ["git", "-C", str(start), "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if r.returncode == 0 and r.stdout.strip():
            return Path(r.stdout.strip()).resolve()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return None


def current_branch(repo: Path) -> str:
    try:
        r = subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if r.returncode == 0:
            return r.stdout.strip()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return ""


def dirty_paths(repo: Path) -> list[str]:
    """Unstaged + staged + untracked paths relative to repo root."""
    paths: set[str] = set()
    try:
        r = subprocess.run(
            ["git", "-C", str(repo), "-c", "core.quotepath=false", "status", "--porcelain", "-u"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if r.returncode != 0:
            return []
        for line in r.stdout.splitlines():
            if len(line) < 4:
                continue
            # XY PATH or XY ORIG -> PATH
            rest = line[3:]
            if " -> " in rest:
                rest = rest.split(" -> ", 1)[1]
            paths.add(rest.strip().strip('"'))
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return []
    return sorted(paths)


def resolve_paths(task_dir: str, state_file: str = "", project_root: str = "") -> dict:
    script_dir = Path(__file__).resolve().parent
    resolver = script_dir / "resolve-artifact-paths.py"
    if not resolver.is_file():
        return {
            "repo_task_dir": str(Path(task_dir).resolve()),
            "handoff_dir": str(Path(task_dir).resolve() / "handoff"),
            "project_root": project_root or "",
        }
    args = [sys.executable, str(resolver), "--task-dir", task_dir, "--format", "json"]
    if state_file:
        args.extend(["--state-file", state_file])
    if project_root:
        args.extend(["--project-root", project_root])
    r = subprocess.run(args, capture_output=True, text=True, check=True)
    return json.loads(r.stdout)


def plan_gate_passed(plan_path: Path) -> bool:
    if not plan_path.is_file():
        return False
    try:
        plan = json.loads(plan_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return False
    gate = plan.get("gate") or {}
    if gate.get("passed_at") and gate.get("post_exit_code", 0) == 0:
        return True
    # legacy: any passed_at is enough
    return bool(gate.get("passed_at"))


def path_matches_guard(path: str, write_set: list[str]) -> bool:
    norm = path.replace("\\", "/").lstrip("./")
    if norm.startswith("src/") or "/src/" in f"/{norm}":
        return True
    for ws in write_set:
        w = (ws or "").replace("\\", "/").strip().rstrip("*").rstrip("/")
        if not w or w.startswith("docs/"):
            continue
        # treat write_set entries under src or common app roots as guarded
        if w.startswith("src/") or w.endswith(".ts") or w.endswith(".tsx") or w.endswith(".js") or w.endswith(".jsx"):
            if norm == w or norm.startswith(w.rstrip("/") + "/") or w.startswith(norm):
                return True
        if norm.startswith(w + "/") or norm == w:
            # only guard non-docs write_set
            if not w.startswith("docs/"):
                return True
    return False


def evaluate(
    task_dir: str,
    state_file: str = "",
    project_root: str = "",
    require_plan_passed: bool = False,
) -> dict:
    paths = resolve_paths(task_dir, state_file, project_root)
    repo_task = Path(paths["repo_task_dir"])
    handoff = Path(paths["handoff_dir"])
    # Prefer gate-passed plan: check resolved handoff then repo-local handoff
    # (avoids stale ~/.goal-state/runtime/<task>/handoff winning over fresh repo plan).
    candidates = [handoff / "plan.json", repo_task / "handoff" / "plan.json"]
    plan_path = candidates[0]
    for cand in candidates:
        if plan_gate_passed(cand):
            plan_path = cand
            break
        if cand.is_file() and not plan_path.is_file():
            plan_path = cand
    proj = Path(project_root).resolve() if project_root else Path(paths.get("project_root") or "") or git_root(repo_task)
    if proj is None:
        proj = git_root(repo_task)
    write_set: list[str] = []
    if plan_path.is_file():
        try:
            write_set = list(json.loads(plan_path.read_text(encoding="utf-8")).get("write_set") or [])
        except (json.JSONDecodeError, OSError):
            write_set = []

    passed = plan_gate_passed(plan_path)
    dirty: list[str] = []
    guarded_dirty: list[str] = []
    if proj and proj.is_dir():
        dirty = dirty_paths(proj)
        guarded_dirty = [p for p in dirty if path_matches_guard(p, write_set)]

    violation = False
    reason = ""
    if not passed:
        if require_plan_passed:
            violation = True
            reason = "plan_gate_missing"
        elif guarded_dirty:
            violation = True
            reason = "plan_code_order"

    return {
        "ok": not violation,
        "failure_code": reason if violation else "",
        "plan_gate_passed": passed,
        "plan_json": str(plan_path),
        "project_root": str(proj) if proj else "",
        "dirty_count": len(dirty),
        "guarded_dirty": guarded_dirty[:50],
        "write_set": write_set,
        "checked_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "message": (
            "plan_code_order: plan gate not passed but working tree has src/write_set changes — "
            "complete gate --post plan first (or stash/reset guarded paths)"
            if violation and reason == "plan_code_order"
            else (
                "plan_gate_missing: handoff/plan.json gate.passed_at required"
                if violation
                else "ok"
            )
        ),
        "recommended_fix_command": (
            "gate-guazi-flow-stage.sh --stage plan --post --mode guazi --task-dir TASK "
            "--state-file STATE --project-root ROOT"
            if violation
            else ""
        ),
    }


def main() -> None:
    ap = argparse.ArgumentParser(description="Fail-closed plan-before-code guard")
    ap.add_argument("--task-dir", required=True)
    ap.add_argument("--project-root", default="")
    ap.add_argument("--state-file", default="")
    ap.add_argument("--mode", choices=("check", "json"), default="check")
    ap.add_argument(
        "--require-plan-passed",
        action="store_true",
        help="Fail when plan handoff gate missing even if working tree is clean",
    )
    args = ap.parse_args()
    result = evaluate(
        args.task_dir,
        state_file=args.state_file,
        project_root=args.project_root,
        require_plan_passed=args.require_plan_passed,
    )
    if args.mode == "json":
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        if result["ok"]:
            print("assert-plan-before-code: OK")
        else:
            print(f"assert-plan-before-code: BLOCKED ({result['failure_code']})", file=sys.stderr)
            print(result["message"], file=sys.stderr)
            if result.get("guarded_dirty"):
                print("guarded_dirty:", ", ".join(result["guarded_dirty"][:20]), file=sys.stderr)
    sys.exit(0 if result["ok"] else 2)


if __name__ == "__main__":
    main()
