#!/usr/bin/env python3
"""Resolve goal-quality validate/e2e expectations by profile + tier (#19 SSOT)."""
from __future__ import annotations

import argparse
import json
import os
import re
from typing import Any

Severity = str  # none | warn | block


def _front_matter(path: str) -> dict[str, str]:
    if not os.path.isfile(path):
        return {}
    text = open(path, encoding="utf-8").read()
    m = re.match(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return {}
    out: dict[str, str] = {}
    for line in m.group(1).splitlines():
        s = line.strip()
        if ":" in s:
            k, v = s.split(":", 1)
            out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def _load_plan_handoff(task_dir: str) -> dict[str, Any]:
    handoff = os.path.join(task_dir, "handoff", "plan.json")
    if not os.path.isfile(handoff):
        return {}
    try:
        return json.load(open(handoff, encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def resolve_plan_profile(task_dir: str, plan: dict[str, Any] | None = None) -> str:
    plan = plan if plan is not None else _load_plan_handoff(task_dir)
    pp = str(plan.get("plan_profile") or "").lower()
    if pp in ("lite", "full"):
        return pp
    fm = _front_matter(os.path.join(task_dir, "index.md"))
    fm_pp = str(fm.get("plan_profile") or "").lower()
    if fm_pp in ("lite", "full"):
        return fm_pp
    tier_fm = str(fm.get("task_tier") or "").upper()
    if tier_fm in ("XS", "S"):
        return "lite"
    return "full"


def resolve_repo_profile(task_dir: str, plan: dict[str, Any] | None = None) -> str:
    plan = plan if plan is not None else _load_plan_handoff(task_dir)
    prof = str(plan.get("profile") or "").lower()
    if prof:
        return prof
    fm = _front_matter(os.path.join(task_dir, "index.md"))
    return str(fm.get("profile") or "").lower()


def agent_orchestration_defaults(quality_tier: str, plan_profile: str, repo_profile: str) -> dict[str, str]:
    """What goal-quality Agent should run before quality-gate (not enforced by gate except strict refs)."""
    tier = quality_tier.lower()
    if tier != "strict":
        return {
            "runtime_smoke": "required_or_pattern_skip",
            "validate": "optional",
            "e2e": "off_default",
            "test_lint": "uvo_at_implement",
        }
    e2e = "recommended" if repo_profile == "h5" else "optional"
    if plan_profile == "lite":
        e2e = "off_default" if repo_profile != "h5" else "recommended"
    return {
        "runtime_smoke": "required_or_pattern_skip",
        "validate": "recommended",
        "e2e": e2e,
        "test_lint": "uvo_at_implement",
    }


def gate_validate_severity(quality_tier: str) -> Severity:
    return "warn" if quality_tier.lower() == "strict" else "none"


def gate_e2e_severity(quality_tier: str, repo_profile: str) -> Severity:
    if quality_tier.lower() != "strict":
        return "none"
    return "block" if repo_profile == "h5" else "warn"


def e2e_evidence_present(task_dir: str, evidence_dir: str | None = None) -> bool:
    ev = evidence_dir or os.environ.get("GOAL_EVIDENCE_DIR") or os.path.join(task_dir, "evidence")
    if os.path.isdir(os.path.join(ev, "e2e")):
        return True
    if os.path.isdir(os.path.join(task_dir, "evidence", "e2e")):
        return True
    index = os.path.join(task_dir, "index.md")
    if os.path.isfile(index):
        text = open(index, encoding="utf-8").read()
        if re.search(r"playwright", text, re.I):
            return True
    return False


def index_mentions_validate(task_dir: str) -> bool:
    index = os.path.join(task_dir, "index.md")
    if not os.path.isfile(index):
        return False
    return bool(re.search(r"validate", open(index, encoding="utf-8").read(), re.I))


def resolve_policy(
    task_dir: str,
    *,
    quality_tier: str = "standard",
    evidence_dir: str | None = None,
) -> dict[str, Any]:
    plan = _load_plan_handoff(task_dir)
    plan_profile = resolve_plan_profile(task_dir, plan)
    repo_profile = resolve_repo_profile(task_dir, plan)
    tier = quality_tier.lower()

    val_sev = gate_validate_severity(tier)
    e2e_sev = gate_e2e_severity(tier, repo_profile)
    agent = agent_orchestration_defaults(tier, plan_profile, repo_profile)

    return {
        "quality_tier": tier,
        "plan_profile": plan_profile,
        "repo_profile": repo_profile,
        "agent": agent,
        "gate": {
            "validate_index_ref": val_sev,
            "e2e_evidence": e2e_sev,
            "iq_structural": "implement_post_only",
            "uvo_test_build": "implement_post_only",
        },
        "dedupe": {
            "quality_gate_skip_iq": "gate-lib/quality.sh passes --skip-iq; IQ structural ran at implement post",
            "uvo_vs_e2e": "UVO runs test/lint/build; e2e Playwright is separate agent step — no double block on test exit",
            "pq_matrix_vs_qg_e2e": "PQ-08 matrix verify_command is planning contract; QG-L1-e2e is strict evidence ref only",
        },
        "evidence": {
            "e2e_present": e2e_evidence_present(task_dir, evidence_dir),
            "validate_mentioned": index_mentions_validate(task_dir),
        },
    }


def main() -> int:
    p = argparse.ArgumentParser(description="goal-quality e2e/validate profile policy (#19)")
    p.add_argument("--task-dir", required=True)
    p.add_argument("--tier", default="standard")
    p.add_argument("--json", action="store_true", dest="as_json")
    args = p.parse_args()
    out = resolve_policy(args.task_dir, quality_tier=args.tier)
    if args.as_json:
        print(json.dumps(out, ensure_ascii=False, indent=2))
    else:
        print(out["gate"]["e2e_evidence"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
