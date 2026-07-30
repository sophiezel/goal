#!/usr/bin/env python3
"""validate-pipeline-chain — handoff chain + provenance checks."""
import argparse
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--task-dir", required=True)
    p.add_argument("--state-file", default="")
    p.add_argument("--exclude-stage", default="", help="skip handoff checks for this stage (e.g. quality during post)")
    return p.parse_args()


def fm(path, key):
    if not os.path.isfile(path):
        return ""
    t = open(path, encoding="utf-8").read()
    m = re.match(r"^---\s*\n(.*?)\n---", t, re.DOTALL)
    if not m:
        return ""
    for line in m.group(1).splitlines():
        stripped = line.strip()
        if stripped.startswith(key + ":"):
            return stripped.split(":", 1)[1].strip().strip('"').strip("'")
        if line.startswith("  ") and stripped.startswith(key + ":"):
            return stripped.split(":", 1)[1].strip().strip('"').strip("'")
    return ""


def load_state(path):
    if path and os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    return {}


def index_implies_implement_done(task_dir):
    index_path = os.path.join(task_dir, "index.md")
    if not os.path.isfile(index_path):
        return False
    text = open(index_path, encoding="utf-8").read()
    lower = text.lower()
    patterns = [
        r"implement\s*完成",
        r"implement.*\bpass\b",
        r"guazi-flow-implement.*\bpass\b",
        r"yarn test.*pass",
        r"pytest.*pass",
        r"\d+\s*passed",
    ]
    for pattern in patterns:
        if re.search(pattern, lower, re.I):
            return True
    stage = fm(index_path, "current_stage")
    if stage in ("review", "complete", "quality", "runtime_smoke", "smoke"):
        return True
    return False


def check_state_handoff_consistency(state, handoff_dir, errors):
    stages = state.get("guazi_flow_stages") or {}
    for stage in ("plan", "implement", "review", "complete"):
        gate = (stages.get(stage) or {}).get("gate") or {}
        if gate.get("passed_at") and not os.path.isfile(os.path.join(handoff_dir, f"{stage}.json")):
            errors.append(
                f"{stage}: state.json gate.passed_at set but handoff/{stage}.json missing"
            )


def resolve_paths(task_dir, state_file=""):
    script_dir = os.path.dirname(os.path.abspath(__file__))
    resolver = os.path.join(script_dir, "resolve-artifact-paths.py")
    import subprocess
    args = [sys.executable, resolver, "--task-dir", task_dir, "--format", "json"]
    if state_file:
        args.extend(["--state-file", state_file])
    r = subprocess.run(args, capture_output=True, text=True, check=True)
    return json.loads(r.stdout)


def main():
    args = parse_args()
    paths = resolve_paths(args.task_dir, args.state_file)
    task_dir = paths["repo_task_dir"]
    handoff_dir = paths["handoff_dir"]
    repo_evidence_dir = paths["repo_evidence_dir"]
    goal_evidence_dir = paths["goal_evidence_dir"]
    errors, warnings = [], []
    state = load_state(args.state_file)
    recommended_fix_command = ""

    check_state_handoff_consistency(state, handoff_dir, errors)

    plan_handoff = os.path.join(handoff_dir, "plan.json")
    impl = os.path.join(handoff_dir, "implement.json")
    index_path = os.path.join(task_dir, "index.md")
    script_dir = os.path.dirname(os.path.abspath(__file__))
    hash_py = os.path.join(script_dir, "index_contract_hash.py")
    refresh = os.path.join(script_dir, "refresh-handoffs-after-index.sh")

    # Plan contract freshness
    if os.path.isfile(plan_handoff) and os.path.isfile(index_path) and os.path.isfile(hash_py):
        try:
            import importlib.util

            spec = importlib.util.spec_from_file_location("index_contract_hash", hash_py)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            plan = json.load(open(plan_handoff, encoding="utf-8"))
            fresh = mod.compare_plan_freshness(index_path, plan)
            if fresh.get("contract_changed"):
                errors.append(
                    "plan: index_contract_hash mismatch (contract sections changed) — run refresh-handoffs-after-index.sh --cascade plan"
                )
                recommended_fix_command = (
                    f"{refresh} --task-dir {task_dir} --state-file {args.state_file} --cascade plan"
                )
            elif fresh.get("execution_changed"):
                warnings.append(
                    "plan: execution record changed since plan handoff — run refresh-handoffs-after-index.sh --cascade implement"
                )
                if not recommended_fix_command:
                    recommended_fix_command = (
                        f"{refresh} --task-dir {task_dir} --state-file {args.state_file} --cascade implement"
                    )
            elif not plan.get("index_contract_hash") and plan.get("index_schema_hash"):
                warnings.append(
                    "plan: legacy index_schema_hash only — migrate via gate --post plan or refresh-handoffs"
                )
            cp = os.path.join(script_dir, "contract_parser.py")
            if os.path.isfile(cp) and os.path.isfile(index_path):
                import importlib.util

                spec = importlib.util.spec_from_file_location("contract_parser", cp)
                cmod = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(cmod)
                stored_api = (plan.get("api_mapping_table_hash") or "").strip()
                cur_api = cmod.api_mapping_table_hash(open(index_path, encoding="utf-8").read())
                if stored_api and cur_api and stored_api != cur_api:
                    errors.append(
                        "plan: api_mapping_table_hash mismatch — gate --post plan after API table edits"
                    )
                elif cur_api and not stored_api:
                    warnings.append(
                        "plan: api_mapping_table_hash missing in handoff — re-run gate --post plan"
                    )
        except Exception as e:
            warnings.append(f"plan: freshness check error: {e}")

    # implement candidate_diff_hash vs current git diff
    if os.path.isfile(impl):
        try:
            impl_doc = json.load(open(impl, encoding="utf-8"))
            stored_dh = impl_doc.get("candidate_diff_hash", "")
            git_root = None
            try:
                import subprocess

                git_root = subprocess.check_output(
                    ["git", "-C", task_dir, "rev-parse", "--show-toplevel"],
                    text=True,
                    stderr=subprocess.DEVNULL,
                ).strip()
            except Exception:
                git_root = None
            if stored_dh and git_root:
                import importlib.util

                uvo_core = os.path.join(script_dir, "verification_oracle_core.py")
                if os.path.isfile(uvo_core):
                    spec = importlib.util.spec_from_file_location("verification_oracle_core", uvo_core)
                    mod = importlib.util.module_from_spec(spec)
                    spec.loader.exec_module(mod)
                    ws = impl_doc.get("write_set") or []
                    ref = ""
                    if os.path.isfile(plan_handoff):
                        plan_doc = json.load(open(plan_handoff, encoding="utf-8"))
                        ref = plan_doc.get("reference_branch") or plan_doc.get("reference_impl_branch") or ""
                    cur_dh = mod.code_subject_hash(git_root, ws, ref)
                else:
                    import subprocess

                    diff = subprocess.check_output(
                        ["git", "-C", git_root, "-c", "core.quotepath=false", "diff", "HEAD"],
                        text=True,
                        stderr=subprocess.DEVNULL,
                    )
                    cur_dh = hashlib.sha256(diff.encode("utf-8")).hexdigest()[:16]
                stored_csh = impl_doc.get("code_subject_hash") or stored_dh
                if cur_dh != stored_csh:
                    warnings.append(
                        f"implement: code_subject_hash drifted ({stored_csh} → {cur_dh}) — refresh via gate --post implement"
                    )
                    if not recommended_fix_command:
                        recommended_fix_command = (
                            f"{refresh} --task-dir {task_dir} --state-file {args.state_file} --cascade implement"
                        )
        except Exception as e:
            warnings.append(f"implement: diff hash check error: {e}")

    if not os.path.isfile(plan_handoff):
        plan_gate = ((state.get("guazi_flow_stages") or {}).get("plan") or {}).get("gate") or {}
        if plan_gate.get("passed_at"):
            errors.append("plan: state gate passed but handoff/plan.json missing")

    if not os.path.isfile(impl):
        if index_implies_implement_done(task_dir):
            errors.append(
                "implement: execution record implies done but handoff/implement.json missing "
                "— run gate --post implement"
            )
        current = state.get("current_stage") or fm(os.path.join(task_dir, "index.md"), "current_stage")
        if current in ("review", "quality", "runtime_smoke", "smoke", "complete"):
            errors.append("implement: handoff/implement.json missing for current_stage=" + str(current))

    manifest_path = os.path.join(handoff_dir, "integration-manifest.json")
    if os.path.isfile(manifest_path) and os.path.isfile(impl):
        barrier_paths = [
            os.path.join(goal_evidence_dir, "integration-barrier.json"),
            os.path.join(repo_evidence_dir, "integration-barrier.json"),
            os.path.join(task_dir, "evidence", "integration-barrier.json"),
        ]
        if not any(os.path.isfile(p) for p in barrier_paths):
            warnings.append(
                "implement: integration-manifest.json present but integration-barrier.json missing "
                "— re-run gate --post implement after cross_app is satisfied"
            )

    sm_path = os.path.join(goal_evidence_dir, "runtime-smoke.md")
    quality_handoff = os.path.join(handoff_dir, "quality.json")
    exclude = (args.exclude_stage or "").strip()
    if os.path.isfile(impl):
        if os.path.isfile(sm_path):
            if (
                exclude != "quality"
                and not os.path.isfile(quality_handoff)
                and not os.path.isfile(os.path.join(handoff_dir, "smoke.json"))
            ):
                res = fm(sm_path, "result")
                if res != "skipped":
                    errors.append("quality: handoff/quality.json gate not passed")
            if fm(sm_path, "result") == "not_pass" and not fm(sm_path, "classification"):
                warnings.append("smoke: not_pass without classification")

    review_md = os.path.join(repo_evidence_dir, "review.md")
    if os.path.isfile(review_md):
        if not os.path.isfile(os.path.join(goal_evidence_dir, "review-run.json")):
            errors.append("review: review-run.json missing (anti-forgery)")
        if not os.path.isfile(os.path.join(goal_evidence_dir, "review-unified.json")):
            errors.append("review: review-unified.json missing")
        rp = os.path.join(handoff_dir, "review-packet.json")
        rr = os.path.join(goal_evidence_dir, "review-run.json")
        if os.path.isfile(rp) and os.path.isfile(rr):
            run = json.load(open(rr, encoding="utf-8"))
            ph = hashlib.sha256(open(rp, "rb").read()).hexdigest()[:16]
            if run.get("packet_hash") and run["packet_hash"] != ph:
                errors.append("review: review-run packet_hash mismatch")
        fix_in = os.path.join(goal_evidence_dir, "review-fix-input.json")
        if not os.path.isfile(fix_in):
            errors.append("review: review-fix-input.json missing (execution contract)")
        else:
            fix = json.load(open(fix_in, encoding="utf-8"))
            action = fix.get("action", "")
            merged = fix.get("merged_result", "")
            if merged == "pass" and action != "proceed_complete":
                errors.append("review: pass requires action=proceed_complete in review-fix-input.json")
            if merged == "not_pass" and action == "proceed_complete":
                errors.append("review: not_pass cannot have action=proceed_complete")

    port_py = os.path.join(script_dir, "validate-stage-port.py")
    if os.path.isfile(port_py) and os.path.isfile(os.path.join(handoff_dir, "complete.json")):
        import subprocess as sp

        port_args = [sys.executable, port_py, "--task-dir", args.task_dir, "--only-present", "--require-delivery"]
        if args.state_file:
            port_args.extend(["--state-file", args.state_file])
        pr = sp.run(port_args, capture_output=True, text=True)
        if pr.returncode != 0:
            try:
                port_doc = json.loads(pr.stdout or "{}")
                for pe in port_doc.get("errors", []):
                    errors.append(f"port: {pe}")
            except json.JSONDecodeError:
                errors.append("port: validate-stage-port failed")

    out = {
        "ok": len(errors) == 0,
        "errors": errors,
        "warnings": warnings,
        "recommended_fix_command": recommended_fix_command,
        "checked_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    print(json.dumps(out, ensure_ascii=False, indent=2))
    sys.exit(0 if out["ok"] else 1)


if __name__ == "__main__":
    main()
