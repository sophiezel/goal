#!/usr/bin/env python3
"""Resolve review_depth (light | full) from state, packet size, and tier."""
from __future__ import annotations

import json
import os
from typing import Any


def _tier_from_state(state: dict[str, Any]) -> str:
    qp = state.get("quality_policy") or {}
    return str(qp.get("tier") or "standard")


def resolve_review_depth(
    packet: dict[str, Any],
    state: dict[str, Any] | None = None,
    *,
    explicit: str = "",
    changed_threshold: int = 5,
    diff_bytes_threshold: int = 25000,
) -> tuple[str, dict[str, Any]]:
    """Return (depth, meta) where depth is light or full."""
    state = state or {}
    rp = state.get("review_policy") or {}
    env_depth = (explicit or os.environ.get("GOAL_REVIEW_DEPTH") or rp.get("depth") or "adaptive").strip().lower()

    changed = len(packet.get("changed_files") or [])
    diff_bytes = len((packet.get("diff") or "").encode("utf-8"))
    tier = _tier_from_state(state)

    meta = {
        "changed_files": changed,
        "diff_bytes": diff_bytes,
        "tier": tier,
        "requested": env_depth,
    }

    if env_depth == "light":
        meta["reason"] = "explicit_light"
        return "light", meta
    if env_depth == "full":
        meta["reason"] = "explicit_full"
        return "full", meta

    # adaptive
    if tier == "strict":
        meta["reason"] = "strict_tier"
        return "full", meta
    if changed > changed_threshold or diff_bytes > diff_bytes_threshold:
        meta["reason"] = "large_change_set"
        return "full", meta
    meta["reason"] = "small_change_set"
    return "light", meta


def load_state(state_file: str) -> dict[str, Any]:
    if state_file and os.path.isfile(state_file):
        try:
            return json.load(open(state_file, encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            pass
    return {}


def persist_review_policy(state_file: str, depth: str, meta: dict[str, Any]) -> None:
    if not state_file or not os.path.isfile(state_file):
        return
    try:
        state = json.load(open(state_file, encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return
    rp = dict(state.get("review_policy") or {})
    rp["depth"] = depth
    rp["depth_meta"] = meta
    state["review_policy"] = rp
    with open(state_file, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2, ensure_ascii=False)
        f.write("\n")


def main() -> int:
    import argparse

    p = argparse.ArgumentParser(description="Resolve review_depth for adaptive routing")
    p.add_argument("--packet", required=True)
    p.add_argument("--state-file", default="")
    p.add_argument("--depth", default="", help="override: light|full|adaptive")
    p.add_argument("--persist", action="store_true")
    p.add_argument("--json", action="store_true", dest="as_json")
    args = p.parse_args()

    packet = json.load(open(args.packet, encoding="utf-8"))
    state = load_state(args.state_file)
    depth, meta = resolve_review_depth(packet, state, explicit=args.depth)
    if args.persist and args.state_file:
        persist_review_policy(args.state_file, depth, meta)
    out = {"depth": depth, "meta": meta}
    if args.as_json:
        print(json.dumps(out, ensure_ascii=False))
    else:
        print(depth)
    return 0


if __name__ == "__main__":
    main()
