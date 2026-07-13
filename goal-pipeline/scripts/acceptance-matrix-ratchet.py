#!/usr/bin/env python3
"""Deterministic acceptance-matrix ratchet (AM-01..AM-05)."""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import sys
from datetime import datetime, timezone
from typing import Any


def _load_diff_resolver(script_dir: str):
    path = os.path.join(script_dir, "diff_resolver.py")
    spec = importlib.util.spec_from_file_location("diff_resolver", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _glob_covered(path: str, write_set: list[str]) -> bool:
    for w in write_set:
        w = (w or "").strip().rstrip("/")
        if not w:
            continue
        if w.endswith("/**"):
            prefix = w[:-3].rstrip("/")
            if path == prefix or path.startswith(prefix + "/"):
                return True
        elif path == w or path.startswith(w + "/"):
            return True
    return False


def _write_set_globs(write_set: list[str]) -> list[str]:
    out: list[str] = []
    for w in write_set:
        w = (w or "").strip().rstrip("/")
        if w and not w.endswith("/**"):
            if w.endswith("/"):
                out.append(w.rstrip("/") + "/**")
            else:
                out.append(w)
    return out


def run_ratchet(
    task_dir: str,
    repo_root: str,
    plan: dict[str, Any],
    uvo: dict[str, Any] | None = None,
) -> dict[str, Any]:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    dr = _load_diff_resolver(script_dir)
    write_set = plan.get("write_set") or []
    ref_branch = plan.get("reference_branch") or plan.get("reference_impl_branch") or "main...HEAD"
    diff_text, _, _ = dr.resolve_implementation_diff(repo_root, plan, write_set, max_bytes=2_000_000)
    changed = dr.changed_files_for_plan(repo_root, plan, write_set)

    checks: list[dict[str, Any]] = []

    # AM-01: each write_set glob has >=1 changed file
    globs = _write_set_globs([w for w in write_set if str(w).startswith("src/")])
    for g in globs:
        prefix = g[:-3] if g.endswith("/**") else g
        hit = any(c == prefix or c.startswith(prefix + "/") for c in changed)
        checks.append({"id": "AM-01", "glob": g, "pass": hit, "detail": "" if hit else "no changed file in glob"})

    # AM-02: route hints from index (App.tsx / pages/index.ts if in write_set)
    route_hints = ["App.tsx", "pages/index.ts", "routes"]
    needs_route = any("App.tsx" in w or "pages/index.ts" in w or "routes" in w for w in write_set)
    if needs_route:
        route_ok = any(h in diff_text for h in route_hints) or any("App.tsx" in c or "pages/index.ts" in c for c in changed)
        checks.append({"id": "AM-02", "pass": route_ok, "detail": "route-related paths in diff" if route_ok else "missing route diff"})
    else:
        checks.append({"id": "AM-02", "pass": True, "detail": "skipped — write_set has no route entry"})

    # AM-03: services layer touched when write_set includes services
    needs_svc = any("services/" in w for w in write_set)
    if needs_svc:
        svc_ok = any("services/" in c for c in changed) or "services/" in diff_text
        checks.append({"id": "AM-03", "pass": svc_ok, "detail": "" if svc_ok else "services not in diff"})
    else:
        checks.append({"id": "AM-03", "pass": True, "detail": "skipped"})

    # AM-04: no obvious out-of-scope prefixes (jian-rn, android, ios)
    forbidden = ("jian-rn/", "android/", "ios/")
    bad = [c for c in changed if c.startswith(forbidden)]
    checks.append({"id": "AM-04", "pass": len(bad) == 0, "detail": ", ".join(bad[:5]) if bad else ""})

    # AM-05: plan verification_commands reflected in UVO steps
    plan_cmds = plan.get("verification_commands") or []
    if plan_cmds and uvo:
        uvo_cmds = " ".join(str(c) for c in (uvo.get("commands") or []))
        aligned = all(str(item.get("cmd", ""))[:20] in uvo_cmds or str(item.get("id", "")) in uvo_cmds for item in plan_cmds if item.get("cmd"))
        checks.append({"id": "AM-05", "pass": aligned, "detail": "plan cmds vs UVO" if aligned else "UVO commands mismatch plan"})
    else:
        checks.append({"id": "AM-05", "pass": True, "detail": "skipped — no plan cmds or UVO"})

    # AM-06: UI refresh / seamless loading heuristic (C04 class — warning only)
    index_path = os.path.join(task_dir, "index.md")
    pseudo = ""
    if os.path.isfile(index_path):
        try:
            text = open(index_path, encoding="utf-8").read()
            m = re.search(r"## 完整伪代码\s*\n(.*?)(?=\n## |\Z)", text, re.DOTALL)
            pseudo = m.group(1) if m else text
        except OSError:
            pseudo = ""
    wants_seamless = bool(re.search(r"无缝|下拉刷新|pull\s*refresh|refreshing", pseudo, re.I))
    full_page_loader = bool(re.search(r"DotLoading|PageLoading|全屏.*loading|replace.*content", diff_text, re.I))
    if wants_seamless and full_page_loader:
        checks.append(
            {
                "id": "AM-06",
                "pass": False,
                "severity": "warning",
                "detail": "伪代码要求无缝刷新，但 diff 含全页 loading 模式（C04 类风险）",
            }
        )
    else:
        checks.append({"id": "AM-06", "pass": True, "detail": "skipped — no C04 seamless-refresh conflict"})

    blockers = [c for c in checks if not c.get("pass") and c.get("severity") != "warning"]
    return {
        "schema_version": 1,
        "overall": "pass" if not blockers else "not_pass",
        "checks": checks,
        "changed_files_count": len(changed),
        "src_files_in_diff": len(dr.src_files_in_diff(diff_text)),
        "reference_branch": ref_branch,
        "passed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


def main():
    p = argparse.ArgumentParser(description="Acceptance matrix deterministic ratchet")
    p.add_argument("--task-dir", required=True)
    p.add_argument("--repo-root", default=".")
    p.add_argument("--evidence-dir", default="")
    p.add_argument("--json", action="store_true", dest="as_json")
    args = p.parse_args()

    task_dir = os.path.abspath(args.task_dir)
    repo_root = os.path.abspath(args.repo_root or os.getcwd())
    handoff = os.path.join(task_dir, "handoff", "plan.json")
    if not os.path.isfile(handoff):
        handoff = os.path.join(os.environ.get("GOAL_HANDOFF_DIR", ""), "plan.json")
    plan = json.load(open(handoff, encoding="utf-8")) if os.path.isfile(handoff) else {}

    evidence_dir = args.evidence_dir or os.path.join(task_dir, "evidence")
    uvo_path = os.path.join(evidence_dir, "verification-oracle.json")
    uvo = json.load(open(uvo_path, encoding="utf-8")) if os.path.isfile(uvo_path) else None

    result = run_ratchet(task_dir, repo_root, plan, uvo)
    out_path = os.path.join(evidence_dir, "acceptance-matrix-ratchet.json")
    os.makedirs(evidence_dir, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
        f.write("\n")

    if args.as_json:
        result = dict(result)
        result["evidence_path"] = out_path
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(result["overall"])

    sys.exit(0 if result["overall"] == "pass" else 1)


if __name__ == "__main__":
    main()
