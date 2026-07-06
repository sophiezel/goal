#!/usr/bin/env python3
"""migrate-artifacts — Move Tier-R goal artifacts from repo task dir to goal-state runtime."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
RESOLVER = SCRIPT_DIR / "resolve-artifact-paths.py"

TIER_R_EVIDENCE = (
    "runtime-smoke.md",
    "review-goal.json",
    "review-gf.json",
    "review-run.json",
    "review-fix-input.json",
    "review-transcript.md",
)


def resolve_paths(task_dir: str, state_file: str, project_root: str) -> dict:
    args = [sys.executable, str(RESOLVER), "--task-dir", task_dir, "--format", "json"]
    if state_file:
        args.extend(["--state-file", state_file])
    if project_root:
        args.extend(["--project-root", project_root])
    r = subprocess.run(args, capture_output=True, text=True, check=True)
    return json.loads(r.stdout)


def ensure_split_layout(state_file: Path, paths: dict) -> None:
    if not state_file.is_file():
        return
    state = json.loads(state_file.read_text(encoding="utf-8"))
    layout = state.get("artifact_layout") or {}
    layout.update({
        "mode": "split",
        "repo_task_dir": paths["repo_task_dir"],
        "runtime_root": paths["runtime_root"],
    })
    state["artifact_layout"] = layout
    state_file.write_text(json.dumps(state, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def move_tree_files(src_dir: Path, dest_dir: Path, pattern: str | None = None) -> list[str]:
    moved = []
    if not src_dir.is_dir():
        return moved
    dest_dir.mkdir(parents=True, exist_ok=True)
    for item in sorted(src_dir.iterdir()):
        if pattern and not item.match(pattern):
            continue
        target = dest_dir / item.name
        if target.exists():
            if target.is_dir():
                shutil.rmtree(target)
            else:
                target.unlink()
        shutil.move(str(item), str(target))
        moved.append(str(item.relative_to(src_dir)))
    return moved


def main() -> None:
    ap = argparse.ArgumentParser(description="Migrate Tier-R artifacts to goal-state runtime")
    ap.add_argument("--task-dir", required=True)
    ap.add_argument("--state-file", default="")
    ap.add_argument("--project-root", default="")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    os.environ.setdefault("GOAL_ARTIFACT_MODE", "split")
    paths = resolve_paths(args.task_dir, args.state_file, args.project_root)
    repo = Path(paths["repo_task_dir"])
    runtime = Path(paths["runtime_root"])
    handoff_src = repo / "handoff"
    handoff_dest = runtime / "handoff"
    evidence_src = repo / "evidence"
    evidence_dest = runtime / "evidence"

    report = {"moved": [], "skipped": [], "runtime_root": str(runtime)}

    if args.dry_run:
        if handoff_src.is_dir():
            report["moved"] += [f"handoff/{p.name}" for p in handoff_src.iterdir()]
        if evidence_src.is_dir():
            for name in TIER_R_EVIDENCE:
                if (evidence_src / name).exists():
                    report["moved"].append(f"evidence/{name}")
            for p in evidence_src.glob("*-gate-fix-input.json"):
                report["moved"].append(f"evidence/{p.name}")
        print(json.dumps(report, indent=2, ensure_ascii=False))
        return

    runtime.mkdir(parents=True, exist_ok=True)
    report["moved"] += [f"handoff/{x}" for x in move_tree_files(handoff_src, handoff_dest)]
    evidence_dest.mkdir(parents=True, exist_ok=True)
    for name in TIER_R_EVIDENCE:
        src = evidence_src / name
        if src.is_file():
            shutil.move(str(src), str(evidence_dest / name))
            report["moved"].append(f"evidence/{name}")
    for p in list(evidence_src.glob("*-gate-fix-input.json")):
        shutil.move(str(p), str(evidence_dest / p.name))
        report["moved"].append(f"evidence/{p.name}")

    if handoff_src.is_dir() and not any(handoff_src.iterdir()):
        handoff_src.rmdir()
        report["moved"].append("handoff/ (removed empty dir)")

    if args.state_file:
        ensure_split_layout(Path(args.state_file), paths)

    print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
