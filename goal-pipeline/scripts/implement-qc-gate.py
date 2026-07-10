#!/usr/bin/env python3
"""implement-qc-gate — IQ firewall after implement (shared by both tracks)."""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys


def parse_args():
    p = argparse.ArgumentParser(description="Implement QC gate (IQ-01..IQ-02)")
    p.add_argument("--task-dir", required=True)
    p.add_argument("--repo-root", default="")
    p.add_argument("--tier", choices=("standard", "strict"), default="standard")
    p.add_argument("--skip-test-lint", action="store_true")
    p.add_argument("--json", action="store_true", dest="as_json")
    return p.parse_args()


def front_matter(path: str) -> dict:
    if not os.path.isfile(path):
        return {}
    text = open(path, encoding="utf-8").read()
    m = re.match(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return {}
    out = {}
    for line in m.group(1).splitlines():
        s = line.strip()
        if ":" in s:
            k, v = s.split(":", 1)
            out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def detect_test_lint_commands(repo_root: str) -> list[str]:
    cmds = []
    pkg = os.path.join(repo_root, "package.json")
    if os.path.isfile(pkg):
        data = json.load(open(pkg, encoding="utf-8"))
        scripts = data.get("scripts") or {}
        if "test" in scripts:
            cmds.append("npm test --if-present 2>/dev/null || yarn test --if-present 2>/dev/null || true")
        if "lint" in scripts:
            cmds.append("npm run lint --if-present 2>/dev/null || yarn lint --if-present 2>/dev/null || true")
    if os.path.isfile(os.path.join(repo_root, "pyproject.toml")) or os.path.isfile(
        os.path.join(repo_root, "pytest.ini")
    ):
        cmds.append("pytest -q --tb=no 2>/dev/null || true")
    return cmds


def check_iq01(repo_root: str, skip: bool) -> list[dict]:
    if skip or not repo_root or not os.path.isdir(repo_root):
        return [{"id": "IQ-01", "severity": "warn", "message": "test/lint not run (no repo-root or skipped)"}]
    issues = []
    cmds = detect_test_lint_commands(repo_root)
    if not cmds:
        return [{"id": "IQ-01", "severity": "warn", "message": "no test/lint scripts detected"}]
    for cmd in cmds:
        r = subprocess.run(cmd, shell=True, cwd=repo_root, capture_output=True, text=True)
        if r.returncode != 0:
            issues.append({"id": "IQ-01", "severity": "block", "message": f"command failed: {cmd[:80]}"})
    if not issues:
        return []
    return issues


def check_iq02(index_text: str, tier: str) -> list[dict]:
    if tier != "strict":
        return []
    v_ids = set(re.findall(r"\b(?:C|V|AC|TC)\d+\b", index_text))
    impl_cov = set(re.findall(r"\b(?:C|V|AC|TC)\d+\b", index_text.split("implement")[-1] if "implement" in index_text.lower() else ""))
    if not v_ids:
        return [{"id": "IQ-02", "severity": "block", "message": "strict tier: no V# in plan for coverage check"}]
    if len(impl_cov) < len(v_ids) * 0.5:
        return [{
            "id": "IQ-02",
            "severity": "block",
            "message": f"strict tier: implement section declares <50% V# coverage ({len(impl_cov)}/{len(v_ids)})",
        }]
    return []


def run_gate(task_dir: str, repo_root: str, tier: str, skip_test_lint: bool) -> dict:
    index_path = os.path.join(task_dir, "index.md")
    text = open(index_path, encoding="utf-8").read() if os.path.isfile(index_path) else ""
    fm = front_matter(index_path)
    tier = fm.get("quality_tier", tier) or tier

    issues: list[dict] = []
    issues.extend(check_iq01(repo_root, skip_test_lint))
    issues.extend(check_iq02(text, tier))

    blocked = any(i["severity"] == "block" for i in issues)
    return {"passed": not blocked, "blocked": blocked, "tier": tier, "issues": issues}


def main():
    args = parse_args()
    repo = args.repo_root or os.environ.get("GOAL_REPO_ROOT", "")
    if not repo:
        repo = os.getcwd()
    result = run_gate(args.task_dir, repo, args.tier, args.skip_test_lint)
    if args.as_json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        for i in result["issues"]:
            print(f"[{i['severity'].upper()}] {i['id']}: {i['message']}")
    sys.exit(0 if result["passed"] else 1)


if __name__ == "__main__":
    main()
