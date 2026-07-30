#!/usr/bin/env python3
"""escape-to-eval.py — Phase B: escape-register entry → skill-upper eval case (v3 §3 Wave 3).

Reads an escape-register.json entry (by id or the latest unresolved) and generates
an eval case YAML in evals/cases/escapes/ that encodes the gate rule the escape
should have caught. The eval case, when run via skill-up, regression-tests that
the gate now blocks the escaped defect class.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone


def load_register(path: str) -> dict:
    return json.load(open(path, encoding="utf-8"))


def pick_escape(register: dict, escape_id: str = "") -> dict:
    escapes = register.get("escapes", [])
    if not escapes:
        raise SystemExit("escape-register has no entries")
    if escape_id:
        for e in escapes:
            if e.get("id") == escape_id:
                return e
        raise SystemExit(f"escape id {escape_id} not found")
    # latest unresolved
    for e in escapes:
        if not e.get("resolved"):
            return e
    return escapes[-1]


def gen_eval_case(escape: dict, repo_root: str) -> str:
    eid = escape.get("id", "ESC-unknown")
    node = escape.get("node", "review")
    rule = escape.get("gate_rule_id", "unknown")
    sev = escape.get("severity", "major")
    summary = escape.get("summary", "")
    root = escape.get("root_cause", "")
    fname = eid.lower().replace("-", "_")
    yaml = f"""# Auto-generated from escape-register {eid} ({datetime.now(timezone.utc).strftime('%Y-%m-%d')})
# Phase B: regression test that gate rule {rule} now blocks this escape class
id: escape-{fname}
title: "escape regression — {eid}: {summary[:60]}"
node: {node}
gate_rule_id: {rule}
severity: {sev}
description: |
  Escape {eid} reached downstream via node '{node}'. Gate rule '{rule}' should have
  blocked it. Root cause: {root}. This eval verifies the gate now catches this class.
expect: block
assertions:
  - gate_rule: {rule}
  - failure_code_present: true
  - silent_pass_forbidden: true
fixtures:
  - path: escapes/{fname}
    description: "reproduces the escaped defect class"
"""
    out_dir = os.path.join(repo_root, "goal-pipeline", "evals", "cases", "escapes")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, f"{fname}.yaml")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(yaml)
    return out_path


def main() -> int:
    p = argparse.ArgumentParser(description="escape-register → eval case (Phase B)")
    p.add_argument("--register", default="")
    p.add_argument("--id", default="", dest="escape_id")
    p.add_argument("--repo-root", default=".")
    p.add_argument("--mark-resolved", action="store_true")
    args = p.parse_args()

    repo_root = os.path.abspath(args.repo_root)
    register_path = args.register or os.path.join(repo_root, "goal-pipeline-workspace", "escape-register.json")
    if not os.path.isfile(register_path):
        register_path = os.path.join(repo_root, "goal-pipeline", "references", "escape-register.template.json")

    register = load_register(register_path)
    escape = pick_escape(register, args.escape_id)
    out_path = gen_eval_case(escape, repo_root)

    if args.mark_resolved:
        for e in register.get("escapes", []):
            if e.get("id") == escape.get("id"):
                e["resolved"] = True
                e["eval_case_path"] = os.path.relpath(out_path, repo_root)
        with open(register_path, "w", encoding="utf-8") as f:
            json.dump(register, f, ensure_ascii=False, indent=2)
            f.write("\n")

    print(json.dumps({
        "escape_id": escape.get("id"),
        "eval_case_path": out_path,
        "gate_rule_id": escape.get("gate_rule_id"),
        "marked_resolved": args.mark_resolved,
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
