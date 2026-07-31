#!/usr/bin/env python3
"""quality_plane_check — Block silent pass / forged review / illegal UVO skip at complete or audit."""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from l10_w1_policy import l10_row_blocks_complete


def load_json(p: Path) -> dict:
    if not p.is_file():
        return {}
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def matrix_satisfaction_errors(handoff: Path) -> list[dict]:
    """Optional host handoff matrix_satisfaction — no-op when field absent."""
    errors: list[dict] = []
    for name in ("plan.json", "review.json"):
        doc = load_json(handoff / name)
        ms = doc.get("matrix_satisfaction")
        if not isinstance(ms, dict):
            continue
        if ms.get("ok") is True:
            continue
        rows = ms.get("unsatisfied_rows") or ms.get("unsatisfied_row_ids") or []
        if not rows and ms.get("ok") is False:
            rows = ["(unspecified)"]
        if rows:
            errors.append(
                {
                    "failure_code": "matrix_row_unsatisfied",
                    "summary": f"acceptance matrix unsatisfied rows: {', '.join(str(r) for r in rows)}",
                    "leakage": {"w2_matrix_row_unsatisfied": [str(r) for r in rows]},
                }
            )
        break
    return errors


def resolve_dirs(task_dir: str, state_file: str, project_root: str) -> tuple[Path, Path]:
    script_dir = Path(__file__).resolve().parent
    resolver = script_dir / "resolve-artifact-paths.py"
    if resolver.is_file():
        import subprocess

        args = [sys.executable, str(resolver), "--task-dir", task_dir, "--format", "json"]
        if state_file:
            args.extend(["--state-file", state_file])
        if project_root:
            args.extend(["--project-root", project_root])
        r = subprocess.run(args, capture_output=True, text=True, check=True)
        d = json.loads(r.stdout)
        return Path(d["repo_evidence_dir"]), Path(d["goal_evidence_dir"])
    t = Path(task_dir)
    return t / "evidence", t / "evidence"


def review_frontmatter(text: str) -> dict:
    m = re.match(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return {}
    out = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--task-dir", required=True)
    ap.add_argument("--state-file", default="")
    ap.add_argument("--project-root", default="")
    ap.add_argument("--mode", choices=("complete", "audit"), default="complete")
    ap.add_argument("--format", choices=("json", "text"), default="json")
    args = ap.parse_args()

    repo_ev, goal_ev = resolve_dirs(args.task_dir, args.state_file, args.project_root)
    errors: list[dict] = []
    matrix_w2: list[dict] = []

    review_md = repo_ev / "review.md"
    run = goal_ev / "review-run.json"
    unified = goal_ev / "review-unified.json"
    degraded = goal_ev / "review-channel-degraded.json"
    uvo = goal_ev / "verification-oracle.json"

    if review_md.is_file():
        fm = review_frontmatter(review_md.read_text(encoding="utf-8"))
        result = (fm.get("result") or "").lower()
        conf = (fm.get("confidence") or fm.get("separation") or "").lower()
        if result == "pass" and not run.is_file() and not unified.is_file():
            # allow skip only if explicitly skipped classification? else forged
            errors.append({"failure_code": "review_forged", "summary": "review.md pass without review-run/unified"})
        if result == "pass" and degraded.is_file() and conf not in ("degraded", "low", "medium"):
            # degraded evidence exists but review claims full pass without confidence tag
            deg = load_json(degraded)
            if deg.get("separation") == "degraded" and conf != "degraded":
                errors.append(
                    {
                        "failure_code": "review_degraded_as_pass",
                        "summary": "channel degraded but review.md missing confidence: degraded",
                    }
                )

    if args.mode == "complete":
        # UVO should exist for any completed implement path
        impl_handoff = Path(args.task_dir) / "handoff" / "implement.json"
        # also check runtime handoff via resolver parent
        if not uvo.is_file() and impl_handoff.is_file():
            # split mode: uvo in goal_ev
            pass
        st = load_json(Path(args.state_file)) if args.state_file else {}
        stages = st.get("guazi_flow_stages") or {}
        if stages.get("implement", {}).get("gate", {}).get("passed_at") and not uvo.is_file():
            # try artifacts path
            if not list(goal_ev.glob("verification-oracle.json")):
                errors.append(
                    {
                        "failure_code": "uvo_skipped_illegally",
                        "summary": "implement gate passed but verification-oracle.json missing",
                    }
                )

        uvo_doc = load_json(uvo) if uvo.is_file() else {}
        overall = str(uvo_doc.get("overall", "")).lower() if uvo_doc else ""
        if overall and overall != "pass":
            errors.append(
                {
                    "failure_code": "uvo_not_pass",
                    "summary": f"verification-oracle overall={uvo_doc.get('overall')} at complete",
                }
            )

        cc = goal_ev / "contract-conformance.json"
        if cc.is_file() and not load_json(cc).get("passed"):
            errors.append(
                {
                    "failure_code": "contract_conformance_open",
                    "summary": "contract-conformance (IQ-10) not passed at complete",
                    "leakage": {"declared_defect_classes_silent_pass": ["IQ-10"]},
                }
            )

        task_path = Path(args.task_dir)
        handoff = task_path / "handoff"
        matrix_w2 = matrix_satisfaction_errors(handoff)

        manifest_path = handoff / "argus-scenario-manifest.json"
        if manifest_path.is_file():
            manifest = load_json(manifest_path)
            silent_l10: list[str] = []
            for row in manifest.get("scenarios") or []:
                if l10_row_blocks_complete(row):
                    silent_l10.append(str(row.get("id") or "unknown"))
            if silent_l10:
                errors.append(
                    {
                        "failure_code": "declared_defect_silent_pass",
                        "summary": f"L10 manifest rows without pass/waive/deferred: {', '.join(silent_l10)}",
                        "leakage": {"declared_defect_classes_silent_pass": silent_l10},
                    }
                )

        ux_scan = goal_ev / "ux-scan.json"
        if ux_scan.is_file():
            ux = load_json(ux_scan)
            unresolved = [
                f.get("id", "UX")
                for f in ux.get("findings") or []
                if (f.get("severity") or "").lower() in ("block", "blocker")
                and (f.get("w1_status") or "open").lower() not in ("pass", "waive", "deferred", "waived")
            ]
            if unresolved:
                errors.append(
                    {
                        "failure_code": "declared_defect_silent_pass",
                        "summary": f"ux-scan blocker findings without disposition: {', '.join(unresolved)}",
                        "leakage": {"declared_defect_classes_silent_pass": unresolved},
                    }
                )

    ok = not errors
    leakage_silent: list[str] = []
    matrix_rows_unsatisfied: list[str] = []
    for e in errors:
        if e.get("failure_code") == "declared_defect_silent_pass":
            leakage_silent.extend((e.get("leakage") or {}).get("declared_defect_classes_silent_pass") or [])
    for e in matrix_w2 if args.mode == "complete" else []:
        matrix_rows_unsatisfied.extend((e.get("leakage") or {}).get("w2_matrix_row_unsatisfied") or [])
    leakage: dict = {"declared_defect_classes_silent_pass": leakage_silent}
    if matrix_rows_unsatisfied:
        leakage["matrix_rows_unsatisfied"] = matrix_rows_unsatisfied
    out = {
        "ok": ok,
        "plane": "quality",
        "errors": errors,
        "silent_pass_forbidden": True,
        "leakage": leakage,
        "w2_matrix_notes": matrix_w2 if matrix_w2 else [],
    }
    if args.format == "text":
        print(f"quality_plane_check ok={ok}")
        for e in errors:
            print(f"  FAIL {e['failure_code']}: {e['summary']}")
    else:
        print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0 if ok else 2


if __name__ == "__main__":
    raise SystemExit(main())
