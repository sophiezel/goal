#!/usr/bin/env python3
"""implement-qc-gate — thin wrapper around UVO (IQ firewall).

Legacy entry point: runs UVO or validates existing verification-oracle.json freshness.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import sys


def _load_core():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(script_dir, "verification_oracle_core.py")
    spec = importlib.util.spec_from_file_location("verification_oracle_core", path)
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


def resolve_evidence_dir(task_dir: str) -> str:
    env = os.environ.get("GOAL_EVIDENCE_DIR")
    if env:
        return env
    return os.path.join(task_dir, "evidence")


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
    run_oracle: bool = False,
) -> dict:
    core = _load_core()
    index_path = os.path.join(task_dir, "index.md")
    text = open(index_path, encoding="utf-8").read() if os.path.isfile(index_path) else ""
    fm = front_matter(index_path)
    tier = fm.get("quality_tier", tier) or tier

    issues: list[dict] = []
    executions: list[dict] = []
    evidence_dir = resolve_evidence_dir(task_dir)
    oracle_path = os.path.join(evidence_dir, "verification-oracle.json")

    if skip_test_lint:
        if not os.path.isfile(oracle_path):
            issues.append(
                {
                    "id": "IQ-01",
                    "severity": "block",
                    "message": "verification-oracle.json missing — run verification-oracle.sh first",
                }
            )
        else:
            fresh = core.check_freshness(oracle_path, repo_root)
            if not fresh.get("fresh"):
                issues.append(
                    {
                        "id": "IQ-01",
                        "severity": "block",
                        "message": f"UVO evidence stale: {fresh.get('reason', 'unknown')}",
                    }
                )
            else:
                executions.append({"id": "UVO-freshness", "ok": True, "source": "verification-oracle.json"})
    elif run_oracle or not os.path.isfile(oracle_path):
        oracle_mode = "full_suite" if tier == "strict" else "related_union"
        result = core.run_oracle(task_dir, repo_root, tier=tier, oracle_mode=oracle_mode, evidence_dir=evidence_dir)
        executions.extend(result.get("steps", []))
        if result.get("overall") != "pass":
            issues.append(
                {
                    "id": "IQ-01",
                    "severity": "block",
                    "message": f"verification-oracle not_pass (mode={oracle_mode})",
                }
            )
    else:
        fresh = core.check_freshness(oracle_path, repo_root)
        if not fresh.get("fresh"):
            oracle_mode = "full_suite" if tier == "strict" else "related_union"
            result = core.run_oracle(task_dir, repo_root, tier=tier, oracle_mode=oracle_mode, evidence_dir=evidence_dir)
            executions.extend(result.get("steps", []))
            if result.get("overall") != "pass":
                issues.append({"id": "IQ-01", "severity": "block", "message": "verification-oracle rerun failed"})
        else:
            executions.append({"id": "UVO-freshness", "ok": True, "source": oracle_path})

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
    p = argparse.ArgumentParser(description="Implement QC gate (IQ thin wrapper → UVO)")
    p.add_argument("--task-dir", required=True)
    p.add_argument("--repo-root", default="")
    p.add_argument("--tier", choices=("standard", "strict"), default="standard")
    p.add_argument("--skip-test-lint", action="store_true", help="Only check UVO evidence freshness")
    p.add_argument("--run-oracle", action="store_true", help="Force run UVO")
    p.add_argument("--profile", default="h5")
    p.add_argument("--json", action="store_true", dest="as_json")
    args = p.parse_args()
    repo = args.repo_root or os.environ.get("GOAL_REPO_ROOT", "") or os.getcwd()
    result = run_gate(args.task_dir, repo, args.tier, args.skip_test_lint, args.profile, args.run_oracle)
    if args.as_json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        for i in result["issues"]:
            print(f"[{i['severity'].upper()}] {i['id']}: {i['message']}")
    sys.exit(0 if result["passed"] else 1)


if __name__ == "__main__":
    main()
