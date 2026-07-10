#!/usr/bin/env python3
"""Resolve verification commands for implement-qc-gate (single source of truth)."""
from __future__ import annotations

import fnmatch
import json
import os
import re
import subprocess
from typing import Any


H5_PAGE_PATTERNS = (
    "src/pages/**",
    "src/App.tsx",
    "src/pages/index.ts",
)


def _guazi_flow_core_root() -> str:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    for candidate in (
        os.path.join(script_dir, "..", "..", "guazi-flow-core"),
        os.path.expanduser("~/.agents/skills/guazi-flow-core"),
    ):
        if os.path.isdir(candidate):
            return os.path.abspath(candidate)
    return ""


def _load_profile_verification(profile_id: str = "h5") -> dict[str, Any]:
    root = _guazi_flow_core_root()
    if not root:
        return {}
    path = os.path.join(root, "profiles", profile_id, "profile.default.json")
    if not os.path.isfile(path):
        return {}
    try:
        data = json.load(open(path, encoding="utf-8"))
        return data.get("implement_post_verification") or {}
    except (OSError, json.JSONDecodeError):
        return {}


def _parse_write_set_from_index(index_path: str) -> list[str]:
    if not os.path.isfile(index_path):
        return []
    text = open(index_path, encoding="utf-8").read()
    m = re.search(
        r"(?:##\s*(?:write_set|写集|范围与写集)|write_set\s*[:：])\s*\n([\s\S]*?)(?:\n##|\Z)",
        text,
        re.I,
    )
    if not m:
        return []
    paths: list[str] = []
    for line in m.group(1).splitlines():
        s = line.strip()
        if s.startswith("- "):
            s = s[2:].strip()
        s = s.strip("`").strip()
        if s.startswith("src/") or s.startswith("docs/"):
            paths.append(s)
    return paths


def _handoff_dir(task_dir: str) -> str:
    env = os.environ.get("GOAL_HANDOFF_DIR") or os.environ.get("HANDOFF_DIR")
    if env and os.path.isdir(env):
        return env
    return os.path.join(task_dir, "handoff")


def _load_write_set(task_dir: str) -> list[str]:
    handoff = os.path.join(_handoff_dir(task_dir), "plan.json")
    if os.path.isfile(handoff):
        try:
            ws = json.load(open(handoff, encoding="utf-8")).get("write_set") or []
            if ws:
                return [str(p) for p in ws]
        except (OSError, json.JSONDecodeError):
            pass
    return _parse_write_set_from_index(os.path.join(task_dir, "index.md"))


def _load_handoff_commands(task_dir: str) -> list[dict[str, Any]]:
    handoff = os.path.join(_handoff_dir(task_dir), "plan.json")
    if not os.path.isfile(handoff):
        return []
    try:
        raw = json.load(open(handoff, encoding="utf-8")).get("verification_commands") or []
        return [c for c in raw if isinstance(c, dict) and c.get("cmd")]
    except (OSError, json.JSONDecodeError):
        return []


def _git_changed_files(repo_root: str) -> list[str]:
    if not repo_root or not os.path.isdir(os.path.join(repo_root, ".git")):
        return []
    files: list[str] = []
    for args in (
        ["git", "-C", repo_root, "diff", "--name-only", "HEAD"],
        ["git", "-C", repo_root, "diff", "--name-only", "--cached"],
        ["git", "-C", repo_root, "ls-files", "--others", "--exclude-standard"],
    ):
        try:
            r = subprocess.run(args, capture_output=True, text=True, timeout=30)
            if r.returncode == 0 and r.stdout.strip():
                files.extend(line.strip() for line in r.stdout.splitlines() if line.strip())
        except (OSError, subprocess.TimeoutExpired):
            continue
    return list(dict.fromkeys(files))


def _matches_patterns(path: str, patterns: tuple[str, ...] | list[str]) -> bool:
    normalized = path.replace("\\", "/")
    for pattern in patterns:
        if fnmatch.fnmatch(normalized, pattern):
            return True
        # directory glob: src/pages/foo matches src/pages/**
        if pattern.endswith("/**"):
            prefix = pattern[:-3]
            if normalized.startswith(prefix.rstrip("/") + "/") or normalized == prefix.rstrip("/"):
                return True
    return False


def _write_set_touches_pages(write_set: list[str], changed_files: list[str]) -> bool:
    candidates = list(write_set) + list(changed_files)
    return any(_matches_patterns(p, H5_PAGE_PATTERNS) for p in candidates)


def _default_h5_commands(repo_root: str) -> list[dict[str, Any]]:
    pkg = os.path.join(repo_root, "package.json")
    cmds: list[dict[str, Any]] = []
    if os.path.isfile(os.path.join(repo_root, "yarn.lock")):
        cmds.append({"id": "h5-build", "cmd": "CI= yarn build:beta", "required": True, "source": "h5-profile"})
        cmds.append(
            {
                "id": "h5-test",
                "cmd": "CI=true yarn test --watchAll=false",
                "required": True,
                "source": "h5-profile",
            }
        )
    elif os.path.isfile(pkg):
        cmds.append({"id": "h5-test", "cmd": "CI=true npm test -- --watchAll=false", "required": True, "source": "h5-profile"})
    return cmds


def _merge_commands(*groups: list[dict[str, Any]]) -> list[dict[str, Any]]:
    merged: dict[str, dict[str, Any]] = {}
    for group in groups:
        for item in group:
            cmd_id = str(item.get("id") or item.get("cmd"))
            merged[cmd_id] = {
                "id": cmd_id,
                "cmd": str(item["cmd"]),
                "required": bool(item.get("required", True)),
                "source": item.get("source", "unknown"),
            }
    return list(merged.values())


def resolve_verification_commands(
    task_dir: str,
    repo_root: str,
    profile_id: str = "h5",
) -> dict[str, Any]:
    """Merge profile + handoff + write_set/diff heuristics into executable commands."""
    write_set = _load_write_set(task_dir)
    changed_files = _git_changed_files(repo_root)
    candidates = write_set + changed_files
    touches_pages = _write_set_touches_pages(write_set, changed_files)

    profile_cfg = _load_profile_verification(profile_id)
    profile_patterns = tuple(profile_cfg.get("when_write_set_matches") or H5_PAGE_PATTERNS)
    profile_cmds: list[dict[str, Any]] = []
    if touches_pages and any(_matches_patterns(p, profile_patterns) for p in candidates):
        profile_cmds = [
            {**c, "source": "h5-profile"}
            for c in (profile_cfg.get("commands") or _default_h5_commands(repo_root))
            if isinstance(c, dict) and c.get("cmd")
        ]

    handoff_cmds = [{**c, "source": "handoff"} for c in _load_handoff_commands(task_dir)]
    commands = _merge_commands(profile_cmds, handoff_cmds)

    return {
        "commands": commands,
        "write_set": write_set,
        "changed_files": changed_files,
        "touches_pages": touches_pages,
        "profile_id": profile_id,
    }


if __name__ == "__main__":
    import argparse

    p = argparse.ArgumentParser()
    p.add_argument("--task-dir", required=True)
    p.add_argument("--repo-root", default=".")
    p.add_argument("--profile", default="h5")
    p.add_argument("--json", action="store_true")
    args = p.parse_args()
    repo = os.path.abspath(args.repo_root or os.getcwd())
    result = resolve_verification_commands(args.task_dir, repo, args.profile)
    print(json.dumps(result, ensure_ascii=False, indent=2))
