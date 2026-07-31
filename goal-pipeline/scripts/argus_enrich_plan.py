#!/usr/bin/env python3
"""Rule-based v1 Argus scenario manifest from plan.json write_set + optional index keywords.

v1 uses path/keyword heuristics only — not fe-argus Scenario Q / LLM retrieval.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path
from typing import Any, Callable

# Path heuristics on write_set only (no task/page literals).
PATH_SCENARIO_RULES: list[tuple[str, Callable[[list[str]], bool], str]] = [
    (
        "route-entry",
        lambda ws: any("App.tsx" in p or "pages/index" in p for p in ws),
        "App / pages index entry files in write_set",
    ),
    (
        "page-domain",
        lambda ws: any("/pages/" in p for p in ws),
        "page domain paths under src/pages/",
    ),
    (
        "service-layer",
        lambda ws: any("/services/" in p for p in ws),
        "service layer paths (API bindings surface)",
    ),
    (
        "shared-ui",
        lambda ws: any("/components/" in p for p in ws),
        "shared components in write_set",
    ),
    (
        "styles",
        lambda ws: any(p.endswith((".scss", ".css", ".sass")) for p in ws),
        "stylesheet paths in write_set",
    ),
]

# Optional index.md keyword hints (generic UX patterns, not business field names).
INDEX_OPTIONAL_RULES: list[tuple[str, str, str]] = [
    ("loading-shell", r"骨架|skeleton|首屏|pending|isLoading", "loading or skeleton for async UI"),
    ("submit-button-loading", r"提交|confirm|submit|二次确认|primary\s+cta", "primary CTA loading/disabled"),
    ("readonly-mode", r"只读|readonly|view[\s-]?only", "read-only vs edit mode"),
    ("image-preview", r"预览|preview|大图|lightbox|gallery", "image preview / gallery"),
    ("header-layout", r"Header|header|nav\s*bar|标题栏", "page header / nav consistency"),
    ("form-validation", r"Toast|toast|必填|required|validation", "required fields and user feedback"),
]

DEFAULT_SCENARIOS = [
    {
        "id": "page-smoke",
        "severity": "soft",
        "paths": [],
        "verify_hint": "manual: route reachable + smoke/UVO",
        "w1_status": "open",
    }
]


def _load_uvo_helper():
    script_dir = Path(__file__).resolve().parent
    spec = importlib.util.spec_from_file_location("uvo", script_dir / "verification_oracle_core.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_write_set(handoff_dir: Path) -> list[str]:
    plan = handoff_dir / "plan.json"
    if not plan.is_file():
        return []
    try:
        ws = json.loads(plan.read_text(encoding="utf-8")).get("write_set") or []
        return list(ws)
    except json.JSONDecodeError:
        return []


def page_paths(write_set: list[str]) -> list[str]:
    out: list[str] = []
    for w in write_set:
        if "/pages/" in w and (w.endswith((".tsx", ".ts", "/")) or w.endswith("/")):
            out.append(w)
    return out or [p for p in write_set if p.startswith("src/pages/")]


def build_manifest(task_dir: Path, handoff_dir: Path) -> dict[str, Any]:
    index_path = task_dir / "index.md"
    index_text = index_path.read_text(encoding="utf-8") if index_path.is_file() else ""
    write_set = load_write_set(handoff_dir)
    pages = page_paths(write_set)
    scenarios: list[dict[str, Any]] = []
    seen_ids: set[str] = set()

    rel_paths = pages[:3] if pages else [p for p in write_set if p.startswith("src/")][:5]

    for sid, pred, hint in PATH_SCENARIO_RULES:
        if not write_set or not pred(write_set):
            continue
        if sid in seen_ids:
            continue
        seen_ids.add(sid)
        scenarios.append(
            {
                "id": sid,
                "severity": "soft",
                "paths": rel_paths,
                "verify_hint": hint,
                "w1_status": "open",
                "source": "rule",
                "signal": "write_set_path",
            }
        )

    for sid, pattern, hint in INDEX_OPTIONAL_RULES:
        if sid in seen_ids:
            continue
        if not index_text or not re.search(pattern, index_text, re.I):
            continue
        seen_ids.add(sid)
        scenarios.append(
            {
                "id": sid,
                "severity": "soft",
                "paths": rel_paths,
                "verify_hint": hint,
                "w1_status": "open",
                "source": "rule",
                "signal": "index_keyword",
            }
        )

    if not scenarios:
        default = dict(DEFAULT_SCENARIOS[0])
        default["paths"] = rel_paths
        default["source"] = "rule"
        scenarios.append(default)

    return {
        "schema_version": 2,
        "generated_by": "argus_enrich_plan.py v1 (rule-based; fe-argus merge via Agent WO)",
        "argus_enrich_status": "rule_only",
        "scenarios": scenarios,
    }


def merge_scenario_lists(
    rule_scenarios: list[dict[str, Any]],
    argus_scenarios: list[dict[str, Any]],
    *,
    argus_status: str = "partial",
) -> dict[str, Any]:
    """Merge Agent fe-argus scenarios by id; rule rows win on id conflict."""
    by_id: dict[str, dict[str, Any]] = {}
    for row in rule_scenarios:
        rid = str(row.get("id") or "")
        if not rid:
            continue
        merged = dict(row)
        merged["source"] = merged.get("source") or "rule"
        by_id[rid] = merged
    for row in argus_scenarios:
        rid = str(row.get("id") or "")
        if not rid:
            continue
        if rid in by_id:
            continue
        merged = dict(row)
        merged["source"] = "argus"
        by_id[rid] = merged
    return {
        "schema_version": 2,
        "generated_by": "argus_enrich_plan.py merge",
        "argus_enrich_status": argus_status,
        "scenarios": list(by_id.values()),
    }


def apply_fe_argus_merge(
    handoff_dir: Path,
    *,
    pending_file: Path,
    merge_status: str = "merged",
) -> dict[str, Any]:
    manifest_path = handoff_dir / "argus-scenario-manifest.json"
    if not manifest_path.is_file():
        raise FileNotFoundError(f"missing rule manifest: {manifest_path}")
    rule_doc = json.loads(manifest_path.read_text(encoding="utf-8"))
    rule_rows = list(rule_doc.get("scenarios") or [])
    pending = json.loads(pending_file.read_text(encoding="utf-8"))
    argus_rows = pending.get("scenarios") if isinstance(pending, dict) else pending
    if not isinstance(argus_rows, list):
        raise ValueError("fe-argus pending file must contain scenarios list or {scenarios: []}")
    status = merge_status if merge_status in ("merged", "partial") else "partial"
    return merge_scenario_lists(rule_rows, argus_rows, argus_status=status)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--task-dir", required=True)
    ap.add_argument("--handoff-dir", default="")
    ap.add_argument("--out", default="")
    ap.add_argument("--format", choices=("json", "text"), default="json")
    ap.add_argument("--merge-fe-argus-file", default="")
    ap.add_argument("--merge-status", choices=("merged", "partial"), default="merged")
    args = ap.parse_args()

    task_dir = Path(args.task_dir).resolve()
    if args.handoff_dir:
        handoff_dir = Path(args.handoff_dir).resolve()
    else:
        uvo = _load_uvo_helper()
        handoff_dir = Path(uvo.resolve_handoff_dir(str(task_dir)))

    out_path = Path(args.out) if args.out else handoff_dir / "argus-scenario-manifest.json"

    if args.merge_fe_argus_file:
        pending = Path(args.merge_fe_argus_file).resolve()
        doc = apply_fe_argus_merge(
            handoff_dir, pending_file=pending, merge_status=args.merge_status
        )
    else:
        doc = build_manifest(task_dir, handoff_dir)
        if out_path.is_file():
            try:
                old = json.loads(out_path.read_text(encoding="utf-8"))
                if old.get("argus_enrich_status") in ("merged", "partial"):
                    argus_only = [
                        s for s in (old.get("scenarios") or []) if s.get("source") == "argus"
                    ]
                    if argus_only:
                        doc = merge_scenario_lists(
                            doc["scenarios"],
                            argus_only,
                            argus_status=str(old.get("argus_enrich_status") or "merged"),
                        )
            except json.JSONDecodeError:
                pass

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    if args.format == "text":
        print(f"written {out_path} scenarios={len(doc['scenarios'])}")
    else:
        print(
            json.dumps(
                {"ok": True, "path": str(out_path), "scenario_count": len(doc["scenarios"])},
                ensure_ascii=False,
            )
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
