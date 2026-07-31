#!/usr/bin/env python3
"""W1 leakage bookkeeping for complete / delivery-quality (L10 manifest + ux-scan)."""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from l10_w1_policy import W1_CLOSED as _W1_CLOSED
from l10_w1_policy import l10_row_blocks_complete


def _load_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def _matrix_rows_from_handoff(handoff: Path) -> list[str]:
    """W2-only matrix row ids from host handoff matrix_satisfaction (no complete hard block)."""
    rows_out: list[str] = []
    for name in ("plan.json", "review.json"):
        doc = _load_json(handoff / name)
        ms = doc.get("matrix_satisfaction")
        if not isinstance(ms, dict):
            continue
        if ms.get("ok") is True:
            break
        rows = ms.get("unsatisfied_rows") or ms.get("unsatisfied_row_ids") or []
        if not rows and ms.get("ok") is False:
            rows = ["(unspecified)"]
        rows_out.extend(str(r) for r in rows)
        break
    return rows_out


def build_w1_leakage(*, handoff_dir: str, goal_evidence_dir: str) -> dict[str, Any]:
    handoff = Path(handoff_dir)
    goal_ev = Path(goal_evidence_dir)
    silent: list[str] = []
    soft_l10_debt: list[str] = []
    matrix_rows_unsatisfied = _matrix_rows_from_handoff(handoff)
    l10_rows: dict[str, str] = {}
    ux_rows: dict[str, str] = {}

    manifest = _load_json(handoff / "argus-scenario-manifest.json")
    for row in manifest.get("scenarios") or []:
        sid = str(row.get("id") or "unknown")
        status = str(row.get("w1_status") or "open").lower()
        l10_rows[sid] = status
        if status not in _W1_CLOSED:
            if l10_row_blocks_complete(row):
                silent.append(f"L10:{sid}")
            else:
                soft_l10_debt.append(f"L10:{sid}")

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

    out: dict[str, Any] = {
        "declared_defect_classes_silent_pass": silent,
        "w1_open_soft_l10_debt": soft_l10_debt,
        "l10_manifest_w1_status": l10_rows,
        "ux_scan_w1_status": ux_rows,
        "w1_bookkeeping_version": 2,
    }
    if matrix_rows_unsatisfied:
        out["matrix_rows_unsatisfied"] = matrix_rows_unsatisfied
    return out


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
