#!/usr/bin/env python3
"""implement-qc-gate — IQ firewall after implement (shared by both tracks)."""
from __future__ import annotations

import argparse
import importlib.util
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
    p.add_argument("--profile", default="h5")
    p.add_argument("--json", action="store_true", dest="as_json")
    return p.parse_args()


def _load_resolver():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(script_dir, "resolve_verification_commands.py")
    spec = importlib.util.spec_from_file_location("resolve_verification_commands", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


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


def run_shell_command(cmd: str, repo_root: str) -> dict:
    result = subprocess.run(
        cmd,
        shell=True,
        cwd=repo_root,
        capture_output=True,
        text=True,
        timeout=900,
    )
    tail = (result.stdout or "") + (result.stderr or "")
    tail = tail[-1500:] if tail else ""
    return {
        "cmd": cmd,
        "exit_code": result.returncode,
        "ok": result.returncode == 0,
        "output_tail": tail,
    }


def check_iq01_verification(repo_root: str, task_dir: str, profile: str, skip: bool) -> tuple[list[dict], list[dict]]:
    if skip or not repo_root or not os.path.isdir(repo_root):
        return (
            [{"id": "IQ-01", "severity": "warn", "message": "verification not run (no repo-root or skipped)"}],
            [],
        )

    resolver = _load_resolver()
    resolved = resolver.resolve_verification_commands(task_dir, repo_root, profile)
    commands = resolved.get("commands") or []
    executions: list[dict] = []
    issues: list[dict] = []

    if not commands:
        return (
            [{"id": "IQ-01", "severity": "warn", "message": "no verification commands resolved"}],
            executions,
        )

    for item in commands:
        cmd = item["cmd"]
        cmd_id = item.get("id", cmd[:40])
        exec_result = run_shell_command(cmd, repo_root)
        exec_result["id"] = cmd_id
        exec_result["source"] = item.get("source", "")
        executions.append(exec_result)
        if not exec_result["ok"]:
            issues.append(
                {
                    "id": "IQ-01",
                    "severity": "block",
                    "message": f"{cmd_id} failed (exit {exec_result['exit_code']}): {cmd[:120]}",
                }
            )

    return issues, executions


def check_iq02(index_text: str, tier: str) -> list[dict]:
    if tier != "strict":
        return []
    v_ids = set(re.findall(r"\b(?:C|V|AC|TC)\d+\b", index_text))
    impl_cov = set(
        re.findall(
            r"\b(?:C|V|AC|TC)\d+\b",
            index_text.split("implement")[-1] if "implement" in index_text.lower() else "",
        )
    )
    if not v_ids:
        return [{"id": "IQ-02", "severity": "block", "message": "strict tier: no V# in plan for coverage check"}]
    if len(impl_cov) < len(v_ids) * 0.5:
        return [
            {
                "id": "IQ-02",
                "severity": "block",
                "message": f"strict tier: implement section declares <50% V# coverage ({len(impl_cov)}/{len(v_ids)})",
            }
        ]
    return []


def run_gate(
    task_dir: str,
    repo_root: str,
    tier: str,
    skip_test_lint: bool,
    profile: str = "h5",
) -> dict:
    index_path = os.path.join(task_dir, "index.md")
    text = open(index_path, encoding="utf-8").read() if os.path.isfile(index_path) else ""
    fm = front_matter(index_path)
    tier = fm.get("quality_tier", tier) or tier

    issues: list[dict] = []
    iq01_issues, executions = check_iq01_verification(repo_root, task_dir, profile, skip_test_lint)
    issues.extend(iq01_issues)
    issues.extend(check_iq02(text, tier))

    blocked = any(i["severity"] == "block" for i in issues)
    return {
        "passed": not blocked,
        "blocked": blocked,
        "tier": tier,
        "issues": issues,
        "verification_executions": executions,
    }


def main():
    args = parse_args()
    repo = args.repo_root or os.environ.get("GOAL_REPO_ROOT", "")
    if not repo:
        repo = os.getcwd()
    result = run_gate(args.task_dir, repo, args.tier, args.skip_test_lint, args.profile)
    if args.as_json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        for i in result["issues"]:
            print(f"[{i['severity'].upper()}] {i['id']}: {i['message']}")
    sys.exit(0 if result["passed"] else 1)


if __name__ == "__main__":
    main()
