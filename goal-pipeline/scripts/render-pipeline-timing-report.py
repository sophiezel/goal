#!/usr/bin/env python3
"""Render pipeline timing report (Markdown v0 / HTML v1) from evidence artifacts."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from pipeline_timing_report_core import (
    build_report_model,
    frontmatter,
    load_json,
    render_html,
    render_markdown,
)


def resolve_goal_evidence(task_dir: str, state_file: str, project_root: str) -> Path:
    script_dir = Path(__file__).resolve().parent
    resolver = script_dir / "resolve-artifact-paths.py"
    if resolver.is_file():
        args = [sys.executable, str(resolver), "--task-dir", task_dir, "--format", "json"]
        if state_file:
            args.extend(["--state-file", state_file])
        if project_root:
            args.extend(["--project-root", project_root])
        r = subprocess.run(args, capture_output=True, text=True, check=True)
        d = json.loads(r.stdout)
        return Path(d["goal_evidence_dir"])
    return Path(task_dir) / "evidence"


def load_artifacts(
    *,
    goal_evidence: Path,
    repo_task: Path,
    timing_json: Path | None,
    uvo_json: Path | None,
    review_json: Path | None,
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], dict[str, str]]:
    if timing_json is not None:
        timing = load_json(timing_json)
        evidence_dir = timing_json.parent
    else:
        timing_path = goal_evidence / "pipeline-timing.json"
        if not timing_path.is_file():
            timing_path = repo_task / "evidence" / "pipeline-timing.json"
        timing = load_json(timing_path)
        evidence_dir = goal_evidence if (goal_evidence / "pipeline-timing.json").is_file() else repo_task / "evidence"

    if uvo_json is not None:
        uvo = load_json(uvo_json)
    else:
        uvo = load_json(goal_evidence / "verification-oracle.json")
        if not uvo:
            uvo = load_json(repo_task / "evidence" / "verification-oracle.json")

    if review_json is not None:
        review_run = load_json(review_json)
    else:
        review_run = load_json(goal_evidence / "review-run.json")
        if not review_run:
            review_run = load_json(repo_task / "evidence" / "review-run.json")

    smoke_fm: dict[str, str] = {}
    for base in (evidence_dir, goal_evidence, repo_task / "evidence"):
        smoke_md = base / "runtime-smoke.md"
        if smoke_md.is_file():
            smoke_fm = frontmatter(smoke_md.read_text(encoding="utf-8"))
            break

    return timing, uvo, review_run, smoke_fm


def main() -> int:
    ap = argparse.ArgumentParser(description="Generate pipeline timing report (markdown or html)")
    ap.add_argument("--task-dir", default="", help="Task directory (guazi-flow task or fixture root)")
    ap.add_argument("--state-file", default="")
    ap.add_argument("--project-root", default="")
    ap.add_argument("--task-id", default="")
    ap.add_argument("--git-short-head", default="unknown")
    ap.add_argument(
        "--format",
        choices=("markdown", "html", "md"),
        default="markdown",
        help="Output format (html = v1 dashboard)",
    )
    ap.add_argument(
        "--timing-json",
        default="",
        help="Direct path to pipeline-timing.json (fixture-friendly; skips task-dir timing resolve)",
    )
    ap.add_argument("--uvo-json", default="", help="Optional verification-oracle.json path")
    ap.add_argument("--review-json", default="", help="Optional review-run.json path")
    ap.add_argument("--output", default="", help="Write report to file; default stdout")
    args = ap.parse_args()

    timing_path = Path(args.timing_json).resolve() if args.timing_json else None
    if not args.task_dir and timing_path is None:
        ap.error("provide --task-dir or --timing-json")

    repo_task = Path(args.task_dir).resolve() if args.task_dir else (timing_path.parent.parent if timing_path else Path.cwd())
    task_id = args.task_id or repo_task.name
    goal_ev = resolve_goal_evidence(str(repo_task), args.state_file, args.project_root) if args.task_dir else repo_task / "evidence"

    timing, uvo, review_run, smoke_fm = load_artifacts(
        goal_evidence=goal_ev,
        repo_task=repo_task,
        timing_json=timing_path,
        uvo_json=Path(args.uvo_json).resolve() if args.uvo_json else None,
        review_json=Path(args.review_json).resolve() if args.review_json else None,
    )
    if not timing:
        print("error: pipeline-timing.json missing or empty", file=sys.stderr)
        return 1

    model = build_report_model(
        task_id=task_id,
        git_short_head=args.git_short_head,
        timing=timing,
        uvo=uvo,
        review_run=review_run,
        smoke_fm=smoke_fm,
    )
    fmt = "markdown" if args.format == "md" else args.format
    body = render_html(model) if fmt == "html" else render_markdown(model)
    if not body.endswith("\n"):
        body += "\n"

    if args.output:
        out = Path(args.output)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(body, encoding="utf-8")
        print(str(out))
    else:
        print(body, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
