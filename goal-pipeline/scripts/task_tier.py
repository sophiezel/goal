#!/usr/bin/env python3
"""task_tier — classify Goal complexity (XS/S/M/L/XL) and emit parallel strategy.

Used at plan post to stamp state.json / plan.json. Agents MUST NOT force XS/20m
on M/L tasks; wall-clock SLO follows the matrix below.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from typing import Any


TIER_MATRIX: dict[str, dict[str, Any]] = {
    "XS": {
        "p50_wall_min": 15,
        "p90_wall_min": 25,
        "parallel": "single_agent",
        "max_subagents": 0,
        "multi_unit": False,
        "review_shard": False,
    },
    "S": {
        "p50_wall_min": 25,
        "p90_wall_min": 40,
        "parallel": "optional_2_subagents",
        "max_subagents": 2,
        "multi_unit": False,
        "review_shard": False,
    },
    "M": {
        "p50_wall_min": 45,
        "p90_wall_min": 70,
        "parallel": "subagent_dag_3_4",
        "max_subagents": 4,
        "multi_unit": False,
        "review_shard": False,
    },
    "L": {
        "p50_wall_min": 90,
        "p90_wall_min": 120,
        "parallel": "multi_unit_plus_subagents",
        "max_subagents": 4,
        "multi_unit": True,
        "review_shard": True,
    },
    "XL": {
        "p50_wall_min": None,
        "p90_wall_min": None,
        "parallel": "worktree_units",
        "max_subagents": 6,
        "multi_unit": True,
        "review_shard": True,
    },
}

SHARED_ENTRY_PATHS = (
    "src/App.tsx",
    "src/pages/index.ts",
    "config-overrides.js",
)


def _parse_write_set_from_index(index_text: str) -> list[str]:
    m = re.search(
        r"(?:##\s*(?:write_set|写集|范围与写集)|write_set\s*[:：])\s*\n([\s\S]*?)(?:\n##|\Z)",
        index_text,
        re.I,
    )
    if not m:
        return []
    body = m.group(1)
    paths: list[str] = []
    for line in body.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        # exclusion subsections
        if re.match(r"^(排除|除外|不做|不包含|exclude)", line, re.I):
            break
        bm = re.match(r"^[-*]\s+`?([^`]+)`?", line)
        if bm:
            paths.append(bm.group(1).strip())
            continue
        tm = re.match(r"^\|\s*`?([^`|]+)`?\s*\|", line)
        if tm and "路径" not in tm.group(1) and "path" not in tm.group(1).lower():
            paths.append(tm.group(1).strip())
    return paths


def _new_page_dirs(write_set: list[str]) -> int:
    dirs = set()
    for w in write_set:
        w = w.replace("\\", "/").rstrip("/")
        if "/pages/" not in w and not w.startswith("src/pages/"):
            continue
        # src/pages/foo or src/pages/foo/**
        parts = w.split("/")
        try:
            i = parts.index("pages")
            if i + 1 < len(parts) and parts[i + 1]:
                dirs.add(parts[i + 1].split("*")[0])
        except ValueError:
            continue
    return len(dirs)


def classify(
    write_set: list[str] | None = None,
    index_text: str = "",
    figma_required: bool | None = None,
) -> dict[str, Any]:
    ws = list(write_set or [])
    if not ws and index_text:
        ws = _parse_write_set_from_index(index_text)
    ws = [w.strip() for w in ws if w and str(w).strip()]

    score = 0
    signals: dict[str, Any] = {
        "write_set_count": len(ws),
        "new_page_dirs": _new_page_dirs(ws),
        "touches_shared_entry": any(
            any(s in w or w.rstrip("/") == s.rstrip("/") for s in SHARED_ENTRY_PATHS) for w in ws
        ),
        "cross_domain": False,
        "multi_ui_surfaces": 0,
        "figma_required": bool(figma_required),
    }

    domains = set()
    for w in ws:
        if "pages/" in w:
            domains.add("pages")
        if "services/" in w:
            domains.add("services")
        if "components/" in w:
            domains.add("components")
        if w.endswith("App.tsx") or "pages/index.ts" in w:
            domains.add("routing")
    signals["cross_domain"] = len(domains) >= 2
    signals["domains"] = sorted(domains)

    # Unique page roots that look like UI surfaces (not every file)
    ui_roots: set[str] = set()
    for w in ws:
        if not re.search(r"FailReason|Popup|List|Recovery|Conversion|Card", w, re.I):
            continue
        parts = w.replace("\\", "/").split("/")
        if "pages" in parts:
            i = parts.index("pages")
            if i + 1 < len(parts):
                ui_roots.add(parts[i + 1])
    signals["multi_ui_surfaces"] = len(ui_roots)

    if index_text and figma_required is None:
        signals["figma_required"] = bool(
            re.search(r"figma\.com|高保真|figma-structure", index_text, re.I)
        )
    multi_unit_doc = bool(
        index_text and re.search(r"(?m)^units\s*:|##\s*units\b|multi-unit", index_text, re.I)
    )
    signals["multi_unit_doc"] = multi_unit_doc

    # Calibrated so: tiny→XS, local patch→S, new list+cross-page (CTB)→M,
    # figma/multi-unit→L, extreme→XL. Do NOT over-weight file fan-out.
    n_pages = signals["new_page_dirs"]
    n_files = len(ws)
    score += 2 if n_pages >= 1 else 0
    score += 2 if n_pages >= 2 else 0
    score += 1 if n_pages >= 4 else 0
    score += 2 if n_files >= 12 else (1 if n_files >= 6 else 0)
    score += 2 if signals["cross_domain"] else 0
    score += 1 if signals["touches_shared_entry"] else 0
    score += min(signals["multi_ui_surfaces"], 2)
    if signals["figma_required"]:
        score += 4
    if multi_unit_doc:
        score += 3

    if n_files <= 2 and n_pages == 0 and score <= 1:
        tier = "XS"
    elif n_pages <= 1 and n_files <= 6 and score <= 4 and not signals["figma_required"]:
        tier = "S"
    elif signals["figma_required"] or multi_unit_doc:
        tier = "L" if score < 16 else "XL"
    elif score <= 13:
        # CTB-like: new list + cross-page popups (~score 10–13) stays M
        tier = "M"
    elif score <= 16:
        tier = "L"
    else:
        tier = "XL"

    matrix = TIER_MATRIX[tier]
    return {
        "task_tier": tier,
        "score": score,
        "signals": signals,
        "slo": {
            "p50_wall_min": matrix["p50_wall_min"],
            "p90_wall_min": matrix["p90_wall_min"],
        },
        "parallel": {
            "strategy": matrix["parallel"],
            "max_subagents": matrix["max_subagents"],
            "multi_unit": matrix["multi_unit"],
            "review_shard": matrix["review_shard"],
            "shared_entry_serial": True,
            "note": "Shared entry files (App.tsx / pages/index.ts) MUST be merged serially by orchestrator",
        },
        "matrix": TIER_MATRIX,
    }


def classify_from_paths(task_dir: str, plan_path: str = "") -> dict[str, Any]:
    index_path = os.path.join(task_dir, "index.md")
    index_text = ""
    if os.path.isfile(index_path):
        index_text = open(index_path, encoding="utf-8").read()
    write_set: list[str] = []
    if plan_path and os.path.isfile(plan_path):
        try:
            plan = json.load(open(plan_path, encoding="utf-8"))
            write_set = list(plan.get("write_set") or [])
        except (OSError, json.JSONDecodeError):
            pass
    return classify(write_set=write_set, index_text=index_text)


def stamp_state(state_path: str, tier_doc: dict[str, Any]) -> None:
    if not state_path or not os.path.isfile(state_path):
        return
    with open(state_path, encoding="utf-8") as f:
        state = json.load(f)
    state["task_tier"] = tier_doc["task_tier"]
    state["task_tier_meta"] = {
        "score": tier_doc["score"],
        "signals": tier_doc["signals"],
        "slo": tier_doc["slo"],
        "parallel": tier_doc["parallel"],
    }
    with open(state_path, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2, ensure_ascii=False)
        f.write("\n")


def main() -> int:
    ap = argparse.ArgumentParser(description="Classify Goal task_tier")
    ap.add_argument("--task-dir", default="")
    ap.add_argument("--plan-json", default="")
    ap.add_argument("--state-file", default="")
    ap.add_argument("--stamp-state", action="store_true")
    ap.add_argument("--format", choices=("json", "text"), default="json")
    args = ap.parse_args()

    if args.task_dir:
        doc = classify_from_paths(os.path.abspath(args.task_dir), args.plan_json)
    else:
        doc = classify()

    if args.stamp_state and args.state_file:
        stamp_state(args.state_file, doc)

    if args.format == "text":
        print(f"task_tier={doc['task_tier']} p50={doc['slo']['p50_wall_min']}m parallel={doc['parallel']['strategy']}")
    else:
        print(json.dumps(doc, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
