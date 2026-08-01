#!/usr/bin/env python3
"""CLI: load profile stage_graph (v1.2 Part J) for shell/kernel callers."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_ROOT))

from kernel.profile.stage_graph import (  # noqa: E402
    assert_default_f2_equivalence,
    canonical_stage_id,
    load_stage_graph,
    next_stage_id,
    progress_for_stage,
    stage_ids,
    validate_gate_lib_mapping,
)


def _read_plan(path: Path | None) -> dict | None:
    if not path or not path.is_file():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    p = argparse.ArgumentParser(description="Resolve pipeline stage_graph from profile / plan.json")
    p.add_argument("--profile", default=None, help="pipeline_profile id (default: default or plan)")
    p.add_argument("--plan-json", type=Path, default=None)
    p.add_argument("--task-dir", type=Path, default=None, help="reads handoff/plan.json when set")
    p.add_argument("--scripts-dir", type=Path, default=Path(__file__).resolve().parent)
    p.add_argument("--current-stage", default="", help="for --action next-id")
    p.add_argument(
        "--action",
        choices=("load", "next-id", "progress", "validate-default-f2", "ids"),
        default="load",
    )
    p.add_argument("--format", choices=("json", "shell"), default="json")
    args = p.parse_args()

    plan_path = args.plan_json
    if args.task_dir and not plan_path:
        plan_path = args.task_dir / "handoff" / "plan.json"
    plan = _read_plan(plan_path)

    try:
        graph_doc = load_stage_graph(profile_id=args.profile, plan_json=plan)
    except (OSError, ValueError, json.JSONDecodeError) as e:
        print(json.dumps({"ok": False, "error": str(e)}), file=sys.stderr)
        return 2

    if args.action == "validate-default-f2":
        errs = assert_default_f2_equivalence(graph_doc)
        errs.extend(validate_gate_lib_mapping(graph_doc, args.scripts_dir))
        out = {"ok": not errs, "errors": errs, "profile_id": graph_doc["profile_id"]}
        print(json.dumps(out, ensure_ascii=False, indent=2))
        return 0 if not errs else 1

    if args.action == "ids":
        print(json.dumps(stage_ids(graph_doc)))
        return 0

    if args.action == "next-id":
        cur = canonical_stage_id(args.current_stage)
        nxt = next_stage_id(cur, graph_doc)
        if args.format == "shell":
            print(f"NEXT_STAGE={nxt}")
        else:
            print(json.dumps({"current_stage": cur, "next_stage": nxt}))
        return 0

    if args.action == "progress":
        label = progress_for_stage(args.current_stage, graph_doc)
        if args.format == "shell":
            print(f"PROGRESS={label}")
        else:
            print(json.dumps({"stage": args.current_stage, "progress": label}))
        return 0

    gate_errs = validate_gate_lib_mapping(graph_doc, args.scripts_dir)
    payload = {
        "ok": not gate_errs,
        "profile_id": graph_doc["profile_id"],
        "source": graph_doc.get("source"),
        "stage_graph": graph_doc["stage_graph"],
        "stage_ids": stage_ids(graph_doc),
        "gate_lib_errors": gate_errs,
    }
    if args.format == "shell":
        for k, v in payload.items():
            if isinstance(v, (list, dict)):
                print(f"{k.upper()}={json.dumps(v, ensure_ascii=False)}")
            else:
                print(f"{k.upper()}={v}")
    else:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0 if not gate_errs else 1


if __name__ == "__main__":
    raise SystemExit(main())
