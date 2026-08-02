#!/usr/bin/env python3
"""Deterministic preflight for review-packet.json — fail fast before LLM."""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import sys
from typing import Any


def _load_diff_resolver(script_dir: str):
    path = os.path.join(script_dir, "diff_resolver.py")
    spec = importlib.util.spec_from_file_location("diff_resolver", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def run_preflight(
    packet: dict[str, Any],
    uvo_path: str,
    min_diff_bytes: int = 256,
    require_src: bool = True,
) -> dict[str, Any]:
    issues: list[dict[str, Any]] = []
    diff_text = packet.get("diff") or ""
    if not diff_text.strip():
        diff_text = packet.get("reference_impl_diff") or ""

    dr = None
    script_dir = os.path.dirname(os.path.abspath(__file__))
    try:
        dr = _load_diff_resolver(script_dir)
        src_files = dr.src_files_in_diff(diff_text)
    except Exception:
        src_files = [f for f in (packet.get("changed_files") or []) if str(f).startswith("src/")]

    if require_src and not src_files:
        issues.append(
            {
                "id": "PKT-01",
                "severity": "blocker",
                "summary": "review packet diff has no src/** files — LLM cannot verify implementation",
                "root_cause": "implement_error",
            }
        )

    diff_bytes = len(diff_text.encode("utf-8"))
    ref_branch = packet.get("reference_branch") or ""
    if diff_bytes < min_diff_bytes and not ref_branch:
        issues.append(
            {
                "id": "PKT-02",
                "severity": "blocker",
                "summary": f"review packet diff too small ({diff_bytes} bytes)",
                "root_cause": "implement_error",
            }
        )

    uvo_overall = "missing"
    if os.path.isfile(uvo_path):
        try:
            uvo = json.load(open(uvo_path, encoding="utf-8"))
            uvo_overall = uvo.get("overall", "not_pass")
            if uvo_overall != "pass":
                issues.append(
                    {
                        "id": "PKT-03",
                        "severity": "blocker",
                        "summary": f"verification-oracle overall={uvo_overall}",
                        "root_cause": "implement_qc",
                    }
                )
        except (OSError, json.JSONDecodeError) as e:
            issues.append(
                {
                    "id": "PKT-03",
                    "severity": "blocker",
                    "summary": f"verification-oracle unreadable: {e}",
                    "root_cause": "implement_qc",
                }
            )
    else:
        issues.append(
            {
                "id": "PKT-03",
                "severity": "blocker",
                "summary": "verification-oracle.json missing",
                "root_cause": "implement_qc",
            }
        )

    integrity = packet.get("integrity") or {}
    if integrity.get("errors"):
        for err in integrity["errors"]:
            issues.append(
                {
                    "id": "PKT-04",
                    "severity": "blocker",
                    "summary": str(err),
                    "root_cause": "plan_gap",
                }
            )

    blockers = [i for i in issues if i.get("severity") == "blocker"]
    return {
        "ok": len(blockers) == 0,
        "issues": issues,
        "src_file_count": len(src_files),
        "diff_bytes": diff_bytes,
        "uvo_overall": uvo_overall,
        "diff_source": packet.get("diff_source", "unknown"),
    }


def main():
    p = argparse.ArgumentParser(description="Review packet deterministic preflight")
    p.add_argument("--packet", required=True, help="handoff/review-packet.json")
    p.add_argument("--uvo", default="", help="evidence/verification-oracle.json")
    p.add_argument("--task-dir", default="", help="infer uvo path from task dir")
    p.add_argument("--json", action="store_true", dest="as_json")
    args = p.parse_args()

    uvo_path = args.uvo
    if not uvo_path and args.task_dir:
        for cand in (
            os.path.join(args.task_dir, "evidence", "verification-oracle.json"),
            os.path.join(os.environ.get("GOAL_EVIDENCE_DIR", ""), "verification-oracle.json"),
        ):
            if cand and os.path.isfile(cand):
                uvo_path = cand
                break

    packet = json.load(open(args.packet, encoding="utf-8"))
    result = run_preflight(packet, uvo_path)

    if args.as_json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print("pass" if result["ok"] else "not_pass")

    sys.exit(0 if result["ok"] else 1)


if __name__ == "__main__":
    main()
