#!/usr/bin/env python3
"""W1 leakage bookkeeping for complete / delivery-quality (L10 manifest + ux-scan)."""
from __future__ import annotations

import json
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


def build_w1_leakage(*, handoff_dir: str, goal_evidence_dir: str) -> dict[str, Any]:
    handoff = Path(handoff_dir)
    goal_ev = Path(goal_evidence_dir)
    silent: list[str] = []
    l10_rows: dict[str, str] = {}
    ux_rows: dict[str, str] = {}

    manifest = _load_json(handoff / "argus-scenario-manifest.json")
    for row in manifest.get("scenarios") or []:
        sid = str(row.get("id") or "unknown")
        status = str(row.get("w1_status") or "open").lower()
        l10_rows[sid] = status
        if status not in _W1_CLOSED:
            silent.append(f"L10:{sid}")

    ux = _load_json(goal_ev / "ux-scan.json")
    for f in ux.get("findings") or []:
        fid = str(f.get("id") or "UX")
        status = str(f.get("w1_status") or "open").lower()
        ux_rows[fid] = status
        if status not in _W1_CLOSED and str(f.get("severity") or "").lower() in (
            "block",
            "blocker",
            "high",
        ):
            silent.append(f"UX:{fid}")

    return {
        "declared_defect_classes_silent_pass": silent,
        "l10_manifest_w1_status": l10_rows,
        "ux_scan_w1_status": ux_rows,
        "w1_bookkeeping_version": 1,
    }


def merge_into_delivery_quality(delivery_path: str, leakage: dict[str, Any]) -> None:
    path = Path(delivery_path)
    doc = _load_json(path) if path.is_file() else {"schema_version": 2}
    doc.setdefault("leakage", {})
    doc["leakage"].update(leakage)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    import argparse

    ap = argparse.ArgumentParser()
    ap.add_argument("--handoff-dir", required=True)
    ap.add_argument("--goal-evidence-dir", required=True)
    ap.add_argument("--delivery-quality", default="")
    ap.add_argument("--format", choices=("json", "text"), default="json")
    args = ap.parse_args()
    leakage = build_w1_leakage(handoff_dir=args.handoff_dir, goal_evidence_dir=args.goal_evidence_dir)
    if args.delivery_quality:
        merge_into_delivery_quality(args.delivery_quality, leakage)
    if args.format == "text":
        print(json.dumps(leakage, ensure_ascii=False, indent=2))
    else:
        print(json.dumps(leakage, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
