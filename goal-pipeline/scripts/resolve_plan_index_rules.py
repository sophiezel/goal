#!/usr/bin/env python3
"""Resolve plan-index-rules.json path (full vs lite) from frontmatter / plan handoff / pre-estimate."""
from __future__ import annotations

import argparse
import json
import os
import re
import sys


def _schema_dir(script_dir: str) -> str:
    refs = os.path.join(script_dir, "..", "references")
    guazi = os.path.join(refs, "guazi-flow-artifact-schema")
    if os.environ.get("GATE_MODE", "").strip().lower() == "guazi" and os.path.isdir(guazi):
        return guazi
    return os.path.join(refs, "goal-artifact-schema")


def parse_frontmatter(text: str) -> dict[str, str]:
    m = re.match(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return {}
    out: dict[str, str] = {}
    for line in m.group(1).splitlines():
        s = line.strip()
        if ":" in s and not s.startswith("#"):
            k, v = s.split(":", 1)
            out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def _load_task_tier_from_plan(plan_json: str) -> str:
    if not plan_json or not os.path.isfile(plan_json):
        return ""
    try:
        return str(json.load(open(plan_json, encoding="utf-8")).get("task_tier") or "").upper()
    except (OSError, json.JSONDecodeError):
        return ""


def _write_set_path_count(index_text: str) -> int:
    ws = re.search(
        r"(?:##\s*(?:write_set|写集|范围与写集)|write_set\s*[:：])\s*\n([\s\S]*?)(?:\n##|\Z)",
        index_text,
        re.I,
    )
    if not ws:
        return 0
    count = 0
    for line in ws.group(1).splitlines():
        s = line.strip()
        if s.startswith("- ") or s.startswith("* "):
            count += 1
    return count


def _has_new_pages(index_text: str) -> bool:
    ws = re.search(
        r"(?:##\s*(?:write_set|写集|范围与写集)|write_set\s*[:：])\s*\n([\s\S]*?)(?:\n##|\Z)",
        index_text,
        re.I,
    )
    if not ws:
        return False
    return bool(re.search(r"src/pages/", ws.group(1)))


def _has_units(index_text: str) -> bool:
    return bool(re.search(r"units\s*[:：]|##\s*units", index_text, re.I))


def resolve_plan_profile(
    index_path: str,
    *,
    plan_json: str = "",
    env_override: str = "",
) -> tuple[str, dict]:
    env = (env_override or os.environ.get("GOAL_PLAN_PROFILE") or "").strip().lower()
    if env == "lite":
        return "lite", {"reason": "env_override"}
    if env == "full":
        return "full", {"reason": "env_override"}

    # plan.json task_tier M+ forces full (overrides even frontmatter lite) — "M+ 强制 full rules"
    plan_tier = _load_task_tier_from_plan(plan_json)
    if plan_tier in ("M", "L", "XL"):
        return "full", {"reason": "plan_json_task_tier_m_plus", "task_tier": plan_tier}

    if not os.path.isfile(index_path):
        return "full", {"reason": "index_missing"}

    text = open(index_path, encoding="utf-8").read()
    fm = parse_frontmatter(text)
    # Explicit frontmatter plan_profile wins (full declared → full, even if plan.json says XS/S)
    fm_profile = str(fm.get("plan_profile") or "").lower()
    if fm_profile == "lite":
        return "lite", {"reason": "frontmatter_plan_profile"}
    if fm_profile == "full":
        return "full", {"reason": "frontmatter_plan_profile"}

    # plan.json task_tier XS/S → lite (only when frontmatter didn't declare)
    if plan_tier in ("XS", "S"):
        return "lite", {"reason": "plan_json_task_tier", "task_tier": plan_tier}

    # frontmatter task_tier XS/S → lite
    tier = str(fm.get("task_tier") or "").upper()
    if tier in ("XS", "S"):
        return "lite", {"reason": "frontmatter_task_tier", "task_tier": tier}

    # Pre-estimate: write_set ≤3, no new pages, no units → lite
    if _write_set_path_count(text) <= 3 and not _has_new_pages(text) and not _has_units(text):
        return "lite", {"reason": "pre_estimate_small"}

    return "full", {"reason": "default_full"}


def rules_path_for_profile(schema_dir: str, profile: str) -> str:
    if profile == "lite":
        lite = os.path.join(schema_dir, "plan-index-rules-lite.json")
        if os.path.isfile(lite):
            return lite
    return os.path.join(schema_dir, "plan-index-rules.json")


def main() -> int:
    p = argparse.ArgumentParser(description="Resolve plan-index-rules.json (full vs lite)")
    p.add_argument("--index", required=True)
    p.add_argument("--plan-json", default="")
    p.add_argument("--format", choices=("path", "json"), default="path")
    args = p.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    schema_dir = _schema_dir(script_dir)
    profile, meta = resolve_plan_profile(args.index, plan_json=args.plan_json)
    rules_path = rules_path_for_profile(schema_dir, profile)

    if args.format == "json":
        print(json.dumps({"profile": profile, "rules_path": rules_path, **meta}, ensure_ascii=False))
    else:
        print(rules_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
