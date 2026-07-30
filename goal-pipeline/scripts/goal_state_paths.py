#!/usr/bin/env python3
"""Canonical GOAL_HOME / GOAL_STATE_HOME / config.json resolution (SSOT)."""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


def goal_home() -> Path:
    raw = os.environ.get("GOAL_HOME", "").strip()
    if raw:
        return Path(raw).expanduser().resolve()
    return (Path.home() / ".goal-pipeline").resolve()


def state_home() -> Path:
    raw = os.environ.get("GOAL_STATE_HOME", "").strip()
    if raw:
        return Path(raw).expanduser().resolve()
    return (goal_home() / "state").resolve()


def pipeline_repo() -> Path:
    raw = os.environ.get("GOAL_PIPELINE_REPO", "").strip()
    if raw:
        return Path(raw).expanduser().resolve()
    return (goal_home() / "repository").resolve()


def config_path() -> Path:
    return state_home() / "config.json"


def runtime_env_snapshot() -> dict[str, str]:
    return {
        "goal_home": str(goal_home()),
        "state_home": str(state_home()),
        "pipeline_repo": str(pipeline_repo()),
        "captured_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


def apply_runtime_env_from_state(state: dict) -> None:
    """Set GOAL_* env only when not already set (bootstrap for Agent shells)."""
    re = state.get("runtime_env")
    if not isinstance(re, dict):
        return
    if not os.environ.get("GOAL_STATE_HOME") and re.get("state_home"):
        os.environ["GOAL_STATE_HOME"] = str(re["state_home"])
    if not os.environ.get("GOAL_HOME") and re.get("goal_home"):
        os.environ["GOAL_HOME"] = str(re["goal_home"])
    if not os.environ.get("GOAL_PIPELINE_REPO") and re.get("pipeline_repo"):
        os.environ["GOAL_PIPELINE_REPO"] = str(re["pipeline_repo"])


def apply_state_file(path: str | Path) -> None:
    p = Path(path).expanduser()
    if not p.is_file():
        return
    try:
        state = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return
    apply_runtime_env_from_state(state)


def shell_exports_from_state_file(path: str | Path) -> str:
    apply_state_file(path)
    gh, sh, pr = goal_home(), state_home(), pipeline_repo()
    lines = [
        f'export GOAL_HOME="{gh}"',
        f'export GOAL_STATE_HOME="{sh}"',
        f'export GOAL_PIPELINE_REPO="{pr}"',
    ]
    return "\n".join(lines)


def main() -> int:
    import argparse

    ap = argparse.ArgumentParser(description="Resolve goal install paths (SSOT)")
    ap.add_argument("--apply-state-file", metavar="PATH", help="Print shell exports after applying runtime_env from state")
    ap.add_argument("--json", action="store_true", help="Print paths as JSON")
    args = ap.parse_args()
    if args.apply_state_file:
        print(shell_exports_from_state_file(args.apply_state_file))
        return 0
    if args.json:
        print(json.dumps(runtime_env_snapshot(), indent=2))
        return 0
    print(config_path())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
