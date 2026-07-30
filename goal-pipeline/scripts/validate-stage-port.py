#!/usr/bin/env python3
"""validate-stage-port — StagePort required fields per pipeline-io-port-spec.md."""
import argparse
import json
import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

STAGE_FILES = {
    "plan": "plan.json",
    "implement": "implement.json",
    "quality": ("quality.json", "smoke.json"),
    "review": "review.json",
    "complete": "complete.json",
}

REQUIRED = {
    "plan": ["stage", "schema_version", "write_set"],
    "implement": ["stage", "schema_version", "write_set"],
    "quality": ["stage", "schema_version"],
    "review": ["stage", "schema_version", "result"],
    "complete": ["stage", "schema_version"],
}

DELIVERY_REQUIRED = ["schema_version", "task_dir", "computed_at", "chain_complete", "gate_status"]


def resolve_paths(task_dir, state_file=""):
    resolver = os.path.join(SCRIPT_DIR, "resolve-artifact-paths.py")
    args = [sys.executable, resolver, "--task-dir", task_dir, "--format", "json"]
    if state_file:
        args.extend(["--state-file", state_file])
    r = subprocess.run(args, capture_output=True, text=True, check=True)
    return json.loads(r.stdout)


def load_handoff(handoff_dir, stage):
    spec = STAGE_FILES[stage]
    if isinstance(spec, tuple):
        for name in spec:
            path = os.path.join(handoff_dir, name)
            if os.path.isfile(path):
                return json.load(open(path, encoding="utf-8")), name
        return None, None
    path = os.path.join(handoff_dir, spec)
    if not os.path.isfile(path):
        return None, spec
    return json.load(open(path, encoding="utf-8")), spec


def check_stage(handoff_dir, stage, errors):
    doc, fname = load_handoff(handoff_dir, stage)
    if doc is None:
        errors.append(f"{stage}: handoff/{fname or STAGE_FILES[stage]} missing")
        return
    for key in REQUIRED.get(stage, []):
        if key not in doc or doc[key] in (None, ""):
            errors.append(f"{stage}: missing required field {key!r} in {fname}")
    if stage == "review" and doc.get("result") != "pass":
        errors.append("review: handoff result must be pass for complete chain")


def check_delivery(handoff_dir, errors, warn_only=False):
    path = os.path.join(handoff_dir, "delivery-quality.json")
    if not os.path.isfile(path):
        msg = "complete: handoff/delivery-quality.json missing (run write-delivery-quality on complete post)"
        if warn_only:
            return [msg]
        errors.append(msg)
        return
    try:
        doc = json.load(open(path, encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        errors.append(f"complete: delivery-quality.json invalid: {e}")
        return
    for key in DELIVERY_REQUIRED:
        if key not in doc:
            errors.append(f"delivery-quality: missing {key!r}")
    ver = doc.get("schema_version")
    if ver not in (1, 2):
        errors.append(f"delivery-quality: unsupported schema_version {ver!r}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--task-dir", required=True)
    p.add_argument("--state-file", default="")
    p.add_argument("--stage", default="", help="single stage or empty for all present handoffs")
    p.add_argument("--require-delivery", action="store_true", help="fail if delivery-quality.json missing")
    p.add_argument(
        "--only-present",
        action="store_true",
        help="only validate stages whose handoff file already exists",
    )
    args = p.parse_args()

    paths = resolve_paths(args.task_dir, args.state_file)
    handoff_dir = paths["handoff_dir"]
    errors = []

    stages = [args.stage] if args.stage else list(STAGE_FILES.keys())
    for st in stages:
        if st not in STAGE_FILES:
            errors.append(f"unknown stage {st!r}")
            continue
        if args.only_present:
            spec = STAGE_FILES[st]
            names = spec if isinstance(spec, tuple) else (spec,)
            if not any(os.path.isfile(os.path.join(handoff_dir, n)) for n in names):
                continue
        check_stage(handoff_dir, st, errors)

    if args.require_delivery or args.stage == "complete" or (not args.stage and os.path.isfile(os.path.join(handoff_dir, "complete.json"))):
        check_delivery(handoff_dir, errors, warn_only=not args.require_delivery)

    out = {"ok": len(errors) == 0, "errors": errors, "handoff_dir": handoff_dir}
    print(json.dumps(out, ensure_ascii=False, indent=2))
    sys.exit(0 if out["ok"] else 1)


if __name__ == "__main__":
    main()
