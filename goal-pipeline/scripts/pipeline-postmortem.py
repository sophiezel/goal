#!/usr/bin/env python3
"""pipeline-postmortem — Emit short blocked/SLA postmortem from state + timing.

Usage:
  pipeline-postmortem.py --state-file PATH [--task-dir PATH] [--project-root PATH] [--format json]
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--state-file", required=True)
    ap.add_argument("--task-dir", default="")
    ap.add_argument("--project-root", default="")
    ap.add_argument("--format", choices=("json", "text"), default="json")
    args = ap.parse_args()

    state = json.loads(Path(args.state_file).read_text(encoding="utf-8"))
    failure = state.get("failure_code") or ""
    status = state.get("status") or ""
    stage = state.get("current_stage") or ""

    timing = {}
    if args.task_dir:
        # best-effort read under task evidence
        for cand in (
            Path(args.task_dir) / "evidence" / "pipeline-timing.json",
        ):
            if cand.is_file():
                try:
                    timing = json.loads(cand.read_text(encoding="utf-8"))
                except json.JSONDecodeError:
                    pass
                break

    recommendations = []
    if failure == "plan_code_order":
        recommendations.append("stash/reset guarded src diffs; finish gate --post plan before code")
    if failure == "noop_fix":
        recommendations.append("do not rerun same gate; change subject_hash via substantive fix")
    if failure in ("review_undetermined", "review_channel_missing"):
        recommendations.append("configure review channel or accept separation=degraded")
    if not recommendations and status == "blocked":
        recommendations.append("read evidence/*-gate-fix-input.json next_steps")

    report = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "status": status,
        "current_stage": stage,
        "failure_code": failure,
        "timing_timezone": timing.get("timezone", "UTC"),
        "stages_timed": list((timing.get("stages") or {}).keys()),
        "recommendations": recommendations,
        "sla_hints": {
            "target_total_min": "40-50",
            "zero_plan_code_order_leaks": True,
        },
    }

    if args.format == "text":
        print(f"postmortem status={status} stage={stage} failure={failure}")
        for r in recommendations:
            print(f"- {r}")
    else:
        print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
