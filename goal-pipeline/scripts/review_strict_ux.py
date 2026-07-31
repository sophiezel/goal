#!/usr/bin/env python3
"""Strict-tier UX/L10 review-first issues (merge-review augmentation)."""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any


_W1_CLOSED = frozenset({"pass", "waive", "deferred", "waived"})


def _load_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def resolve_quality_tier(state_file: str) -> str:
    if not state_file or not os.path.isfile(state_file):
        return "standard"
    try:
        state = json.loads(Path(state_file).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return "standard"
    return str((state.get("quality_policy") or {}).get("tier") or "standard").lower()


def collect_strict_ux_issues(
    *,
    handoff_dir: str,
    goal_evidence_dir: str,
    state_file: str = "",
) -> list[dict[str, Any]]:
    """When tier=strict, open L10 manifest / ux-scan items become review blockers (review-first)."""
    if resolve_quality_tier(state_file) != "strict":
        return []

    issues: list[dict[str, Any]] = []
    handoff = Path(handoff_dir)
    goal_ev = Path(goal_evidence_dir)

    manifest = _load_json(handoff / "argus-scenario-manifest.json")
    for row in manifest.get("scenarios") or []:
        status = str(row.get("w1_status") or "open").lower()
        if status in _W1_CLOSED:
            continue
        sid = str(row.get("id") or "L10")
        issues.append(
            {
                "id": f"UX-STRICT-L10-{sid}",
                "channel": "goal",
                "severity": "blocker",
                "summary": f"strict tier: L10 manifest row '{sid}' not pass/waive/deferred (w1_status={status})",
                "root_cause": "ux_policy",
                "suggestion": "fix UX, waive with separation, or defer with evidence before review pass",
            }
        )

    ux = _load_json(goal_ev / "ux-scan.json")
    for f in ux.get("findings") or []:
        status = str(f.get("w1_status") or "open").lower()
        if status in _W1_CLOSED:
            continue
        fid = str(f.get("id") or "UX")
        sev = str(f.get("severity") or "warn").lower()
        issues.append(
            {
                "id": f"UX-STRICT-{fid}",
                "channel": "goal",
                "severity": "blocker",
                "summary": f"strict tier: ux-scan {fid} ({sev}) without disposition",
                "root_cause": "ux_policy",
                "suggestion": "resolve finding, waive, or defer — do not hard-block implement post on L10 alone in standard tier",
            }
        )

    return issues


def main() -> int:
    import argparse

    ap = argparse.ArgumentParser()
    ap.add_argument("--handoff-dir", required=True)
    ap.add_argument("--goal-evidence-dir", required=True)
    ap.add_argument("--state-file", default="")
    ap.add_argument("--format", choices=("json", "text"), default="json")
    args = ap.parse_args()
    issues = collect_strict_ux_issues(
        handoff_dir=args.handoff_dir,
        goal_evidence_dir=args.goal_evidence_dir,
        state_file=args.state_file,
    )
    if args.format == "text":
        for i in issues:
            print(f"{i['id']}: {i['summary']}")
    else:
        print(json.dumps({"issues": issues, "count": len(issues)}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
