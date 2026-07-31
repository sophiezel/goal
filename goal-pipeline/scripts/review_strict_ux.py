#!/usr/bin/env python3
"""Strict-tier UX/L10 review-first issues (merge-review augmentation)."""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

_W1_CLOSED = frozenset({"pass", "waive", "deferred", "waived"})
_SOFT_SEVERITY = frozenset({"soft", "warn", "info", "low"})
_UX_BLOCK_SEVERITY = frozenset({"block", "blocker", "hard", "critical"})


def _load_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def l10_row_blocks_strict_review(row: dict) -> bool:
    """B3-aligned: soft+open L10 does not block review; hard/escalated open rows do."""
    status = str(row.get("w1_status") or "open").lower()
    if status in _W1_CLOSED:
        return False
    if row.get("escalated_to_l9") or row.get("l9_escalated"):
        return True
    severity = str(row.get("severity") or "soft").lower()
    if severity in _UX_BLOCK_SEVERITY:
        return True
    if severity in _SOFT_SEVERITY:
        return False
    return False


def ux_finding_blocks_strict_review(finding: dict) -> bool:
    """Strict review: only blocker/hard open ux-scan findings are review blockers."""
    status = str(finding.get("w1_status") or "open").lower()
    if status in _W1_CLOSED:
        return False
    severity = str(finding.get("severity") or "warn").lower()
    if severity in _UX_BLOCK_SEVERITY:
        return True
    if severity in _SOFT_SEVERITY:
        return False
    return False


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
    """When tier=strict, open hard L10 / ux-scan blocker findings become review blockers (review-first)."""
    if resolve_quality_tier(state_file) != "strict":
        return []

    issues: list[dict[str, Any]] = []
    handoff = Path(handoff_dir)
    goal_ev = Path(goal_evidence_dir)

    manifest = _load_json(handoff / "argus-scenario-manifest.json")
    for row in manifest.get("scenarios") or []:
        if not l10_row_blocks_strict_review(row):
            continue
        sid = str(row.get("id") or "L10")
        sev = str(row.get("severity") or "hard").lower()
        issues.append(
            {
                "id": f"UX-STRICT-L10-{sid}",
                "channel": "goal",
                "severity": "blocker",
                "summary": f"strict tier: L10 manifest row '{sid}' ({sev}) without disposition",
                "root_cause": "ux_policy",
                "suggestion": "fix UX, waive with separation, or defer with evidence before review pass",
            }
        )

    ux = _load_json(goal_ev / "ux-scan.json")
    for f in ux.get("findings") or []:
        if not ux_finding_blocks_strict_review(f):
            continue
        fid = str(f.get("id") or "UX")
        sev = str(f.get("severity") or "blocker").lower()
        issues.append(
            {
                "id": f"UX-STRICT-{fid}",
                "channel": "goal",
                "severity": "blocker",
                "summary": f"strict tier: ux-scan {fid} ({sev}) without disposition",
                "root_cause": "ux_policy",
                "suggestion": "resolve finding, waive, or defer before review pass",
            }
        )

    return issues


def collect_strict_ux_warn_issues(
    *,
    handoff_dir: str,
    goal_evidence_dir: str,
    state_file: str = "",
) -> list[dict[str, Any]]:
    """Strict tier: open soft L10 / ux-scan warn findings — issues with warn severity, not review blockers."""
    if resolve_quality_tier(state_file) != "strict":
        return []

    issues: list[dict[str, Any]] = []
    handoff = Path(handoff_dir)
    goal_ev = Path(goal_evidence_dir)

    manifest = _load_json(handoff / "argus-scenario-manifest.json")
    for row in manifest.get("scenarios") or []:
        status = str(row.get("w1_status") or "open").lower()
        if status in _W1_CLOSED or l10_row_blocks_strict_review(row):
            continue
        sid = str(row.get("id") or "L10")
        sev = str(row.get("severity") or "soft").lower()
        issues.append(
            {
                "id": f"UX-STRICT-WARN-L10-{sid}",
                "channel": "goal",
                "severity": "warn",
                "summary": f"strict tier: L10 manifest row '{sid}' ({sev}) open — track in W1 debt",
                "root_cause": "ux_policy",
                "suggestion": "waive/defer with evidence or fix before ship",
            }
        )

    ux = _load_json(goal_ev / "ux-scan.json")
    for f in ux.get("findings") or []:
        if ux_finding_blocks_strict_review(f):
            continue
        status = str(f.get("w1_status") or "open").lower()
        if status in _W1_CLOSED:
            continue
        severity = str(f.get("severity") or "warn").lower()
        if severity not in _SOFT_SEVERITY:
            continue
        fid = str(f.get("id") or "UX")
        issues.append(
            {
                "id": f"UX-STRICT-WARN-{fid}",
                "channel": "goal",
                "severity": "warn",
                "summary": f"strict tier: ux-scan {fid} ({severity}) without disposition",
                "root_cause": "ux_policy",
                "suggestion": "resolve, waive, or defer — does not alone fail review",
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
