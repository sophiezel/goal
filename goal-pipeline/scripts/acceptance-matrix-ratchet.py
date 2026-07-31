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

    # AM-01: untouched write_set globs are warnings + auto-prune (not blockers).
    globs = _write_set_globs([w for w in write_set if str(w).startswith("src/")])
    prune_prefixes: list[str] = []
    for g in globs:
        prefix = g[:-3] if g.endswith("/**") else g
        hit = any(dr.path_allowed(c, [g, prefix]) for c in changed)
        if hit:
            checks.append({"id": "AM-01", "glob": g, "pass": True, "detail": ""})
        else:
            prune_prefixes.append(prefix)
            checks.append(
                {
                    "id": "AM-01",
                    "glob": g,
                    "pass": True,
                    "severity": "warning",
                    "detail": "no changed file in glob — pruned from plan write_set when possible",
                    "prune": True,
                }
            )
    if prune_prefixes:
        from handoff_path_resolver import resolve_plan_json_path

        plan_path = resolve_plan_json_path(task_dir)
        if os.path.isfile(plan_path):
            try:
                with open(plan_path, encoding="utf-8") as pf:
                    plan_doc = json.load(pf)
                old_ws = list(plan_doc.get("write_set") or write_set)
                rebuilt: list[str] = []
                for w in old_ws:
                    wn = (w or "").strip().rstrip("/")
                    if not wn.startswith("src/"):
                        rebuilt.append(w)
                        continue
                    if any(dr.path_allowed(c, [wn, wn + "/**"]) for c in changed):
                        rebuilt.append(w)
                if rebuilt and rebuilt != old_ws:
                    plan_doc["write_set"] = rebuilt
                    plan_doc["write_set_pruned"] = True
                    plan_doc["write_set_pruned_paths"] = prune_prefixes
                    with open(plan_path, "w", encoding="utf-8") as pf:
                        json.dump(plan_doc, pf, indent=2, ensure_ascii=False)
                        pf.write("\n")
                    checks.append(
                        {
                            "id": "AM-01-prune",
                            "pass": True,
                            "severity": "warning",
                            "detail": f"pruned {len(old_ws) - len(rebuilt)} untouched write_set paths",
                        }
                    )
            except (OSError, json.JSONDecodeError, TypeError):
                pass

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
    index_text = ""
    if os.path.isfile(index_path):
        try:
            index_text = open(index_path, encoding="utf-8").read()
            m = re.search(r"## 完整伪代码\s*\n(.*?)(?=\n## |\Z)", index_text, re.DOTALL)
            pseudo = m.group(1) if m else index_text
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

    # AM-07: write_set paths must exist in repo (catch phantom/typo paths) — warn (strict: block)
    tier = str(plan.get("quality_tier") or os.environ.get("GOAL_QUALITY_TIER") or "standard").lower()
    am07_sev = "block" if tier == "strict" else "warning"
    phantom = [w for w in write_set if w and not w.endswith("/**") and not os.path.exists(os.path.join(repo_root, w))]
    if phantom:
        checks.append({"id": "AM-07", "pass": False, "severity": am07_sev, "detail": f"write_set paths not in repo: {', '.join(phantom[:5])}"})
    else:
        checks.append({"id": "AM-07", "pass": True, "detail": "all write_set paths exist"})

    # AM-08: package.json diff must not add forbidden out-of-scope deps — block
    import subprocess as _sp
    forbidden_deps = ("jian-rn", "react-native-", "expo-")
    bad_deps: list[str] = []
    try:
        pkg_diff = _sp.check_output(
            ["git", "-C", repo_root, "diff", "HEAD", "--no-color", "--", "package.json"],
            text=True, stderr=_sp.DEVNULL, timeout=10,
        )
    except Exception:
        pkg_diff = ""
    if pkg_diff:
        for d in forbidden_deps:
            if re.search(r'"' + re.escape(d) + r'[^"]*"\s*:', pkg_diff):
                bad_deps.append(d)
    checks.append({"id": "AM-08", "pass": len(bad_deps) == 0, "severity": "block" if bad_deps else "", "detail": f"forbidden deps added: {', '.join(bad_deps)}" if bad_deps else "no forbidden deps"})

    # AM-09: data-testid declared in acceptance matrix must appear in changed files — warn (strict: block)
    testids_declared: list[str] = re.findall(r'data-testid[=:"\s]+([a-zA-Z0-9_-]+)', index_text)
    if testids_declared:
        diff_blob = diff_text
        missing_tids = [t for t in set(testids_declared) if t not in diff_blob]
        if missing_tids:
            checks.append({"id": "AM-09", "pass": False, "severity": am07_sev, "detail": f"declared data-testid not in diff: {', '.join(sorted(missing_tids)[:5])}"})
        else:
            checks.append({"id": "AM-09", "pass": True, "detail": "all declared data-testid present in diff"})
    else:
        checks.append({"id": "AM-09", "pass": True, "detail": "skipped — no data-testid declared"})

    # AM-10: Stop Conditions referenced when package.json is touched — warn
    touches_pkg = bool(pkg_diff)
    has_stop_cond = bool(re.search(r"Stop\s*Conditions|停止条件|依赖.*Stop", index_text, re.I))
    if touches_pkg and not has_stop_cond:
        checks.append({"id": "AM-10", "pass": False, "severity": "warning", "detail": "write_set touches package.json but index has no Stop Conditions section"})
    else:
        checks.append({"id": "AM-10", "pass": True, "detail": "skipped — no package.json change or Stop Conditions present"})

    blockers = [c for c in checks if not c.get("pass") and c.get("severity") != "warning"]
    matrix_rows: list[dict[str, Any]] = []
    ms = plan.get("matrix_satisfaction")
    if isinstance(ms, dict):
        for entry in ms.get("rows") or []:
            if isinstance(entry, dict) and entry.get("id"):
                matrix_rows.append(dict(entry))
            elif isinstance(entry, str) and entry.strip():
                matrix_rows.append({"id": entry.strip(), "status": "unspecified"})
    return {
        "schema_version": 1,
        "overall": "pass" if not blockers else "not_pass",
        "checks": checks,
        "matrix_rows": matrix_rows,
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

    from handoff_path_resolver import goal_evidence_dir, resolve_plan_json_path

    task_dir = os.path.abspath(args.task_dir)
    repo_root = os.path.abspath(args.repo_root or os.getcwd())
    state_file = (os.environ.get("GOAL_STATE_FILE") or "").strip()
    handoff = resolve_plan_json_path(task_dir, state_file=state_file, project_root=repo_root)
    plan = json.load(open(handoff, encoding="utf-8")) if os.path.isfile(handoff) else {}

    evidence_dir = args.evidence_dir or goal_evidence_dir(task_dir, project_root=repo_root)
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
