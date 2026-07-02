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
        r"\|\s*implement\s*\|",
        r"yarn test.*pass",
        r"pytest.*pass",
        r"\d+\s*passed",
    ]
    for pattern in patterns:
        if re.search(pattern, lower, re.I):
            return True
    stage = fm(index_path, "current_stage")
    if stage in ("review", "complete", "runtime_smoke", "smoke"):
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


def main():
    args = parse_args()
    task_dir = os.path.abspath(args.task_dir)
    handoff_dir = os.path.join(task_dir, "handoff")
    evidence_dir = os.path.join(task_dir, "evidence")
    errors, warnings = [], []
    state = load_state(args.state_file)

    check_state_handoff_consistency(state, handoff_dir, errors)

    plan_handoff = os.path.join(handoff_dir, "plan.json")
    impl = os.path.join(handoff_dir, "implement.json")

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
        if current in ("review", "runtime_smoke", "smoke", "complete"):
            errors.append("implement: handoff/implement.json missing for current_stage=" + str(current))

    sm_path = os.path.join(evidence_dir, "runtime-smoke.md")
    if os.path.isfile(impl):
        if os.path.isfile(sm_path):
            if not os.path.isfile(os.path.join(handoff_dir, "smoke.json")):
                res = fm(sm_path, "result")
                if res != "skipped":
                    errors.append("smoke: handoff/smoke.json gate not passed")
            if fm(sm_path, "result") == "not_pass" and not fm(sm_path, "classification"):
                warnings.append("smoke: not_pass without classification")

    review_md = os.path.join(evidence_dir, "review.md")
    if os.path.isfile(review_md):
        if not os.path.isfile(os.path.join(evidence_dir, "review-run.json")):
            errors.append("review: review-run.json missing (anti-forgery)")
        if not os.path.isfile(os.path.join(evidence_dir, "review-goal.json")):
            errors.append("review: review-goal.json missing")
        rp = os.path.join(handoff_dir, "review-packet.json")
        rr = os.path.join(evidence_dir, "review-run.json")
        if os.path.isfile(rp) and os.path.isfile(rr):
            run = json.load(open(rr, encoding="utf-8"))
            ph = hashlib.sha256(open(rp, "rb").read()).hexdigest()[:16]
            if run.get("packet_hash") and run["packet_hash"] != ph:
                errors.append("review: review-run packet_hash mismatch")
        fix_in = os.path.join(evidence_dir, "review-fix-input.json")
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

    for stage in ("plan", "implement", "review"):
        hf = os.path.join(handoff_dir, stage + ".json")
        if stage == "review" and os.path.isfile(review_md) and not os.path.isfile(hf):
            errors.append("review: handoff/review.json missing")

    out = {
        "ok": len(errors) == 0,
        "errors": errors,
        "warnings": warnings,
        "checked_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    print(json.dumps(out, ensure_ascii=False, indent=2))
    sys.exit(0 if out["ok"] else 1)


if __name__ == "__main__":
    main()
