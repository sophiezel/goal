#!/usr/bin/env python3
"""Resolve postmerge_policy (required | optional) for goal-pipeline / guazi-flow-goal."""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any


def _load_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def _frontmatter(text: str) -> dict[str, str]:
    m = re.match(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return {}
    out: dict[str, str] = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def _norm_policy(raw: str) -> str:
    v = (raw or "").strip().lower()
    if v in ("required", "require", "mandatory"):
        return "required"
    return "optional"


def resolve_postmerge_policy(
    *,
    index_path: str = "",
    state_file: str = "",
    handoff_dir: str = "",
    env_policy: str = "",
) -> tuple[str, dict[str, Any]]:
    meta: dict[str, Any] = {"sources": []}

    env = _norm_policy(env_policy or os.environ.get("GOAL_POSTMERGE_POLICY", ""))
    if env_policy or os.environ.get("GOAL_POSTMERGE_POLICY"):
        meta["sources"].append("env")
        meta["reason"] = "env_override"
        return env, meta

    state = _load_json(Path(state_file)) if state_file else {}
    ctx = state.get("resolved_rule_context") or {}
    st_pol = _norm_policy(str(ctx.get("postmerge_policy") or state.get("postmerge_policy") or ""))
    if st_pol == "required":
        meta["sources"].append("state.resolved_rule_context")
        meta["reason"] = "state_resolved_rule_context"
        return "required", meta

    handoff = Path(handoff_dir) if handoff_dir else Path()
    plan = _load_json(handoff / "plan.json")
    plan_ctx = plan.get("resolved_rule_context") or {}
    plan_pol = _norm_policy(
        str(plan_ctx.get("postmerge_policy") or plan.get("postmerge_policy") or "")
    )
    if plan_pol == "required":
        meta["sources"].append("handoff.plan.json")
        meta["reason"] = "plan_handoff"
        return "required", meta

    if index_path and Path(index_path).is_file():
        fm = _frontmatter(Path(index_path).read_text(encoding="utf-8"))
        idx_pol = _norm_policy(str(fm.get("postmerge_policy") or ""))
        if idx_pol == "required":
            meta["sources"].append("index.frontmatter")
            meta["reason"] = "index_frontmatter"
            return "required", meta

    meta["reason"] = "default_optional"
    return "optional", meta


def postmerge_evidence_ok(repo_evidence_dir: Path) -> tuple[bool, str]:
    pm = repo_evidence_dir / "postmerge.md"
    if not pm.is_file():
        return False, "missing evidence/postmerge.md"
    fm = _frontmatter(pm.read_text(encoding="utf-8"))
    stage = (fm.get("stage") or "").lower()
    if stage and stage != "postmerge":
        return False, f"postmerge.md stage={fm.get('stage')}"
    result = (fm.get("result") or "").lower()
    if result != "pass":
        return False, f"postmerge.md result={fm.get('result') or 'missing'}"
    review_md = repo_evidence_dir / "review.md"
    if review_md.is_file():
        rfm = _frontmatter(review_md.read_text(encoding="utf-8"))
        r_hash = rfm.get("review_subject_hash") or ""
        p_hash = fm.get("review_subject_hash") or ""
        if r_hash and p_hash and r_hash != p_hash:
            return False, "postmerge review_subject_hash stale vs review.md"
    return True, "ok"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--index", default="")
    ap.add_argument("--state-file", default="")
    ap.add_argument("--handoff-dir", default="")
    ap.add_argument("--repo-evidence-dir", default="")
    ap.add_argument("--check-evidence", action="store_true")
    ap.add_argument("--format", choices=("json", "text"), default="json")
    args = ap.parse_args()

    policy, meta = resolve_postmerge_policy(
        index_path=args.index,
        state_file=args.state_file,
        handoff_dir=args.handoff_dir,
    )
    evidence_ok = None
    evidence_detail = ""
    if args.check_evidence and policy == "required":
        if not args.repo_evidence_dir:
            evidence_ok = False
            evidence_detail = "repo_evidence_dir required for --check-evidence"
        else:
            evidence_ok, evidence_detail = postmerge_evidence_ok(Path(args.repo_evidence_dir))

    out = {
        "postmerge_policy": policy,
        "required": policy == "required",
        "meta": meta,
    }
    if evidence_ok is not None:
        out["postmerge_evidence_ok"] = evidence_ok
        out["postmerge_evidence_detail"] = evidence_detail

    if args.format == "text":
        print(f"postmerge_policy={policy}")
        if evidence_ok is not None:
            print(f"postmerge_evidence_ok={evidence_ok} ({evidence_detail})")
    else:
        print(json.dumps(out, ensure_ascii=False, indent=2))
    if policy == "required" and evidence_ok is False:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
