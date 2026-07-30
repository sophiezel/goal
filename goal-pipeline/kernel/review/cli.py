#!/usr/bin/env python3
"""ReviewKernel CLI — invoke / run boundaries for goal-run-review-chain.sh."""
from __future__ import annotations

import argparse
import os
import subprocess
import sys

_ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, _ROOT)

from kernel.review.invoke import invoke_independent_review  # noqa: E402


def _scripts_dir() -> str:
    return os.path.join(_ROOT, "scripts")


def cmd_invoke(args: argparse.Namespace) -> int:
    return invoke_independent_review(
        _scripts_dir(),
        args.task_dir,
        args.state_file or "",
        args.project_root or "",
        args.mode,
    )


def cmd_run(args: argparse.Namespace) -> int:
    """assemble-review-packet + invoke + merge-review-issues (same order as goal-run-review-chain)."""
    sd = _scripts_dir()
    common = ["--task-dir", args.task_dir]
    if args.state_file:
        common += ["--state-file", args.state_file]
    if args.project_root:
        common += ["--project-root", args.project_root]
    assemble = os.path.join(sd, "assemble-review-packet.sh")
    merge = os.path.join(sd, "merge-review-issues.sh")
    if not os.path.isfile(assemble):
        print("review cli: assemble-review-packet.sh missing", file=sys.stderr)
        return 2
    subprocess.check_call(["bash", assemble] + common)
    rc = invoke_independent_review(sd, args.task_dir, args.state_file or "", args.project_root or "", args.mode)
    if rc != 0:
        return rc
    if not os.path.isfile(merge):
        print("review cli: merge-review-issues.sh missing", file=sys.stderr)
        return 2
    unified = args.unified_json
    if not unified:
        resolver = os.path.join(sd, "resolve-artifact-paths.py")
        out = subprocess.check_output(
            [sys.executable, resolver, "--task-dir", args.task_dir, "--format", "json"]
            + (["--state-file", args.state_file] if args.state_file else []),
            text=True,
        )
        paths = __import__("json").loads(out)
        unified = os.path.join(paths["goal_evidence_dir"], "review-unified.json")
    return subprocess.call(["bash", merge] + common + ["--unified-json", unified])


def main() -> int:
    p = argparse.ArgumentParser(prog="review-kernel")
    sub = p.add_subparsers(dest="command", required=True)
    pi = sub.add_parser("invoke", help="L2 independent review only")
    pi.add_argument("--task-dir", required=True)
    pi.add_argument("--state-file", default="")
    pi.add_argument("--project-root", default="")
    pi.add_argument("--mode", default=os.environ.get("GOAL_REVIEW_MODE", "unified"))
    pi.set_defaults(func=cmd_invoke)
    pr = sub.add_parser("run", help="assemble + invoke + merge")
    pr.add_argument("--task-dir", required=True)
    pr.add_argument("--state-file", default="")
    pr.add_argument("--project-root", default="")
    pr.add_argument("--mode", default=os.environ.get("GOAL_REVIEW_MODE", "unified"))
    pr.add_argument("--unified-json", default="")
    pr.set_defaults(func=cmd_run)
    args = p.parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    sys.exit(main())
