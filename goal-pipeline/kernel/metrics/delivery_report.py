#!/usr/bin/env python3
"""Build delivery-quality.json v2 and ADR-0004 completeness checks."""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from typing import Any

V2_METRIC_KEYS = (
    ("timing", "plan_ms"),
    ("timing", "review_ms"),
    ("review_provenance", "model_invocations"),
    ("loops", "review_rounds"),
)


def _ms_for(stages_t: dict, name: str) -> int:
    ent = stages_t.get(name) or {}
    if isinstance(ent, dict):
        return int(ent.get("wall_ms") or ent.get("ms") or 0)
    return 0


def build_delivery_report(
    *,
    handoff: str,
    goal_evidence: str,
    repo_task: str,
    pipeline_id: str = "guazi-flow-goal",
    state_file: str = "",
) -> dict[str, Any]:
    stages = ["plan", "implement", "quality", "review", "complete"]
    chain: dict[str, bool] = {}
    stages_summary: dict[str, Any] = {}
    for s in stages:
        p = os.path.join(handoff, f"{s}.json")
        if s == "quality" and not os.path.isfile(p):
            p = os.path.join(handoff, "smoke.json")
        exists = os.path.isfile(p)
        chain[s] = exists
        if exists:
            try:
                d = json.load(open(p, encoding="utf-8"))
                stages_summary[s] = {
                    "gate_passed_at": (d.get("gate") or {}).get("passed_at", ""),
                    "post_exit_code": (d.get("gate") or {}).get("post_exit_code", ""),
                }
            except (OSError, json.JSONDecodeError):
                stages_summary[s] = {}

    all_complete = all(chain.values())
    leak = 0.0
    escape_path = os.path.join(goal_evidence, "escape-register.json")
    if not os.path.isfile(escape_path):
        escape_path = os.path.join(repo_task, "evidence", "escape-register.json")
    if os.path.isfile(escape_path):
        try:
            er = json.load(open(escape_path, encoding="utf-8"))
            for e in er.get("escapes", []):
                if os.path.abspath(e.get("task_dir", "")) == os.path.abspath(repo_task):
                    leak = 1.0
                    break
        except (OSError, json.JSONDecodeError):
            pass

    task_tier = plan_profile = review_track = ""
    plan_path = os.path.join(handoff, "plan.json")
    if os.path.isfile(plan_path):
        try:
            plan = json.load(open(plan_path, encoding="utf-8"))
            task_tier = plan.get("task_tier", "") or plan.get("tier", "")
            plan_profile = plan.get("plan_profile", "full")
        except (OSError, json.JSONDecodeError):
            pass

    state: dict[str, Any] = {}
    if state_file and os.path.isfile(state_file):
        try:
            state = json.load(open(state_file, encoding="utf-8"))
            task_tier = task_tier or state.get("task_tier", "")
            review_track = (state.get("review_policy") or {}).get("track", "")
            if not review_track:
                review_track = state.get("review_track") or ""
        except (OSError, json.JSONDecodeError):
            pass

    timing: dict[str, Any] = {"source": "evidence/pipeline-timing.json"}
    timing_path = os.path.join(goal_evidence, "pipeline-timing.json")
    if not os.path.isfile(timing_path):
        timing_path = os.path.join(repo_task, "evidence", "pipeline-timing.json")
    if os.path.isfile(timing_path):
        try:
            pt = json.load(open(timing_path, encoding="utf-8"))
            stages_t = pt.get("stages") or pt.get("by_stage") or {}
            timing.update(
                {
                    "plan_ms": _ms_for(stages_t, "plan"),
                    "implement_ms": _ms_for(stages_t, "implement"),
                    "quality_ms": _ms_for(stages_t, "quality") or _ms_for(stages_t, "smoke"),
                    "review_ms": _ms_for(stages_t, "review"),
                    "total_ms": int(pt.get("total_ms") or pt.get("wall_ms_total") or 0),
                }
            )
        except (OSError, json.JSONDecodeError):
            pass

    review_prov: dict[str, Any] = {
        "model_invocations": 0,
        "latency_ms": 0,
        "provider": "",
        "model": "",
        "channels_used": [],
        "issues_goal": 0,
        "issues_gf": 0,
    }
    run_path = os.path.join(goal_evidence, "review-run.json")
    if os.path.isfile(run_path):
        try:
            run = json.load(open(run_path, encoding="utf-8"))
            review_prov["model_invocations"] = int(run.get("invocation_count") or 1)
            review_prov["latency_ms"] = int(run.get("latency_ms") or 0)
            review_prov["provider"] = run.get("provider", "")
            review_prov["model"] = run.get("model", "")
            review_prov["channels_used"] = run.get("channels") or []
        except (OSError, json.JSONDecodeError):
            pass

    fix_path = os.path.join(goal_evidence, "review-fix-input.json")
    loops: dict[str, Any] = {
        "review_rounds": 0,
        "replan_count": int(state.get("replan_count") or 0),
        "stagnant_blocked": False,
        "final_action": "",
        "first_pass": False,
    }
    if os.path.isfile(fix_path):
        try:
            fix = json.load(open(fix_path, encoding="utf-8"))
            loops["review_rounds"] = int(fix.get("round") or 0)
            loops["stagnant_blocked"] = bool(fix.get("stagnant_blocked"))
            loops["final_action"] = fix.get("action", "")
            loops["first_pass"] = loops["review_rounds"] <= 1 and fix.get("merged_result") == "pass"
            review_prov["issues_goal"] = sum(
                1 for i in fix.get("issues", []) if i.get("channel") != "guazi-flow-review"
            )
            review_prov["issues_gf"] = sum(
                1 for i in fix.get("issues", []) if i.get("channel") == "guazi-flow-review"
            )
        except (OSError, json.JSONDecodeError):
            pass

    handoff_cov = sum(1 for v in chain.values() if v) / max(len(chain), 1)
    blocker_final = 0
    if os.path.isfile(fix_path):
        try:
            blocker_final = int(json.load(open(fix_path, encoding="utf-8")).get("blocker_count") or 0)
        except (OSError, json.JSONDecodeError):
            pass

    gate_status = "OK" if (all_complete and leak == 0.0) else "BLOCK"

    def _gate_evidence_rollup(*dirs: str) -> list[dict[str, Any]]:
        """Generic rollup: any evidence JSON with a top-level ``passed`` (gate outcome), not fix-input."""
        roll: list[dict[str, Any]] = []
        seen: set[str] = set()
        skip_fragments = ("fix-input", "review-packet", "review-run", "pipeline-timing", "escape-register")
        for base in dirs:
            if not base or not os.path.isdir(base):
                continue
            for name in sorted(os.listdir(base)):
                if not name.endswith(".json"):
                    continue
                if any(f in name for f in skip_fragments):
                    continue
                path = os.path.join(base, name)
                if path in seen:
                    continue
                try:
                    doc = json.load(open(path, encoding="utf-8"))
                except (OSError, json.JSONDecodeError):
                    continue
                if not isinstance(doc, dict) or "passed" not in doc:
                    continue
                seen.add(path)
                entry: dict[str, Any] = {
                    "artifact": name,
                    "passed": bool(doc.get("passed")),
                    "issue_count": len(doc.get("issues") or []),
                }
                if "skipped" in doc:
                    entry["skipped"] = bool(doc.get("skipped"))
                roll.append(entry)
        return roll

    gate_evidence_rollup = _gate_evidence_rollup(goal_evidence, os.path.join(repo_task, "evidence"))

    report: dict[str, Any] = {
        "schema_version": 2,
        "pipeline_id": pipeline_id,
        "task_dir": repo_task,
        "computed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "chain_complete": chain,
        "leak_rate": leak,
        "gate_status": gate_status,
        "stages_summary": stages_summary,
        "task_tier": task_tier,
        "plan_profile": plan_profile,
        "review_track": review_track,
        "timing": timing,
        "review_provenance": review_prov,
        "loops": loops,
        "quality_summary": {
            "blocker_count_final": blocker_final,
            "leak_rate": leak,
            "handoff_coverage": round(handoff_cov, 4),
        },
        "gate_evidence_rollup": gate_evidence_rollup,
    }
    warnings = v2_completeness_warnings(report)
    if warnings:
        report["incomplete_metrics"] = warnings
    return report


def v2_completeness_warnings(report: dict[str, Any]) -> list[str]:
    """ADR-0004: missing v2 metric fields → warn list (non-fatal unless strict tier)."""
    warnings: list[str] = []
    for section, key in V2_METRIC_KEYS:
        block = report.get(section) or {}
        if key not in block:
            warnings.append(f"{section}.{key}")
    return warnings


def resolve_quality_tier(state_file: str) -> str:
    if not state_file or not os.path.isfile(state_file):
        return "standard"
    try:
        state = json.load(open(state_file, encoding="utf-8"))
        return (state.get("quality_policy") or {}).get("tier") or "standard"
    except (OSError, json.JSONDecodeError):
        return "standard"


def adr0004_gate(report_path: str, state_file: str = "") -> tuple[int, list[str]]:
    """Return (exit_code, messages). strict tier + incomplete → exit 2."""
    if not os.path.isfile(report_path):
        return 2, ["delivery-quality.json missing"]
    try:
        doc = json.load(open(report_path, encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        return 2, [f"delivery-quality invalid: {e}"]
    warnings = doc.get("incomplete_metrics") or v2_completeness_warnings(doc)
    tier = resolve_quality_tier(state_file)
    if tier == "strict" and warnings:
        return 2, [f"ADR-0004 strict tier: incomplete delivery metrics: {', '.join(warnings)}"]
    return 0, warnings


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--handoff", default="")
    p.add_argument("--goal-evidence", default="")
    p.add_argument("--repo-task", default="")
    p.add_argument("--output", required=True)
    p.add_argument("--state-file", default="")
    p.add_argument("--pipeline-id", default="guazi-flow-goal")
    p.add_argument("--adr-check", action="store_true", help="ADR-0004 only (report must exist at --output)")
    args = p.parse_args()
    if args.adr_check:
        code, msgs = adr0004_gate(args.output, args.state_file)
        for m in msgs:
            print(m, file=sys.stderr if code else sys.stdout)
        return code
    if not args.handoff or not args.goal_evidence or not args.repo_task:
        print("delivery_report: --handoff --goal-evidence --repo-task required", file=sys.stderr)
        return 2
    report = build_delivery_report(
        handoff=args.handoff,
        goal_evidence=args.goal_evidence,
        repo_task=args.repo_task,
        pipeline_id=args.pipeline_id,
        state_file=args.state_file,
    )
    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
