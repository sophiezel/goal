#!/usr/bin/env python3
"""Resolve review track (single vs dual) for XS/S fast-track (v3 §8.2).

single: goal-review/SKILL.md only + goal-run-review-chain.sh (no guazi-flow-review Agent turn)
dual:   guazi-flow-review + chain (current behavior)

Default in PR3: dual (feature flag). Single is opt-in via env or state.
P2 flips auto-resolve to single for XS/S after eval ≥95% × 2 rounds.
"""
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
    env = (env_track or os.environ.get("GOAL_REVIEW_TRACK") or "").strip().lower()
    if env == "single":
        return "single", {"reason": "env_override"}
    if env == "dual":
        return "dual", {"reason": "env_override"}

    # P2 default-flip: GOAL_REVIEW_SINGLE_DEFAULT=1 enables XS/S → single auto-resolve
    # (gated behind eval ≥95% × 2 rounds; set after P2 eval passes)
    if not auto_resolve_xs_s and os.environ.get("GOAL_REVIEW_SINGLE_DEFAULT") == "1":
        auto_resolve_xs_s = True

    state = state or {}
    state_track = str((state.get("review_policy") or {}).get("track") or "").lower()
    if state_track == "single":
        return "single", {"reason": "state_review_policy"}
    if state_track == "dual":
        return "dual", {"reason": "state_review_policy"}

    # auto-resolve: XS/S → single when --auto-resolve-xs-s or plan_profile lite (manifest default)
    plan_profile = str(state.get("plan_profile") or "").lower()
    if not auto_resolve_xs_s and plan_profile == "lite" and task_tier in ("XS", "S"):
        auto_resolve_xs_s = True
    if auto_resolve_xs_s and task_tier in ("XS", "S"):
        return "single", {"reason": "auto_xs_s", "task_tier": task_tier}

    return "dual", {"reason": "default_dual"}


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
    p = argparse.ArgumentParser(description="Resolve review track (single/dual)")
    p.add_argument("--state-file", default="")
    p.add_argument("--plan-json", default="")
    p.add_argument("--task-tier", default="")
    p.add_argument("--persist", action="store_true")
    p.add_argument("--auto-resolve-xs-s", action="store_true",
                   help="Enable XS/S → single auto-resolve (gated; off by default in PR3)")
    p.add_argument("--format", choices=("track", "json"), default="track")
    args = p.parse_args()

    state = _load_state(args.state_file)
    if args.plan_json and os.path.isfile(args.plan_json):
        try:
            plan_doc = json.load(open(args.plan_json, encoding="utf-8"))
            state.setdefault("plan_profile", plan_doc.get("plan_profile", ""))
            if not state.get("task_tier"):
                state["task_tier"] = plan_doc.get("task_tier", "")
        except (OSError, json.JSONDecodeError):
            pass
    task_tier = (args.task_tier or _load_task_tier(state, args.plan_json)).upper()
    track, meta = resolve_review_track(
        task_tier, state=state, auto_resolve_xs_s=args.auto_resolve_xs_s
    )

    if args.persist and args.state_file:
        persist_review_track(args.state_file, track, meta)

    if args.format == "json":
        print(json.dumps({"track": track, "task_tier": task_tier, **meta}, ensure_ascii=False))
    else:
        print(track)
    return 0


if __name__ == "__main__":
    sys.exit(main())
