#!/usr/bin/env python3
"""leak-rate-panel — compute pipeline leak rate from handoff + escape data (v3 §3 Wave 2).

Leak = a declared failure-code defect that reached a downstream stage or production
without being caught at its owning gate. This panel reads:
  - handoff/*.json (gate passed_at) to find stages that passed
  - evidence/escape-register.json (Phase B) to find escapes attributed to a stage

Outputs a JSON panel: per-stage leak count, total completes, leak_rate.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone


def load_json(path: str, default=None):
    if path and os.path.isfile(path):
        try:
            return json.load(open(path, encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            pass
    return default if default is not None else {}


def collect_completes(workspace_dir: str) -> list[dict]:
    """Scan goal-pipeline-workspace for completed task dirs with handoff chains."""
    completes = []
    if not os.path.isdir(workspace_dir):
        return completes
    for root, dirs, files in os.walk(workspace_dir):
        if "handoff" in dirs and "complete.json" in os.listdir(os.path.join(root, "handoff")) if os.path.isdir(os.path.join(root, "handoff")) else False:
            handoff_dir = os.path.join(root, "handoff")
            complete = load_json(os.path.join(handoff_dir, "complete.json"))
            if complete:
                completes.append({"task_dir": root, "complete": complete})
    return completes


def collect_escapes(escape_path: str) -> list[dict]:
    return load_json(escape_path, {}).get("escapes", [])


def compute_panel(workspace_dir: str, escape_path: str) -> dict:
    completes = collect_completes(workspace_dir)
    escapes = collect_escapes(escape_path)

    stages = ["plan", "implement", "quality", "review", "complete"]
    stage_leaks = {s: 0 for s in stages}
    stage_passes = {s: 0 for s in stages}

    for c in completes:
        for s in stages:
            handoff = load_json(os.path.join(c["task_dir"], "handoff", f"{s}.json"))
            gate = handoff.get("gate", {}) if isinstance(handoff, dict) else {}
            if gate.get("passed_at"):
                stage_passes[s] += 1

    for e in escapes:
        node = e.get("node", "")
        if node in stage_leaks:
            stage_leaks[node] += 1

    total_completes = len(completes)
    total_escapes = len(escapes)
    leak_rate = round(total_escapes / total_completes, 4) if total_completes else 0.0

    return {
        "schema_version": 1,
        "computed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "workspace_dir": workspace_dir,
        "escape_register": escape_path,
        "total_completes": total_completes,
        "total_escapes": total_escapes,
        "leak_rate": leak_rate,
        "leak_rate_target": 0.10,
        "per_stage": {
            s: {
                "passes": stage_passes[s],
                "leaks": stage_leaks[s],
                "stage_leak_rate": round(stage_leaks[s] / stage_passes[s], 4) if stage_passes[s] else 0.0,
            }
            for s in stages
        },
        "gate_status": "BLOCK" if leak_rate > 0.10 else "OK",
    }


def main() -> int:
    p = argparse.ArgumentParser(description="Leak rate panel (v3 §3 Wave 2)")
    p.add_argument("--workspace", default=os.environ.get("GOAL_PIPELINE_WORKSPACE", ""))
    p.add_argument("--escape-register", default="")
    p.add_argument("--json", action="store_true", dest="as_json")
    args = p.parse_args()

    workspace = args.workspace or os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "..", "goal-pipeline-workspace")
    escape_path = args.escape_register or os.path.join(workspace, "escape-register.json")

    panel = compute_panel(workspace, escape_path)
    if args.as_json:
        print(json.dumps(panel, ensure_ascii=False, indent=2))
    else:
        print(f"Leak Rate Panel ({panel['computed_at']})")
        print(f"  completes: {panel['total_completes']} | escapes: {panel['total_escapes']} | leak_rate: {panel['leak_rate']} (target <{panel['leak_rate_target']})")
        print(f"  gate: {panel['gate_status']}")
        for s, d in panel["per_stage"].items():
            print(f"  {s}: passes={d['passes']} leaks={d['leaks']} stage_leak_rate={d['stage_leak_rate']}")
    return 0 if panel["gate_status"] == "OK" else 1


if __name__ == "__main__":
    sys.exit(main())
