#!/usr/bin/env python3
"""data_plane_check — SSOT / hash policy invariants."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--task-dir", required=True)
    ap.add_argument("--project-root", required=True)
    ap.add_argument("--state-file", default="")
    ap.add_argument("--format", choices=("json", "text"), default="json")
    args = ap.parse_args()

    errors: list[dict] = []
    warnings: list[str] = []

    # project_id
    if args.state_file:
        vs = SCRIPT_DIR / "validate-state-path.sh"
        if vs.is_file():
            r = subprocess.run(
                [
                    "bash",
                    str(vs),
                    "--state-file",
                    args.state_file,
                    "--project-root",
                    args.project_root,
                    "--format",
                    "json",
                ],
                capture_output=True,
                text=True,
            )
            if r.returncode != 0:
                errors.append({"failure_code": "project_id_mismatch", "summary": (r.stderr or r.stdout)[:300]})

    # HashPolicy: refresh demotes execution-only cascade plan
    refresh = (SCRIPT_DIR / "refresh-handoffs-after-index.sh").read_text(encoding="utf-8")
    if "demote to implement" not in refresh and "REJECT cascade=plan" not in refresh:
        errors.append(
            {
                "failure_code": "execution_cascade_plan_rejected",
                "summary": "refresh-handoffs missing execution-only cascade guard",
            }
        )

    # resolve branch scope
    rap = (SCRIPT_DIR / "resolve-artifact-paths.py").read_text(encoding="utf-8")
    if "state_branch_matches" not in rap:
        errors.append({"failure_code": "state_ambiguous", "summary": "find_state_file not branch-scoped"})

    # handoff / index projection: progress SSOT is handoff+state; index current_stage is projection
    task = Path(args.task_dir)
    index = task / "index.md"
    handoff_dir = task / "handoff"
    if args.state_file and Path(args.state_file).is_file() and index.is_file():
        try:
            st = json.loads(Path(args.state_file).read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            st = {}
        stages = st.get("guazi_flow_stages") or {}
        # If plan handoff exists with passed_at, state should record plan progress (when tracked)
        plan_ho = handoff_dir / "plan.json"
        if plan_ho.is_file():
            try:
                plan = json.loads(plan_ho.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, OSError):
                plan = {}
            gate = plan.get("gate") or {}
            if gate.get("passed_at") and stages and not (stages.get("plan") or {}).get("gate", {}).get("passed_at"):
                # soft: warn when state tracks stages but plan gate not mirrored
                warnings.append("plan handoff gate.passed_at not mirrored in state.guazi_flow_stages")
        # HashPolicy module present for contract compare
        ich = SCRIPT_DIR / "index_contract_hash.py"
        if not ich.is_file():
            errors.append({"failure_code": "contract_stale", "summary": "index_contract_hash.py missing"})
        else:
            ich_txt = ich.read_text(encoding="utf-8")
            if "current_stage" not in ich_txt or "contract" not in ich_txt.lower():
                errors.append(
                    {
                        "failure_code": "contract_stale",
                        "summary": "index_contract_hash missing current_stage strip / contract compare",
                    }
                )

    ok = not errors
    out = {"ok": ok, "plane": "data", "errors": errors, "warnings": warnings}
    if args.format == "text":
        print(f"data_plane_check ok={ok}")
        for e in errors:
            print(e)
    else:
        print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0 if ok else 2


if __name__ == "__main__":
    raise SystemExit(main())
