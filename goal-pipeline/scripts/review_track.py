#!/usr/bin/env python3
"""Resolve review track — goal-pipeline is single-track only (v1.4)."""
from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any


def _load_state(state_file: str) -> dict[str, Any]:
    if not state_file or not os.path.isfile(state_file):
        return {}
    try:
        return json.load(open(state_file, encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def _load_task_tier(state: dict[str, Any], plan_json: str) -> str:
    tier = str(state.get("task_tier") or "").upper()
    if tier:
        return tier
    if plan_json and os.path.isfile(plan_json):
        try:
            return str(json.load(open(plan_json, encoding="utf-8")).get("task_tier") or "").upper()
        except (OSError, json.JSONDecodeError):
            pass
    return ""


def resolve_review_track(
    task_tier: str = "",
    *,
    env_track: str = "",
    state: dict[str, Any] | None = None,
    auto_resolve_xs_s: bool = False,
) -> tuple[str, dict[str, Any]]:
    _ = (task_tier, env_track, state, auto_resolve_xs_s)
    return "single", {"reason": "goal_v14_single_only"}


def wrapper_profile_for_track(track: str) -> str:
    return "goal-review"


def persist_review_track(state_file: str, track: str, meta: dict[str, Any]) -> None:
    if not state_file or not os.path.isfile(state_file):
        return
    try:
        st = json.load(open(state_file, encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        st = {}
    st.setdefault("review_policy", {})
    st["review_policy"]["track"] = track
    st["review_policy"]["resolved_at"] = meta.get("reason", "")
    if "task_tier" in meta:
        st["review_policy"]["task_tier"] = meta["task_tier"]
    with open(state_file, "w", encoding="utf-8") as f:
        json.dump(st, f, ensure_ascii=False, indent=2)


def main() -> int:
    p = argparse.ArgumentParser(description="Resolve review track (goal: single only)")
    p.add_argument("--state-file", default="")
    p.add_argument("--plan-json", default="")
    p.add_argument("--task-tier", default="")
    p.add_argument("--persist", action="store_true")
    p.add_argument("--auto-resolve-xs-s", action="store_true")
    p.add_argument("--format", choices=("track", "json"), default="track")
    args = p.parse_args()

    state = _load_state(args.state_file)
    task_tier = (args.task_tier or _load_task_tier(state, args.plan_json)).upper()
    track, meta = resolve_review_track(task_tier, state=state, auto_resolve_xs_s=args.auto_resolve_xs_s)

    if args.persist and args.state_file:
        persist_review_track(args.state_file, track, meta)

    if args.format == "json":
        print(json.dumps({"track": track, "task_tier": task_tier, **meta}, ensure_ascii=False))
    else:
        print(track)
    return 0


if __name__ == "__main__":
    sys.exit(main())
