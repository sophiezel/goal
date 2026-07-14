#!/usr/bin/env python3
"""Optional host helper: refuse a write path when FrozenWorkOrder.capability denies it.

Usage:
  assert_capability.py --work-order WO.json --path relative/or/abs [--project-root R]

Exit 0 = allowed; 2 = denied (code_writes_allowed false or deny glob).
Host adapters MUST call this (or assert_plan_before_code) — do not invent parallel rules.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def path_matches(globish: str, rel: str) -> bool:
    g = globish.replace("**/", "").replace("**", "")
    if g.endswith("/**"):
        prefix = g[:-3].rstrip("/")
        return rel == prefix or rel.startswith(prefix + "/")
    if g.endswith("/*"):
        return rel.startswith(g[:-1])
    if "*" in g:
        from fnmatch import fnmatch

        return fnmatch(rel, g)
    return rel == g or rel.startswith(g.rstrip("/") + "/")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--work-order", required=True)
    ap.add_argument("--path", required=True)
    ap.add_argument("--project-root", default="")
    args = ap.parse_args()

    wo = json.loads(Path(args.work_order).read_text(encoding="utf-8"))
    cap = wo.get("capability") or {}
    writes = wo.get("code_writes_allowed")
    if writes is None:
        writes = cap.get("code_writes_allowed", True)

    p = Path(args.path)
    root = Path(args.project_root).resolve() if args.project_root else None
    if root and p.is_absolute():
        try:
            rel = str(p.resolve().relative_to(root)).replace("\\", "/")
        except ValueError:
            rel = str(p)
    else:
        rel = str(p).replace("\\", "/").lstrip("./")

    deny = list(cap.get("deny_write_globs") or [])
    if writes is False or any(path_matches(d, rel) for d in deny):
        print(
            json.dumps(
                {
                    "ok": False,
                    "failure_code": "plan_code_order" if not writes else "write_set_violation",
                    "path": rel,
                    "host_guard": "adapter",
                }
            )
        )
        return 2

    allow = list(cap.get("allowed_write_globs") or [])
    if allow and not any(path_matches(a, rel) for a in allow):
        # soft allow when globs are placeholders like $write_set
        if not any("$" in a for a in allow):
            print(json.dumps({"ok": False, "failure_code": "write_set_violation", "path": rel}))
            return 2

    print(json.dumps({"ok": True, "path": rel}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
