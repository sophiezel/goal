#!/usr/bin/env python3
"""check_commit_before_review — enforce write_set committed before review (v3 §8.3b).

Fails when any path in plan.json.write_set is dirty (uncommitted) at review --pre.
failure_code: uncommitted_write_set
GOAL_SKIP_COMMIT_BEFORE_REVIEW=1 bypasses (local only, never in CI).
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys


def _git_porcelain(repo_root: str) -> list[str]:
    try:
        out = subprocess.check_output(
            ["git", "-C", repo_root, "status", "--porcelain", "--untracked-files=all"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError):
        return []
    dirty = []
    for line in out.splitlines():
        if not line.strip():
            continue
        # porcelain format: XY <path>  (X=staged, Y=worktree)
        path = line[3:].strip()
        # rename: "R  old -> new" → take new
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
        dirty.append(path.strip('"'))
    return dirty


def _load_write_set(task_dir: str, handoff_dir: str) -> list[str]:
    plan_json = os.path.join(handoff_dir, "plan.json")
    if not os.path.isfile(plan_json):
        return []
    try:
        return list(json.load(open(plan_json, encoding="utf-8")).get("write_set") or [])
    except (OSError, json.JSONDecodeError):
        return []


def check(repo_root: str, write_set: list[str]) -> dict:
    if not write_set:
        return {"ok": True, "dirty": [], "reason": "empty_write_set"}
    dirty = set(_git_porcelain(repo_root))
    dirty_in_ws = sorted({p for p in dirty for ws in write_set if p == ws or p.startswith(ws.rstrip("/") + "/") or ws.rstrip("/") == p})
    return {"ok": len(dirty_in_ws) == 0, "dirty": dirty_in_ws, "checked": write_set}


def main() -> int:
    p = argparse.ArgumentParser(description="Check write_set committed before review")
    p.add_argument("--repo-root", required=True)
    p.add_argument("--task-dir", required=True)
    p.add_argument("--handoff-dir", default="")
    p.add_argument("--json", action="store_true", dest="as_json")
    args = p.parse_args()

    if os.environ.get("GOAL_SKIP_COMMIT_BEFORE_REVIEW") == "1":
        if args.as_json:
            print(json.dumps({"ok": True, "skipped": True, "reason": "GOAL_SKIP_COMMIT_BEFORE_REVIEW=1"}))
        else:
            print("SKIP: GOAL_SKIP_COMMIT_BEFORE_REVIEW=1")
        return 0

    handoff_dir = args.handoff_dir or os.path.join(args.task_dir, "handoff")
    write_set = _load_write_set(args.task_dir, handoff_dir)
    result = check(args.repo_root, write_set)

    if args.as_json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        if result["ok"]:
            print("OK: write_set committed")
        else:
            print("FAIL: uncommitted write_set paths: %s" % ", ".join(result["dirty"]))
            print("failure_code: uncommitted_write_set")
            print("fix: commit write_set changes before review, or set GOAL_SKIP_COMMIT_BEFORE_REVIEW=1 (local only)")
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
