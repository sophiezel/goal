#!/usr/bin/env python3
"""Emit record-pipeline-timing mark events from oracle/smoke/review artifacts."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


def record(task_dir: str, state_file: str, project_root: str, stage: str, substep: str, duration_ms: int) -> None:
    script = Path(__file__).resolve().parent / "record-pipeline-timing.py"
    if not script.is_file() or duration_ms <= 0:
        return
    args = [
        sys.executable,
        str(script),
        "--task-dir",
        task_dir,
        "--stage",
        stage,
        "--event",
        "mark",
        "--substep",
        substep,
        "--duration-ms",
        str(duration_ms),
    ]
    if state_file:
        args.extend(["--state-file", state_file])
    if project_root:
        args.extend(["--project-root", project_root])
    subprocess.run(args, capture_output=True, check=False)


def resolve_goal_evidence(task_dir: str, state_file: str, project_root: str) -> Path:
    resolver = Path(__file__).resolve().parent / "resolve-artifact-paths.py"
    if resolver.is_file():
        args = [sys.executable, str(resolver), "--task-dir", task_dir, "--format", "json"]
        if state_file:
            args.extend(["--state-file", state_file])
        if project_root:
            args.extend(["--project-root", project_root])
        r = subprocess.run(args, capture_output=True, text=True, check=True)
        return Path(json.loads(r.stdout)["goal_evidence_dir"])
    return Path(task_dir) / "evidence"


def sync_uvo(task_dir: str, state_file: str, project_root: str, evidence: Path) -> int:
    uvo = evidence / "verification-oracle.json"
    if not uvo.is_file():
        return 0
    try:
        data = json.loads(uvo.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return 0
    count = 0
    for step in data.get("steps") or []:
        sid = str(step.get("id") or "step")
        ms = int(step.get("duration_ms") or 0)
        if ms > 0:
            record(task_dir, state_file, project_root, "implement", f"uvo_{sid}", ms)
            count += 1
    total = int(data.get("duration_ms") or 0)
    if total > 0:
        record(task_dir, state_file, project_root, "implement", "uvo", total)
    return count


def sync_smoke(task_dir: str, state_file: str, project_root: str, evidence: Path) -> int:
    smoke = evidence / "runtime-smoke.md"
    if not smoke.is_file():
        return 0
    text = smoke.read_text(encoding="utf-8")
    m = re.match(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return 0
    ms = 0
    for line in m.group(1).splitlines():
        if line.strip().startswith("duration_ms:"):
            try:
                ms = int(line.split(":", 1)[1].strip())
            except ValueError:
                ms = 0
    if ms > 0:
        record(task_dir, state_file, project_root, "quality", "runtime_smoke", ms)
        return 1
    return 0


def sync_review(task_dir: str, state_file: str, project_root: str, evidence: Path) -> int:
    run = evidence / "review-run.json"
    if not run.is_file():
        return 0
    try:
        data = json.loads(run.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return 0
    ms = int(data.get("latency_ms") or 0)
    if ms > 0:
        record(task_dir, state_file, project_root, "review", "attempt", ms)
        return 1
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--task-dir", required=True)
    ap.add_argument("--state-file", default="")
    ap.add_argument("--project-root", default="")
    ap.add_argument("--source", choices=("uvo", "smoke", "review", "all"), default="all")
    args = ap.parse_args()
    evidence = resolve_goal_evidence(args.task_dir, args.state_file, args.project_root)
    total = 0
    if args.source in ("uvo", "all"):
        total += sync_uvo(args.task_dir, args.state_file, args.project_root, evidence)
    if args.source in ("smoke", "all"):
        total += sync_smoke(args.task_dir, args.state_file, args.project_root, evidence)
    if args.source in ("review", "all"):
        total += sync_review(args.task_dir, args.state_file, args.project_root, evidence)
    print(json.dumps({"ok": True, "marks_recorded": total}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
