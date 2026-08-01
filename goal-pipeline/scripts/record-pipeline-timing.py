#!/usr/bin/env python3
"""record-pipeline-timing — Append UTC stage timing into evidence/pipeline-timing.json.

Usage:
  record-pipeline-timing.py --task-dir PATH --stage plan|implement|quality|review|complete \
      --event start|end|mark [--substep NAME] [--duration-ms N] [--state-file PATH] [--project-root PATH]
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def resolve_evidence(task_dir: str, state_file: str, project_root: str) -> Path:
    script_dir = Path(__file__).resolve().parent
    resolver = script_dir / "resolve-artifact-paths.py"
    if resolver.is_file():
        args = [sys.executable, str(resolver), "--task-dir", task_dir, "--format", "json"]
        if state_file:
            args.extend(["--state-file", state_file])
        if project_root:
            args.extend(["--project-root", project_root])
        r = subprocess.run(args, capture_output=True, text=True, check=True)
        paths = json.loads(r.stdout)
        return Path(paths["goal_evidence_dir"])
    return Path(task_dir) / "evidence"


def canonical_timing_stage(stage: str) -> str:
    """Map deprecated gate stage ids to v1.2 timing stage ids (B1/B2)."""
    if stage == "smoke":
        return "quality"
    return stage


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--task-dir", required=True)
    ap.add_argument("--stage", required=True)
    ap.add_argument("--event", choices=("start", "end", "mark"), default="mark")
    ap.add_argument("--substep", default="", help="Optional substep name (cwiki, write_index, uvo, attempt, ...)")
    ap.add_argument("--duration-ms", type=int, default=0)
    ap.add_argument("--state-file", default="")
    ap.add_argument("--project-root", default="")
    ap.add_argument("--note", default="")
    args = ap.parse_args()
    stage = canonical_timing_stage(args.stage.strip())
    evidence = resolve_evidence(args.task_dir, args.state_file, args.project_root)
    path = evidence / "pipeline-timing.json"
    doc: dict
    if path.is_file():
        try:
            doc = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            doc = {}
    else:
        doc = {}

    doc.setdefault("schema_version", 1)
    doc.setdefault("timezone", "UTC")
    doc.setdefault("stages", {})
    stages = doc["stages"]
    entry = stages.setdefault(stage, {"events": []})
    ts = utc_now()
    ev = {"event": args.event, "timestamp_utc": ts}
    if args.substep:
        ev["substep"] = args.substep
    if args.duration_ms:
        ev["duration_ms"] = args.duration_ms
    if args.note:
        ev["note"] = args.note
    entry["events"].append(ev)
    if args.event == "start" and not args.substep:
        entry["started_at_utc"] = ts
    if args.event == "end" and args.duration_ms and not args.substep:
        entry["duration_ms"] = args.duration_ms
    if args.substep:
        sub = entry.setdefault("substeps", {})
        slot = sub.setdefault(args.substep, {"events": []})
        slot["events"].append(ev)
        if args.duration_ms and args.event in ("end", "mark"):
            slot["duration_ms"] = args.duration_ms
        slot["last_timestamp_utc"] = ts
    entry["last_timestamp_utc"] = ts
    doc["updated_at_utc"] = ts

    path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(
        json.dumps(
            {
                "ok": True,
                "path": str(path),
                "stage": stage,
                "event": args.event,
                "substep": args.substep or None,
                "timestamp_utc": ts,
            }
        )
    )


if __name__ == "__main__":
    main()
