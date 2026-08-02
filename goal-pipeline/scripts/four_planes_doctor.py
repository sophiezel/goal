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


def check_warn(name: str, ok: bool, detail: str = "") -> dict:
    """Non-blocking advisory; never contributes to doctor failure."""
    status = "ok" if ok else "warn"
    return {"check": name, "status": status, "detail": detail, "plane": name.split(".", 1)[0] if "." in name else "meta"}


def _handoff_tier_live_checks(task_dir: str, project_root: str, state_file: str) -> list[dict]:
    """Live split-layout: Tier-R resolution must match resolver SSOT (#17)."""
    out: list[dict] = []
    if str(SCRIPT_DIR) not in sys.path:
        sys.path.insert(0, str(SCRIPT_DIR))
    from handoff_path_resolver import (  # noqa: WPS433
        resolve_artifact_paths,
        resolve_handoff_dir,
        resolve_plan_json_path,
    )

    td = os.path.abspath(task_dir)
    pr = project_root or td
    sf = state_file
    paths = resolve_artifact_paths(td, state_file=sf, project_root=pr)
    rap_ho = (paths.get("handoff_dir") or "").strip()
    resolver_ho = resolve_handoff_dir(td, state_file=sf, project_root=pr)
    rap_norm = str(Path(rap_ho).resolve()) if rap_ho else ""
    res_norm = str(Path(resolver_ho).resolve()) if resolver_ho else ""
    agree = rap_norm == res_norm if rap_norm and res_norm else bool(rap_norm or res_norm)
    out.append(
        check(
            "data.handoff_tier_rap_resolver",
            agree,
            f"rap={rap_norm or '∅'} resolver={res_norm or '∅'}",
        )
    )

    plan_path = resolve_plan_json_path(td, state_file=sf, project_root=pr)
    plan_ok = os.path.isfile(plan_path)
    out.append(
        check(
            "data.handoff_tier_plan_json",
            plan_ok,
            plan_path if plan_ok else f"missing {plan_path}",
        )
    )

    mode = ""
    layout = paths.get("artifact_layout") if isinstance(paths.get("artifact_layout"), dict) else {}
    if layout:
        mode = (layout.get("mode") or "").strip()
    if not mode and sf and os.path.isfile(sf):
        try:
            st = json.loads(Path(sf).read_text(encoding="utf-8"))
            al = st.get("artifact_layout") if isinstance(st.get("artifact_layout"), dict) else {}
            mode = (al.get("mode") or "").strip()
        except (json.JSONDecodeError, OSError):
            pass

    repo_plan = os.path.join(td, "handoff", "plan.json")
    tier_r_plan = plan_path if plan_ok else ""
    drift = False
    drift_detail = ""
    if mode == "split":
        if plan_ok and os.path.isfile(repo_plan):
            if os.path.samefile(repo_plan, tier_r_plan):
                drift_detail = "split: repo handoff/plan.json duplicates Tier-R (ok if synced)"
            else:
                drift = True
                drift_detail = f"split: repo {repo_plan} != Tier-R {tier_r_plan}"
        elif plan_ok and res_norm and res_norm == str(Path(td, "handoff").resolve()):
            drift = True
            drift_detail = "split: resolver points at repo handoff without Tier-R runtime"
    out.append(
        check(
            "data.handoff_ssot_drift",
            not drift,
            drift_detail or f"mode={mode or 'unknown'}",
        )
    )
    return out


def _shell_handoff_ssot_checks() -> list[dict]:
    """Static: implement-post shell gates must not hardcode task_dir/handoff only."""
    out: list[dict] = []
    qg = SCRIPT_DIR / "quality-gate.sh"
    qg_txt = qg.read_text(encoding="utf-8") if qg.is_file() else ""
    qg_ok = (
        "resolve-artifact-paths.py" in qg_txt
        and (
            "${HANDOFF_DIR" in qg_txt
            or 'HANDOFF_DIR:-' in qg_txt
            or "HANDOFF_DIR}/plan.json" in qg_txt
        )
    )
    out.append(check("data.qg_shell_handoff_ssot", qg_ok, "quality-gate.sh plan.json path"))

    verify = SCRIPT_DIR / "verify.sh"
    v_txt = verify.read_text(encoding="utf-8") if verify.is_file() else ""
    v_ok = "resolve-artifact-paths.py" in v_txt and "HANDOFF_DIR" in v_txt
    out.append(check("data.verify_shell_handoff_ssot", v_ok, "verify.sh handoff_status_json"))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project-root", default="")
    ap.add_argument("--task-dir", default="")
    ap.add_argument("--state-file", default="")
    ap.add_argument("--repo-root", default="",
                   help="Repo source root for install-drift SHA comparison (auto-detected if omitted)")
    ap.add_argument("--format", choices=("json", "text"), default="json")
    args = ap.parse_args()

    checks: list[dict] = []
    kernel = SCRIPT_DIR / "goal-pipeline-kernel.sh"
    checks.append(check("control.kernel_cli", kernel.is_file(), str(kernel)))
    kernel_pkg = SCRIPT_DIR.parent / "kernel" / "__init__.py"
    kernel_ver = ""
    if kernel_pkg.is_file():
        txt = kernel_pkg.read_text(encoding="utf-8")
        for line in txt.splitlines():
            if line.strip().startswith("__version__"):
                kernel_ver = line.split("=", 1)[-1].strip().strip('"').strip("'")
                break
    checks.append(check("control.kernel_package", kernel_pkg.is_file(), kernel_ver or str(kernel_pkg)))
    gf_driver = SCRIPT_DIR / "gf-stage-driver.sh"
    goal_driver = SCRIPT_DIR / "goal-stage-driver.sh"
    gf_gate = SCRIPT_DIR / "gate-gf-stage.sh"
    for label, path in (
        ("control.gf_stage_driver", gf_driver),
        ("control.gate_gf_stage", gf_gate),
    ):
        checks.append(check(label, path.is_file(), str(path)))
    if kernel_ver and gf_driver.is_file() and goal_driver.is_file():
        gfd = gf_driver.read_text(encoding="utf-8")
        gsd = goal_driver.read_text(encoding="utf-8")
        uses_kernel = "kernel/" in gfd or "kernel." in gfd
        checks.append(
            check(
                "control.gf_driver_kernel_wire",
                uses_kernel or "GF_USE_NATIVE_DRIVER" in gfd,
                f"kernel_version={kernel_ver}",
            )
        )
        checks.append(
            check(
                "control.kernel_version_goal_driver",
                "goal-pipeline-kernel" in gsd or "kernel" in gsd,
                kernel_ver,
            )
        )
    checks.append(check("control.driver", goal_driver.is_file()))
    checks.append(check("control.gate", (SCRIPT_DIR / "gate-guazi-flow-stage.sh").is_file()))
    checks.append(check("control.assert_merged", (SCRIPT_DIR / "assert_plan_before_code.py").is_file()))

    checks.append(check("data.validate_state", (SCRIPT_DIR / "validate-state-path.sh").is_file()))
    checks.append(check("data.resolve_paths", (SCRIPT_DIR / "resolve-artifact-paths.py").is_file()))
    checks.append(check("data.hash_policy", (SCRIPT_DIR / "index_contract_hash.py").is_file()))
    checks.append(check("data.refresh_cascade", (SCRIPT_DIR / "refresh-handoffs-after-index.sh").is_file()))
    rap = (SCRIPT_DIR / "resolve-artifact-paths.py").read_text(encoding="utf-8") if (SCRIPT_DIR / "resolve-artifact-paths.py").is_file() else ""
    checks.append(check("data.handoff_path_resolver", (SCRIPT_DIR / "handoff_path_resolver.py").is_file()))
    am_txt = (SCRIPT_DIR / "acceptance-matrix-ratchet.py").read_text(encoding="utf-8") if (SCRIPT_DIR / "acceptance-matrix-ratchet.py").is_file() else ""
    checks.append(
        check(
            "data.am_ratchet_handoff_ssot",
            "handoff_path_resolver" in am_txt or "resolve_plan_json_path" in am_txt,
            "acceptance-matrix-ratchet.py",
        )
    )
    qpc = (SCRIPT_DIR / "quality_plane_check.py").read_text(encoding="utf-8") if (SCRIPT_DIR / "quality_plane_check.py").is_file() else ""
    checks.append(
        check(
            "data.quality_plane_handoff_ssot",
            "handoff_dir" in qpc and "matrix_satisfaction_plane_notes" in qpc,
            "quality_plane_check.py",
        )
    )
    uvo_txt = (SCRIPT_DIR / "verification_oracle_core.py").read_text(encoding="utf-8") if (SCRIPT_DIR / "verification_oracle_core.py").is_file() else ""
    checks.append(
        check(
            "data.uvo_handoff_ssot",
            "handoff_path_resolver" in uvo_txt,
            "verification_oracle_core.resolve_handoff_dir",
        )
    )
    checks.extend(_shell_handoff_ssot_checks())

    codes = REF_DIR / "failure-codes.json"
    checklist = REF_DIR / "four-planes-checklist.json"
    checks.append(check("quality.failure_codes_dict", codes.is_file(), str(codes)))
    checks.append(check("quality.planes_checklist", checklist.is_file()))
    checks.append(check("quality.uvo", (SCRIPT_DIR / "verification-oracle.sh").is_file() or (SCRIPT_DIR / "verification_oracle_core.py").is_file()))
    checks.append(check("quality.am_ratchet", (SCRIPT_DIR / "acceptance-matrix-ratchet.py").is_file()))
    checks.append(check("quality.packet_preflight", (SCRIPT_DIR / "review_packet_preflight.py").is_file()))
    checks.append(check("quality.channel_policy", (SCRIPT_DIR / "review-channel-guard.py").is_file()))
    checks.append(check("quality.plane_check", (SCRIPT_DIR / "quality_plane_check.py").is_file()))
    checks.append(check("quality.contract_parser", (SCRIPT_DIR / "contract_parser.py").is_file()))
    checks.append(check("quality.contract_conformance", (SCRIPT_DIR / "contract-conformance-check.py").is_file()))
    impl_gate = SCRIPT_DIR / "gate-lib" / "implement.sh"
    impl_txt = impl_gate.read_text(encoding="utf-8") if impl_gate.is_file() else ""
    checks.append(
        check(
            "quality.iq10_wired",
            "contract-conformance-check.py" in impl_txt,
            "implement post",
        )
    )

    gate_script = SCRIPT_DIR / "gate-goal-stage.sh"
    if not gate_script.is_file():
        gate_script = SCRIPT_DIR / "gate-guazi-flow-stage.sh"
    gate_txt = gate_script.read_text(encoding="utf-8") if gate_script.is_file() else ""
    quality_lib = SCRIPT_DIR / "gate-lib" / "quality.sh"
    qg_txt = quality_lib.read_text(encoding="utf-8") if quality_lib.is_file() else ""
    qg_state_ok = (
        "QG_ARGS+=(--state-file" in gate_txt
        or "--state-file \"$STATE_FILE\"" in gate_txt
        or "QG_ARGS+=(--state-file" in qg_txt
    )
    checks.append(check("efficiency.qg_state_file", qg_state_ok))
    checks.append(check("efficiency.pipeline_timing", (SCRIPT_DIR / "record-pipeline-timing.py").is_file()))
    delivery_mod = SCRIPT_DIR.parent / "kernel" / "metrics" / "delivery_report.py"
    checks.append(check("efficiency.delivery_report_kernel", delivery_mod.is_file(), str(delivery_mod)))
    checks.append(check("efficiency.postmortem", (SCRIPT_DIR / "pipeline-postmortem.py").is_file()))
    driver = (SCRIPT_DIR / "goal-stage-driver.sh").read_text(encoding="utf-8") if (SCRIPT_DIR / "goal-stage-driver.sh").is_file() else ""
    checks.append(check("efficiency.no_build_beta_in_wo", "build:beta" not in driver or "DO NOT run yarn build:beta" in driver))

    arch_candidates = [
        Path(__file__).resolve().parents[2] / "docs" / "architecture" / "goal-runtime.md",
        Path(os.environ.get("GOAL_PIPELINE_REPO", "")).expanduser() / "docs" / "architecture" / "goal-runtime.md",
        Path(os.environ.get("DEPLOY_SOURCE", "")).expanduser() / "docs" / "architecture" / "goal-runtime.md",
        Path.home() / ".goal-pipeline" / "repository" / "docs" / "architecture" / "goal-runtime.md",
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

    if str(SCRIPT_DIR) not in sys.path:
        sys.path.insert(0, str(SCRIPT_DIR))
    from argus_plan_post_policy import fe_argus_skill_discover  # noqa: WPS433

    fe_skill = fe_argus_skill_discover()
    if fe_skill.get("installed"):
        checks.append(
            check_warn(
                "meta.fe_argus_skill_recommended",
                True,
                fe_skill.get("skill_dir") or "installed",
            )
        )
    else:
        checks.append(
            check_warn(
                "meta.fe_argus_skill_recommended",
                False,
                f"optional skill missing — recommended: {fe_skill.get('install_one_liner')}",
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

    tier_env = os.environ.get("GOAL_RUN_FOUR_PLANES_DOCTOR", "").strip() in ("1", "true", "yes")
    tier_task = (args.task_dir or os.environ.get("GOAL_TASK_DIR") or "").strip()
    tier_state = (args.state_file or os.environ.get("GOAL_STATE_FILE") or "").strip()
    tier_project = (args.project_root or os.environ.get("GOAL_REPO_ROOT") or "").strip()
    if tier_task and tier_state and (tier_env or args.state_file):
        checks.extend(_handoff_tier_live_checks(tier_task, tier_project, tier_state))
    elif tier_env and not (tier_task and tier_state):
        checks.append(
            check(
                "data.handoff_tier_live",
                False,
                "GOAL_RUN_FOUR_PLANES_DOCTOR=1 requires --task-dir and --state-file",
            )
        )

    # install-drift (v3 W1d): compare GOAL_STATE_HOME/scripts SHAs vs repo source
    import hashlib
    checkout_root = SCRIPT_DIR.parent.parent
    checkout_ok = (
        checkout_root.is_dir()
        and (checkout_root / "goal-pipeline" / "scripts").resolve() == SCRIPT_DIR.resolve()
    )
    repo_root = Path(args.repo_root).expanduser() if args.repo_root else None
    if not repo_root:
        for cand in (
            Path(os.environ.get("GOAL_PIPELINE_REPO", "")).expanduser(),
            Path(os.environ.get("DEPLOY_SOURCE", "")).expanduser(),
            checkout_root if checkout_ok else Path("."),
            Path.home() / ".goal-pipeline" / "repository",
        ):
            if str(cand) != "." and cand.is_dir() and (cand / "goal-pipeline" / "scripts").is_dir():
                repo_root = cand
                break
    state_home = Path(os.environ.get("GOAL_STATE_HOME", "")).expanduser()
    if not state_home.is_dir():
        state_home = Path.home() / ".goal-pipeline" / "state"
    installed_dir = state_home / "scripts" if (state_home / "scripts").is_dir() else SCRIPT_DIR
    if repo_root and repo_root.is_dir():
        repo_scripts = repo_root / "goal-pipeline" / "scripts"
        drift_files = []
        for name in ("gate-guazi-flow-stage.sh", "goal-stage-driver.sh", "merge_review_core.py",
                     "plan-quality-gate.py", "resolve_plan_index_rules.py", "review_track.py",
                     "check_commit_before_review.py", "quality-gate.sh",
                     "acceptance-matrix-ratchet.py", "write-delivery-quality.sh",
                     "validate-stage-port.py", "gf-stage-driver.sh", "gate-gf-stage.sh",
                     "leak-rate-panel.py", "benchmark-ci.sh", "escape-to-eval.py",
                     "contract_parser.py", "contract-conformance-check.py",
                     "handoff_path_resolver.py", "resolve-artifact-paths.py"):
            installed = installed_dir / name
            source = repo_scripts / name
            if not installed.is_file() or not source.is_file():
                continue
            h_i = hashlib.sha256(installed.read_bytes()).hexdigest()[:16]
            h_s = hashlib.sha256(source.read_bytes()).hexdigest()[:16]
            if h_i != h_s:
                drift_files.append(f"{name}: installed={h_i} repo={h_s}")
        checks.append(check("meta.install_drift", len(drift_files) == 0,
                            ("no drift" if not drift_files else "; ".join(drift_files))))
    else:
        checks.append(check("meta.install_drift", True, "repo root not found — drift check skipped"))

    failed = [c for c in checks if c["status"] == "fail"]
    by_plane: dict[str, list] = {}
    for c in checks:
        p = c["check"].split(".", 1)[0]
        by_plane.setdefault(p, []).append(c)

    out = {
        "ok": not failed,
        "schema_version": 1,
        "host_guard": os.environ.get("GOAL_HOST_GUARD", "off"),
        "planes_summary": {
            p: {"ok": all(x["status"] in ("ok", "warn") for x in items), "checks": len(items)}
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
