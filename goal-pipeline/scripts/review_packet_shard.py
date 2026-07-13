#!/usr/bin/env python3
"""Split review packets into domain shards and merge shard-level unified JSON."""
from __future__ import annotations

import importlib.util
import json
import os
import re
from typing import Any


def _load_diff_resolver(script_dir: str):
    path = os.path.join(script_dir, "diff_resolver.py")
    spec = importlib.util.spec_from_file_location("diff_resolver", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"diff_resolver missing: {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def classify_path(path: str) -> str:
    p = path.replace("\\", "/")
    if "services/" in p or p.startswith("src/services/"):
        return "services"
    if "components/" in p or "popup" in p.lower() or "modal" in p.lower():
        return "components"
    if "list" in p.lower():
        return "list"
    if "App.tsx" in p or "pages/index.ts" in p or "/routes" in p:
        return "routing"
    if p.startswith("src/pages/"):
        return "detail"
    return "core"


def shard_paths(changed_files: list[str]) -> dict[str, list[str]]:
    buckets: dict[str, list[str]] = {}
    for raw in changed_files:
        p = (raw or "").strip()
        if not p:
            continue
        sid = classify_path(p)
        buckets.setdefault(sid, []).append(p)
    return buckets


def issue_dedup_key(issue: dict[str, Any]) -> str:
    ch = issue.get("channel", "goal")
    f = issue.get("file", "")
    summary = (issue.get("summary") or issue.get("description") or "")[:80]
    return f"{ch}|{f}|{summary}"


def merge_unified_reviews(reviews: list[dict[str, Any]]) -> dict[str, Any]:
    """Merge shard unified JSON; dedupe issues by channel|file|summary."""
    if not reviews:
        return {
            "result": "review_undetermined",
            "issues": [],
            "checklist_goal": [],
            "checklist_gf": [],
        }
    if len(reviews) == 1:
        return reviews[0]

    merged_issues: list[dict[str, Any]] = []
    seen: set[str] = set()
    goal_cl: dict[str, dict] = {}
    gf_cl: dict[str, dict] = {}
    results: list[str] = []
    models: list[str] = []
    gf_attested = False

    for rev in reviews:
        results.append(str(rev.get("result") or "not_pass"))
        if rev.get("model"):
            models.append(str(rev["model"]))
        gf_attested = gf_attested or bool(rev.get("gf_skill_attested"))
        for iss in rev.get("issues") or []:
            if not isinstance(iss, dict):
                continue
            key = issue_dedup_key(iss)
            if key in seen:
                continue
            seen.add(key)
            merged_issues.append(iss)
        for item in rev.get("checklist_goal") or []:
            if not isinstance(item, dict):
                continue
            iid = str(item.get("id") or item.get("case_id") or len(goal_cl))
            prev = goal_cl.get(iid)
            if not prev or not item.get("passed", True):
                goal_cl[iid] = item
        for item in rev.get("checklist_gf") or []:
            if not isinstance(item, dict):
                continue
            cid = str(item.get("case_id") or item.get("id") or len(gf_cl))
            prev = gf_cl.get(cid)
            if not prev or not item.get("passed", True):
                gf_cl[cid] = item

    blockers = [i for i in merged_issues if (i.get("severity") or "").lower() in ("blocker", "high", "critical")]
    if any(r == "review_undetermined" for r in results):
        final = "review_undetermined"
    elif any(r == "not_pass" for r in results) or blockers:
        final = "not_pass"
    elif all(r == "pass" for r in results):
        final = "pass"
    else:
        final = "not_pass"

    return {
        "schema_version": 1,
        "result": final,
        "issues": merged_issues,
        "checklist_goal": list(goal_cl.values()),
        "checklist_gf": list(gf_cl.values()),
        "gf_skill_attested": gf_attested,
        "model": models[0] if models else "",
        "shard_merge": {"shard_count": len(reviews), "results": results},
    }


def build_shards(packet: dict[str, Any], script_dir: str, min_shards: int = 2) -> list[dict[str, Any]]:
    """Return list of shard packets with filtered diff per domain."""
    dr = _load_diff_resolver(script_dir)
    changed = list(packet.get("changed_files") or [])
    if len(changed) < min_shards:
        return [packet]

    buckets = shard_paths(changed)
    if len(buckets) < min_shards:
        return [packet]

    full_diff = packet.get("diff") or ""
    shards: list[dict[str, Any]] = []
    for sid, files in sorted(buckets.items()):
        if not files:
            continue
        shard_diff = dr.filter_diff_by_write_set(full_diff, files)
        if not shard_diff.strip():
            continue
        p = json.loads(json.dumps(packet))
        p["diff"] = shard_diff
        p["changed_files"] = files
        p["shard_id"] = sid
        p["shard_label"] = sid
        p["diff_source"] = (packet.get("diff_source") or "code_subject_hash") + f"+shard:{sid}"
        meta = p.get("hashes") or {}
        meta["shard_id"] = sid
        p["hashes"] = meta
        contract = dict(p.get("contract") or {})
        contract["shard_scope"] = f"仅审查以下变更文件: {', '.join(files[:20])}"
        p["contract"] = contract
        shards.append(p)

    return shards if len(shards) >= min_shards else [packet]
