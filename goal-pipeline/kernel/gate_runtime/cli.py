#!/usr/bin/env python3
"""gate_runtime CLI — subject_hash / noop_check for shell gates."""
from __future__ import annotations

import argparse
import os
import sys

_ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, _ROOT)

from kernel.gate_runtime.noop import is_noop_fix  # noqa: E402
from kernel.gate_runtime.subject_hash import code_subject_hash  # noqa: E402


def main() -> int:
    p = argparse.ArgumentParser(prog="gate-runtime")
    sub = p.add_subparsers(dest="command", required=True)
    sh = sub.add_parser("subject-hash")
    sh.add_argument("--repo-root", required=True)
    sh.add_argument("--write-set", default="", help="comma-separated paths")
    sh.add_argument("--ref-branch", default="")
    np = sub.add_parser("noop-check")
    np.add_argument("--previous", required=True)
    np.add_argument("--current", required=True)
    args = p.parse_args()
    if args.command == "subject-hash":
        ws = [x.strip() for x in args.write_set.split(",") if x.strip()] if args.write_set else None
        print(code_subject_hash(args.repo_root, ws, args.ref_branch))
        return 0
    if args.command == "noop-check":
        print("1" if is_noop_fix(args.previous, args.current) else "0")
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main())
