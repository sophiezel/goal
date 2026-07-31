#!/usr/bin/env python3
"""W2 L9 acceptance-matrix leakage (unsatisfied vs waived with separation)."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

_WAIVED_STATUSES = frozenset({"waive", "waived"})
_UNSATISFIED_STATUSES = frozenset({"fail", "failed", "not_pass", "unsatisfied", "open"})


def _load_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def _row_id(entry: Any) -> str:
    if isinstance(entry, str):
        return entry.strip()
    if isinstance(entry, dict):
        for key in ("row_id", "id", "matrix_row_id", "row"):
            val = entry.get(key)
            if val:
                return str(val).strip()
    return ""


def _has_valid_separation(entry: dict[str, Any]) -> bool:
    sep = entry.get("separation")
    if isinstance(sep, dict):
        if sep.get("valid") is True or sep.get("ok") is True:
            return True
        for key in ("ref", "pointer", "evidence", "path", "uri"):
            if str(sep.get(key) or "").strip():
                return True
        return False
    for key in ("separation_ref", "separation_evidence", "separation_pointer"):
        if str(entry.get(key) or "").strip():
            return True
    if isinstance(sep, str) and sep.strip():
        return True
    return False


def _normalize_row_entry(
    entry: Any,
    *,
    verify_type: str,
    evidence: str,
    source: str,
) -> dict[str, Any] | None:
    if isinstance(entry, str):
        rid = entry.strip()
        if not rid:
            return None
        return {
            "row_id": rid,
            "verify_type": verify_type,
            "evidence": evidence,
            "source": source,
            "status": "unsatisfied",
        }
    if not isinstance(entry, dict):
        return None
    rid = _row_id(entry)
    if not rid:
        return None
    status = str(entry.get("status") or entry.get("w2_status") or "unsatisfied").lower()
    return {
        "row_id": rid,
        "verify_type": str(entry.get("verify_type") or verify_type),
        "evidence": str(entry.get("evidence") or entry.get("evidence_ref") or evidence),
        "source": str(entry.get("source") or source),
        "status": status,
        "waive_reason": entry.get("waive_reason") or entry.get("reason"),
        "separation": entry.get("separation") or entry.get("separation_ref"),
    }


def _classify_row(row: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    """Return ('unsatisfied'|'waived'|'skip', payload)."""
    status = str(row.get("status") or "unsatisfied").lower()
    rid = row["row_id"]
    if status in _WAIVED_STATUSES:
        if _has_valid_separation(row):
            waived = {
                "row_id": rid,
                "verify_type": row.get("verify_type") or "handoff",
                "separation": row.get("separation") or row.get("separation_ref"),
                "waive_reason": row.get("waive_reason") or "",
                "evidence": row.get("evidence") or "",
                "source": row.get("source") or "handoff",
            }
            return "waived", waived
        uns = dict(row)
        uns["status"] = "unsatisfied"
        uns["evidence"] = uns.get("evidence") or "waive without valid separation (#16)"
        return "unsatisfied", uns
    if status in ("pass", "passed", "satisfied", "ok"):
        return "skip", row
    if status in _UNSATISFIED_STATUSES or status == "unsatisfied":
        return "unsatisfied", row
    return "unsatisfied", row


def _merge_row(
    by_id: dict[str, dict[str, Any]],
    row: dict[str, Any],
    bucket: str,
) -> None:
    rid = row["row_id"]
    existing = by_id.get(rid)
    if existing is None:
        by_id[rid] = {**row, "_bucket": bucket}
        return
    # unsatisfied wins over waived when both sources disagree
    if bucket == "unsatisfied" or existing.get("_bucket") == "unsatisfied":
        by_id[rid] = {**row, "_bucket": "unsatisfied"}
    elif bucket == "waived" and existing.get("_bucket") != "unsatisfied":
        by_id[rid] = {**row, "_bucket": "waived"}


def collect_handoff_matrix_satisfaction(handoff: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    unsatisfied: list[dict[str, Any]] = []
    waived: list[dict[str, Any]] = []
    by_id: dict[str, dict[str, Any]] = {}

    for name in ("plan.json", "review.json"):
        doc = _load_json(handoff / name)
        ms = doc.get("matrix_satisfaction")
        if not isinstance(ms, dict):
            continue
        if ms.get("ok") is True and not ms.get("rows"):
            break

        for entry in ms.get("rows") or []:
            row = _normalize_row_entry(entry, verify_type="handoff", evidence=name, source="matrix_satisfaction")
            if not row:
                continue
            kind, payload = _classify_row(row)
            if kind == "unsatisfied":
                _merge_row(by_id, payload, "unsatisfied")
            elif kind == "waived":
                _merge_row(by_id, payload, "waived")

        for entry in ms.get("waived_rows") or []:
            row = _normalize_row_entry(entry, verify_type="handoff", evidence=name, source="matrix_satisfaction")
            if not row:
                continue
            row["status"] = "waived"
            kind, payload = _classify_row(row)
            if kind == "waived":
                _merge_row(by_id, payload, "waived")
            elif kind == "unsatisfied":
                _merge_row(by_id, payload, "unsatisfied")

        legacy = ms.get("unsatisfied_rows") or ms.get("unsatisfied_row_ids") or []
        if not legacy and ms.get("ok") is False and not ms.get("rows"):
            legacy = ["(unspecified)"]
        for entry in legacy:
            row = _normalize_row_entry(entry, verify_type="handoff", evidence=name, source="matrix_satisfaction")
            if row:
                _merge_row(by_id, row, "unsatisfied")

        break

    for row in by_id.values():
        bucket = row.pop("_bucket", "unsatisfied")
        row.pop("status", None)
        if bucket == "waived":
            waived.append(row)
        else:
            unsatisfied.append(row)
    return unsatisfied, waived


def collect_ratchet_matrix_rows(goal_evidence: Path, handoff: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    unsatisfied: list[dict[str, Any]] = []
    waived: list[dict[str, Any]] = []
    ratchet_path = goal_evidence / "acceptance-matrix-ratchet.json"
    ratchet = _load_json(ratchet_path)
    if not ratchet:
        return unsatisfied, waived

    evidence_ref = str(ratchet_path.name)
    for entry in ratchet.get("matrix_rows") or []:
        row = _normalize_row_entry(entry, verify_type="am_ratchet", evidence=evidence_ref, source="acceptance-matrix-ratchet")
        if not row:
            continue
        kind, payload = _classify_row(row)
        if kind == "unsatisfied":
            unsatisfied.append(payload)
        elif kind == "waived":
            waived.append(payload)

    if ratchet.get("overall") == "not_pass" and not ratchet.get("matrix_rows"):
        plan = _load_json(handoff / "plan.json")
        ms = plan.get("matrix_satisfaction") if isinstance(plan.get("matrix_satisfaction"), dict) else {}
        for entry in ms.get("rows") or []:
            row = _normalize_row_entry(entry, verify_type="am_ratchet", evidence=evidence_ref, source="acceptance-matrix-ratchet")
            if not row:
                continue
            kind, payload = _classify_row(row)
            if kind == "unsatisfied":
                unsatisfied.append(payload)
            elif kind == "waived":
                waived.append(payload)

    return unsatisfied, waived


def collect_review_matrix_rows(goal_evidence: Path) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for fname in ("review-unified.json", "review-run.json"):
        doc = _load_json(goal_evidence / fname)
        if not doc:
            continue
        for issue in doc.get("issues") or []:
            if not isinstance(issue, dict):
                continue
            rid = _row_id(issue) or str(issue.get("matrix_row_id") or "").strip()
            tags = issue.get("tags") or issue.get("labels") or []
            if not rid and any("matrix" in str(t).lower() for t in tags):
                rid = str(issue.get("id") or "").strip()
            if not rid:
                continue
            passed = issue.get("passed")
            if passed is True:
                continue
            sev = str(issue.get("severity") or "").lower()
            if passed is False or sev in ("block", "blocker", "fail", "failed"):
                out.append(
                    {
                        "row_id": rid,
                        "verify_type": "review_rubric",
                        "evidence": fname,
                        "source": "review",
                    }
                )
        for item in doc.get("checklist_goal") or []:
            if not isinstance(item, dict):
                continue
            cid = str(item.get("id") or "")
            if cid.startswith(("C", "V", "AC", "TC")) and item.get("passed") is False:
                out.append(
                    {
                        "row_id": cid,
                        "verify_type": "review_rubric",
                        "evidence": fname,
                        "source": "review_checklist",
                    }
                )
    return out


def _dedupe_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_id: dict[str, dict[str, Any]] = {}
    for row in rows:
        rid = row.get("row_id")
        if not rid:
            continue
        by_id[str(rid)] = row
    return list(by_id.values())


def build_w2_matrix_leakage(*, handoff_dir: str, goal_evidence_dir: str) -> dict[str, Any]:
    handoff = Path(handoff_dir)
    goal_ev = Path(goal_evidence_dir)

    unsatisfied: list[dict[str, Any]] = []
    waived: list[dict[str, Any]] = []

    u1, w1 = collect_handoff_matrix_satisfaction(handoff)
    unsatisfied.extend(u1)
    waived.extend(w1)

    u2, w2 = collect_ratchet_matrix_rows(goal_ev, handoff)
    unsatisfied.extend(u2)
    waived.extend(w2)

    unsatisfied.extend(collect_review_matrix_rows(goal_ev))

    waived_ids = {r["row_id"] for r in waived}
    unsatisfied = [r for r in _dedupe_rows(unsatisfied) if r["row_id"] not in waived_ids]
    waived = _dedupe_rows(waived)

    out: dict[str, Any] = {"w2_bookkeeping_version": 1}
    if unsatisfied:
        out["matrix_rows_unsatisfied"] = unsatisfied
    if waived:
        out["matrix_rows_waived"] = waived
    return out


def matrix_row_ids(leakage: dict[str, Any]) -> list[str]:
    rows = leakage.get("matrix_rows_unsatisfied") or []
    ids: list[str] = []
    for r in rows:
        if isinstance(r, str):
            ids.append(r)
        elif isinstance(r, dict) and r.get("row_id"):
            ids.append(str(r["row_id"]))
    return ids


def matrix_satisfaction_plane_notes(handoff: Path, goal_evidence: Path) -> list[dict[str, Any]]:
    """Quality-plane W2 notes (does not hard-block complete)."""
    leakage = build_w2_matrix_leakage(handoff_dir=str(handoff), goal_evidence_dir=str(goal_evidence))
    ids = matrix_row_ids(leakage)
    if not ids:
        return []
    return [
        {
            "failure_code": "matrix_row_unsatisfied",
            "summary": f"acceptance matrix unsatisfied rows: {', '.join(ids)}",
            "leakage": {"w2_matrix_row_unsatisfied": ids},
        }
    ]


def merge_w2_into_leakage(base: dict[str, Any], w2: dict[str, Any]) -> dict[str, Any]:
    merged = dict(base)
    if w2.get("matrix_rows_unsatisfied"):
        merged["matrix_rows_unsatisfied"] = w2["matrix_rows_unsatisfied"]
    if w2.get("matrix_rows_waived"):
        merged["matrix_rows_waived"] = w2["matrix_rows_waived"]
    return merged


def main() -> int:
    import argparse

    ap = argparse.ArgumentParser(description="W2 matrix row leakage bookkeeping")
    ap.add_argument("--handoff-dir", required=True)
    ap.add_argument("--goal-evidence-dir", required=True)
    ap.add_argument("--format", choices=("json", "text"), default="json")
    args = ap.parse_args()
    payload = build_w2_matrix_leakage(handoff_dir=args.handoff_dir, goal_evidence_dir=args.goal_evidence_dir)
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
