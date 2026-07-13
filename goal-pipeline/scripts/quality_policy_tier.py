#!/usr/bin/env python3
"""Resolve quality_policy.tier with auto-upgrade for security-sensitive write_sets."""
from __future__ import annotations

import argparse
import json
import os
import re
from typing import Any

# Path / keyword signals that force strict tier (security, auth, payment)
STRICT_PATH_RE = re.compile(
    r"(?:^|/)(?:auth|login|oauth|token|credential|password|security|payment|pay|wallet|encrypt|secret)(?:/|\.|$)",
    re.I,
)
STRICT_KEYWORD_RE = re.compile(
    r"\b(?:鉴权|登录|支付|密码|token|oauth|credential|security|payment|wallet|encrypt)\b",
    re.I,
)


def parse_write_set(index_text: str, plan_handoff: dict[str, Any] | None = None) -> list[str]:
    if plan_handoff:
        ws = plan_handoff.get("write_set") or []
        if isinstance(ws, list) and ws:
            return [str(p) for p in ws]
    m = re.search(
        r"(?:write_set\s*[:：]|##\s*(?:write_set|写集|范围与写集))\s*(.+?)(?:\n##|\Z)",
        index_text,
        re.I | re.S,
    )
    if not m:
        return []
    body = m.group(1)
    paths: list[str] = []
    for line in body.splitlines():
        line = line.strip().lstrip("-*•").strip()
        if not line or line.startswith("#"):
            continue
        line = re.sub(r"^\d+\.\s*", "", line)
        if line:
            paths.append(line.split()[0] if " " in line else line)
    return paths


def tier_signals(index_text: str, write_set: list[str]) -> list[str]:
    signals: list[str] = []
    for path in write_set:
        if STRICT_PATH_RE.search(path.replace("\\", "/")):
            signals.append(f"path:{path}")
    if STRICT_KEYWORD_RE.search(index_text):
        signals.append("index_keyword")
    return signals


def resolve_quality_tier(
    index_text: str,
    state: dict[str, Any] | None = None,
    *,
    plan_handoff: dict[str, Any] | None = None,
    explicit: str = "",
) -> tuple[str, dict[str, Any]]:
    state = state or {}
    qp = state.get("quality_policy") or {}
    current = str(qp.get("tier") or "standard").lower()
    requested = (explicit or os.environ.get("GOAL_QUALITY_TIER") or current).strip().lower()

    write_set = parse_write_set(index_text, plan_handoff)
    signals = tier_signals(index_text, write_set)

    meta: dict[str, Any] = {
        "requested": requested,
        "previous": current,
        "write_set_count": len(write_set),
        "strict_signals": signals,
    }

    if requested == "strict":
        meta["reason"] = "explicit_strict"
        return "strict", meta
    if signals:
        meta["reason"] = "auto_upgrade_security_write_set"
        meta["upgraded_from"] = requested if requested != "strict" else current
        return "strict", meta
    meta["reason"] = "default_standard"
    return "standard", meta


def load_state(state_file: str) -> dict[str, Any]:
    if state_file and os.path.isfile(state_file):
        try:
            return json.load(open(state_file, encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            pass
    return {}


def persist_quality_policy(state_file: str, tier: str, meta: dict[str, Any]) -> None:
    if not state_file or not os.path.isfile(state_file):
        return
    try:
        state = json.load(open(state_file, encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return
    qp = dict(state.get("quality_policy") or {})
    qp["tier"] = tier
    qp["tier_meta"] = meta
    state["quality_policy"] = qp
    with open(state_file, "w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=2, ensure_ascii=False)
        fh.write("\n")


def main() -> int:
    p = argparse.ArgumentParser(description="Resolve quality_policy tier with auto-upgrade")
    p.add_argument("--index", default="")
    p.add_argument("--task-dir", default="")
    p.add_argument("--state-file", default="")
    p.add_argument("--tier", default="", help="override: standard|strict")
    p.add_argument("--persist", action="store_true")
    p.add_argument("--json", action="store_true", dest="as_json")
    args = p.parse_args()

    index_path = args.index
    if not index_path and args.task_dir:
        index_path = os.path.join(args.task_dir, "index.md")
    if not index_path or not os.path.isfile(index_path):
        print("standard" if not args.as_json else json.dumps({"tier": "standard", "meta": {"reason": "no_index"}}))
        return 0

    index_text = open(index_path, encoding="utf-8").read()
    plan_handoff = None
    if args.task_dir:
        handoff = os.path.join(args.task_dir, "handoff", "plan.json")
        if os.path.isfile(handoff):
            try:
                plan_handoff = json.load(open(handoff, encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                pass

    state = load_state(args.state_file)
    tier, meta = resolve_quality_tier(index_text, state, plan_handoff=plan_handoff, explicit=args.tier)
    if args.persist and args.state_file:
        persist_quality_policy(args.state_file, tier, meta)
    if args.as_json:
        print(json.dumps({"tier": tier, "meta": meta}, ensure_ascii=False))
    else:
        print(tier)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
