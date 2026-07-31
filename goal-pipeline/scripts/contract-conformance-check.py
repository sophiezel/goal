#!/usr/bin/env python3
"""IQ-10: table-driven API mapping conformance against write_set sources."""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if _SCRIPT_DIR not in sys.path:
    sys.path.insert(0, _SCRIPT_DIR)

from contract_parser import (
    ApiMappingRow,
    extract_bindings_for_profile,
    iter_write_set_files,
    parse_api_mapping_table,
)


def resolve_plan_path(
    task_dir: str,
    handoff_dir: str = "",
    repo_root: str = "",
    project_root: str = "",
) -> str:
    from handoff_path_resolver import resolve_plan_json_path

    if handoff_dir and os.path.isdir(handoff_dir):
        return os.path.join(handoff_dir, "plan.json")
    state_file = os.environ.get("GOAL_STATE_FILE", "")
    pr = (project_root or repo_root or os.environ.get("GOAL_REPO_ROOT") or "").strip()
    return resolve_plan_json_path(task_dir, state_file=state_file, project_root=pr)


def parse_args():
    p = argparse.ArgumentParser(description="Contract conformance (IQ-10)")
    p.add_argument("--task-dir", required=True)
    p.add_argument("--repo-root", required=True)
    p.add_argument("--profile", default="")
    p.add_argument("--json", action="store_true", dest="as_json")
    p.add_argument("--evidence", default="", help="write contract-conformance.json")
    p.add_argument("--handoff-dir", default="", help="Tier-R handoff dir (split layout)")
    p.add_argument(
        "--project-root",
        default="",
        help="Git project root for handoff/Tier-R resolution (defaults to --repo-root)",
    )
    return p.parse_args()


def _path_matches(binding_uri: str, row_path: str) -> bool:
    a = binding_uri.strip()
    b = row_path.strip()
    return a == b or a.endswith(b) or b.endswith(a)


def _check_required_params(content: str, params: list[str]) -> list[str]:
    missing: list[str] = []
    for p in params:
        if not re.search(rf"\b{re.escape(p)}\s*:", content) and not re.search(
            rf"['\"]{re.escape(p)}['\"]\s*:", content
        ):
            missing.append(p)
    return missing


def check_row(
    row: ApiMappingRow,
    bindings: list,
    file_contents: dict[str, str],
) -> list[dict]:
    issues: list[dict] = []
    matched = [b for b in bindings if _path_matches(b.uri, row.path)]
    if not matched:
        issues.append(
            {
                "id": "IQ-10",
                "severity": "block",
                "message": f"no createRequest binding for path {row.path}",
                "root_cause": "contract_drift",
            }
        )
        return issues
    if row.request_key:
        if not any(b.request_key.upper() == row.request_key.upper() for b in matched):
            issues.append(
                {
                    "id": "IQ-10",
                    "severity": "block",
                    "message": (
                        f"path {row.path} expected request_key {row.request_key}, "
                        f"found {[b.request_key for b in matched]}"
                    ),
                    "root_cause": "contract_drift",
                }
            )
    if row.required_params:
        for b in matched:
            content = file_contents.get(b.source_file, "")
            miss = _check_required_params(content, row.required_params)
            if miss:
                issues.append(
                    {
                        "id": "IQ-10",
                        "severity": "block",
                        "message": f"path {row.path} missing params {miss} in {os.path.basename(b.source_file)}",
                        "root_cause": "contract_drift",
                    }
                )
    return issues


def run_check(
    task_dir: str,
    repo_root: str,
    profile: str,
    handoff_dir: str = "",
    project_root: str = "",
) -> dict:
    index_path = os.path.join(task_dir, "index.md")
    plan_path = resolve_plan_path(task_dir, handoff_dir, repo_root, project_root)
    if not os.path.isfile(index_path):
        return {
            "passed": False,
            "skipped": False,
            "issues": [{"id": "IQ-10", "severity": "block", "message": "index.md missing"}],
        }
    index_text = open(index_path, encoding="utf-8").read()
    rows = parse_api_mapping_table(index_text)
    if not rows:
        return {"passed": True, "skipped": True, "issues": [], "reason": "no API mapping table"}

    write_set: list[str] = []
    prof = profile
    if os.path.isfile(plan_path):
        plan = json.load(open(plan_path, encoding="utf-8"))
        write_set = plan.get("write_set") or []
        prof = prof or plan.get("profile") or plan.get("profile_detail") or "h5"

    files = iter_write_set_files(repo_root, write_set)
    bindings = []
    file_contents: dict[str, str] = {}
    for fp in files:
        try:
            content = open(fp, encoding="utf-8").read()
        except OSError:
            continue
        file_contents[fp] = content
        bindings.extend(extract_bindings_for_profile(prof, fp, content))

    issues: list[dict] = []
    for row in rows:
        issues.extend(check_row(row, bindings, file_contents))

    blocked = any(i.get("severity") == "block" for i in issues)
    return {
        "passed": not blocked,
        "skipped": False,
        "profile": prof,
        "api_rows": len(rows),
        "bindings_found": len(bindings),
        "issues": issues,
    }


def main():
    args = parse_args()
    repo_root = os.path.abspath(args.repo_root)
    project_root = os.path.abspath(args.project_root or args.repo_root)
    if project_root:
        os.environ.setdefault("GOAL_REPO_ROOT", project_root)
    result = run_check(
        args.task_dir,
        repo_root,
        args.profile,
        args.handoff_dir,
        project_root,
    )
    if args.evidence:
        ev_dir = os.path.dirname(args.evidence)
        if ev_dir:
            os.makedirs(ev_dir, exist_ok=True)
        with open(args.evidence, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2, ensure_ascii=False)
            f.write("\n")
    if args.as_json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    sys.exit(0 if result.get("passed") else 1)


if __name__ == "__main__":
    main()
