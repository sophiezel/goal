#!/usr/bin/env python3
"""SSOT handoff + Tier-R path resolution for gate consumers (split / repo_full).

Resolution order (see goal-pipeline/references/handoff-path-resolution.md):
  1. GOAL_HANDOFF_DIR or HANDOFF_DIR when the directory exists
  2. resolve-artifact-paths.py handoff_dir (artifact_layout / GOAL_STATE_FILE)
  3. <task_dir>/handoff (repo_full legacy)
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


def _script_dir() -> Path:
    return Path(__file__).resolve().parent


def _effective_project_root(task_dir: str, project_root: str) -> str:
    td = os.path.abspath(task_dir)
    pr = (project_root or os.environ.get("GOAL_REPO_ROOT") or "").strip()
    if pr and os.path.abspath(pr) != td:
        return pr
    try:
        import subprocess
        from pathlib import Path

        r = subprocess.run(
            ["git", "-C", td, "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        if r.returncode == 0 and r.stdout.strip():
            return str(Path(r.stdout.strip()).resolve())
    except (OSError, subprocess.TimeoutExpired):
        pass
    return pr or td


def resolve_artifact_paths(
    task_dir: str,
    state_file: str = "",
    project_root: str = "",
) -> dict[str, Any]:
    """Run resolve-artifact-paths.py; return {} on failure."""
    resolver = _script_dir() / "resolve-artifact-paths.py"
    if not resolver.is_file():
        return {}
    sf = (state_file or os.environ.get("GOAL_STATE_FILE") or "").strip()
    pr = _effective_project_root(task_dir, project_root)
    args = [sys.executable, str(resolver), "--task-dir", task_dir, "--format", "json"]
    if sf:
        args.extend(["--state-file", sf])
    if pr:
        args.extend(["--project-root", pr])
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=30, check=False)
        if r.returncode != 0 or not (r.stdout or "").strip():
            return {}
        return json.loads(r.stdout)
    except (json.JSONDecodeError, OSError, subprocess.TimeoutExpired):
        return {}


def _handoff_dir_usable(handoff_dir: str) -> bool:
    if not handoff_dir or not os.path.isdir(handoff_dir):
        return False
    if os.path.isfile(os.path.join(handoff_dir, "plan.json")):
        return True
    try:
        return any(Path(handoff_dir).glob("*.json"))
    except OSError:
        return False


def resolve_handoff_dir(
    task_dir: str,
    state_file: str = "",
    project_root: str = "",
) -> str:
    env = (os.environ.get("GOAL_HANDOFF_DIR") or os.environ.get("HANDOFF_DIR") or "").strip()
    if env and os.path.isdir(env):
        return env

    paths = resolve_artifact_paths(task_dir, state_file=state_file, project_root=project_root)
    ho = (paths.get("handoff_dir") or "").strip()
    if ho and _handoff_dir_usable(ho):
        return ho

    return os.path.join(os.path.abspath(task_dir), "handoff")


def resolve_plan_json_path(
    task_dir: str,
    handoff_dir: str = "",
    state_file: str = "",
    project_root: str = "",
) -> str:
    if handoff_dir and os.path.isdir(handoff_dir):
        return os.path.join(handoff_dir, "plan.json")
    return os.path.join(resolve_handoff_dir(task_dir, state_file, project_root), "plan.json")


def goal_evidence_dir(
    task_dir: str,
    state_file: str = "",
    project_root: str = "",
) -> str:
    env = (os.environ.get("GOAL_EVIDENCE_DIR") or "").strip()
    if env and os.path.isdir(env):
        return env
    paths = resolve_artifact_paths(task_dir, state_file=state_file, project_root=project_root)
    ge = (paths.get("goal_evidence_dir") or "").strip()
    if ge:
        return ge
    return os.path.join(os.path.abspath(task_dir), "evidence")
