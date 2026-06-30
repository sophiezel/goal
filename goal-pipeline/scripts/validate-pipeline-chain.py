#!/usr/bin/env python3
"""validate-pipeline-chain — handoff chain + provenance checks."""
import argparse, hashlib, json, os, re, sys
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
        if line.strip().startswith(key + ":"):
            return line.split(":", 1)[1].strip().strip('"').strip("'")
    return ""

def handoff_gate(task_dir, stage):
    p = os.path.join(task_dir, "handoff", stage + ".json")
    if not os.path.isfile(p):
        return None
    return json.load(open(p)).get("gate", {}).get("passed_at")

def main():
    args = parse_args()
    task_dir = os.path.abspath(args.task_dir)
    handoff_dir = os.path.join(task_dir, "handoff")
    evidence_dir = os.path.join(task_dir, "evidence")
    errors, warnings = [], []

    impl = os.path.join(handoff_dir, "implement.json")
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
            run = json.load(open(rr))
            ph = hashlib.sha256(open(rp, "rb").read()).hexdigest()[:16]
            if run.get("packet_hash") and run["packet_hash"] != ph:
                errors.append("review: review-run packet_hash mismatch")
        fix_in = os.path.join(evidence_dir, "review-fix-input.json")
        if not os.path.isfile(fix_in):
            errors.append("review: review-fix-input.json missing (execution contract)")
        else:
            fix = json.load(open(fix_in))
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
