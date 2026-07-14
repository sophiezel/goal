#!/usr/bin/env python3
"""four_planes_doctor — Verify control/data/quality/efficiency plane assets exist and wire correctly."""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REF_DIR = SCRIPT_DIR.parent / "references"


def check(name: str, ok: bool, detail: str = "") -> dict:
    return {"check": name, "status": "ok" if ok else "fail", "detail": detail, "plane": name.split(".", 1)[0] if "." in name else "meta"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project-root", default="")
    ap.add_argument("--task-dir", default="")
    ap.add_argument("--state-file", default="")
    ap.add_argument("--format", choices=("json", "text"), default="json")
    args = ap.parse_args()

    checks: list[dict] = []
    kernel = SCRIPT_DIR / "goal-pipeline-kernel.sh"
    checks.append(check("control.kernel_cli", kernel.is_file(), str(kernel)))
    checks.append(check("control.driver", (SCRIPT_DIR / "goal-stage-driver.sh").is_file()))
    checks.append(check("control.gate", (SCRIPT_DIR / "gate-guazi-flow-stage.sh").is_file()))
    checks.append(check("control.assert_merged", (SCRIPT_DIR / "assert_plan_before_code.py").is_file()))

    checks.append(check("data.validate_state", (SCRIPT_DIR / "validate-state-path.sh").is_file()))
    checks.append(check("data.resolve_paths", (SCRIPT_DIR / "resolve-artifact-paths.py").is_file()))
    checks.append(check("data.hash_policy", (SCRIPT_DIR / "index_contract_hash.py").is_file()))
    checks.append(check("data.refresh_cascade", (SCRIPT_DIR / "refresh-handoffs-after-index.sh").is_file()))
    rap = (SCRIPT_DIR / "resolve-artifact-paths.py").read_text(encoding="utf-8") if (SCRIPT_DIR / "resolve-artifact-paths.py").is_file() else ""
    checks.append(check("data.branch_scoped_discover", "state_branch_matches" in rap))

    codes = REF_DIR / "failure-codes.json"
    checklist = REF_DIR / "four-planes-checklist.json"
    checks.append(check("quality.failure_codes_dict", codes.is_file(), str(codes)))
    checks.append(check("quality.planes_checklist", checklist.is_file()))
    checks.append(check("quality.uvo", (SCRIPT_DIR / "verification-oracle.sh").is_file() or (SCRIPT_DIR / "verification_oracle_core.py").is_file()))
    checks.append(check("quality.am_ratchet", (SCRIPT_DIR / "acceptance-matrix-ratchet.py").is_file()))
    checks.append(check("quality.packet_preflight", (SCRIPT_DIR / "review_packet_preflight.py").is_file()))
    checks.append(check("quality.channel_policy", (SCRIPT_DIR / "review-channel-guard.py").is_file()))
    checks.append(check("quality.plane_check", (SCRIPT_DIR / "quality_plane_check.py").is_file()))

    gate_txt = (SCRIPT_DIR / "gate-guazi-flow-stage.sh").read_text(encoding="utf-8") if (SCRIPT_DIR / "gate-guazi-flow-stage.sh").is_file() else ""
    checks.append(check("efficiency.qg_state_file", "QG_ARGS+=(--state-file" in gate_txt or "--state-file \"$STATE_FILE\"" in gate_txt))
    checks.append(check("efficiency.pipeline_timing", (SCRIPT_DIR / "record-pipeline-timing.py").is_file()))
    checks.append(check("efficiency.postmortem", (SCRIPT_DIR / "pipeline-postmortem.py").is_file()))
    driver = (SCRIPT_DIR / "goal-stage-driver.sh").read_text(encoding="utf-8") if (SCRIPT_DIR / "goal-stage-driver.sh").is_file() else ""
    checks.append(check("efficiency.no_build_beta_in_wo", "build:beta" not in driver or "DO NOT run yarn build:beta" in driver))

    arch_candidates = [
        Path(__file__).resolve().parents[2] / "docs" / "architecture" / "goal-runtime.md",
        Path(os.environ.get("GOAL_PIPELINE_REPO", "")).expanduser() / "docs" / "architecture" / "goal-runtime.md",
        Path(os.environ.get("DEPLOY_SOURCE", "")).expanduser() / "docs" / "architecture" / "goal-runtime.md",
        Path.home() / ".goal-pipeline-repo" / "docs" / "architecture" / "goal-runtime.md",
        SCRIPT_DIR.parent.parent / "docs" / "architecture" / "goal-runtime.md",
    ]
    arch = next((p for p in arch_candidates if p and str(p) != "." and p.is_file()), arch_candidates[0])
    checks.append(check("meta.goal_runtime_doc", arch.is_file(), str(arch)))
    checks.append(
        check(
            "meta.host_guard",
            True,
            f"GOAL_HOST_GUARD={os.environ.get('GOAL_HOST_GUARD', 'off')} (Core does not claim physical Write deny)",
        )
    )

    if args.state_file and args.project_root and (SCRIPT_DIR / "validate-state-path.sh").is_file():
        import subprocess

        r = subprocess.run(
            [
                "bash",
                str(SCRIPT_DIR / "validate-state-path.sh"),
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
        checks.append(check("data.canonical_state", r.returncode == 0, (r.stderr or r.stdout)[:200]))

    failed = [c for c in checks if c["status"] != "ok"]
    by_plane: dict[str, list] = {}
    for c in checks:
        p = c["check"].split(".", 1)[0]
        by_plane.setdefault(p, []).append(c)

    out = {
        "ok": not failed,
        "schema_version": 1,
        "host_guard": os.environ.get("GOAL_HOST_GUARD", "off"),
        "planes_summary": {
            p: {"ok": all(x["status"] == "ok" for x in items), "checks": len(items)}
            for p, items in by_plane.items()
        },
        "failed": failed,
        "checks": checks,
    }
    if args.format == "text":
        print(f"four_planes_doctor ok={out['ok']} host_guard={out['host_guard']}")
        for c in checks:
            print(f"  [{c['status']}] {c['check']} {c.get('detail','')}")
    else:
        print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0 if out["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
