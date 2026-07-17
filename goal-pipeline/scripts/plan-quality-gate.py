#!/usr/bin/env python3
"""plan-quality-gate — PQ firewall for plan stage (shared by both tracks)."""
from __future__ import annotations

import argparse
import json
import os
import re
import sys


def parse_args():
    p = argparse.ArgumentParser(description="Plan quality gate (PQ-01..PQ-07)")
    p.add_argument("--task-dir", required=True)
    p.add_argument("--tier", choices=("standard", "strict"), default="standard")
    p.add_argument("--rules", default="")
    p.add_argument("--json", action="store_true", dest="as_json")
    return p.parse_args()


def load_rules(path: str) -> dict:
    if not path:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        path = os.path.join(script_dir, "..", "references", "plan-quality-rules.json")
    with open(path, encoding="utf-8") as f:
        return json.load(f)


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
        if ":" in s and not s.startswith("#"):
            k, v = s.split(":", 1)
            out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def severity_for(rule: dict, tier: str) -> str:
    return rule.get(tier, rule.get("standard", "warn"))


def check_pq01(index_text: str, tier: str, rules: dict) -> list[dict]:
    issues = []
    sev = severity_for(rules["rules"]["PQ-01"], tier)
    has_ws = bool(re.search(r"write_set\s*[:：]|##\s*(write_set|写集)", index_text, re.I))
    if not has_ws:
        issues.append({"id": "PQ-01", "severity": sev, "message": "index.md missing write_set section"})
        return issues
    ws = re.search(r"(?:write_set\s*[:：]|##\s*(?:write_set|写集))\s*(.+?)(?:\n##|\Z)", index_text, re.I | re.S)
    body = (ws.group(1) if ws else "").strip()
    if not body or body in ("-", "无", "none", "N/A"):
        issues.append({"id": "PQ-01", "severity": sev, "message": "write_set is empty"})
    return issues


def check_pq02(index_text: str, tier: str, rules: dict) -> list[dict]:
    issues = []
    sev = severity_for(rules["rules"]["PQ-02"], tier)
    ids = re.findall(r"\b(?:C|V|AC|TC)\d+\b", index_text)
    if not ids:
        issues.append({"id": "PQ-02", "severity": sev, "message": "no acceptance matrix ids (C#/V#/AC#/TC#) in index.md"})
    return issues


def check_pq03(index_text: str, tier: str, rules: dict) -> list[dict]:
    issues = []
    sev = severity_for(rules["rules"]["PQ-03"], tier)
    if not re.search(r"验收|acceptance", index_text, re.I):
        issues.append({"id": "PQ-03", "severity": sev, "message": "no acceptance matrix section"})
        return issues
    if not re.search(r"执行方式|验证|oracle|automated|manual", index_text, re.I):
        issues.append({"id": "PQ-03", "severity": sev, "message": "acceptance matrix missing execution/verification columns"})
    return issues


def check_pq04(index_text: str, tier: str, rules: dict) -> list[dict]:
    issues = []
    sev = severity_for(rules["rules"]["PQ-04"], tier)
    for phrase in rules.get("fuzzy_phrases", []):
        if phrase in index_text:
            issues.append({"id": "PQ-04", "severity": sev, "message": f"fuzzy acceptance phrase: {phrase}"})
    return issues


def check_pq05(index_text: str, tier: str, rules: dict) -> list[dict]:
    issues = []
    sev = severity_for(rules["rules"]["PQ-05"], tier)
    blockers = re.search(r"blockers?\s*[:：](.+?)(?:\n#|\Z)", index_text, re.I | re.S)
    if blockers:
        section = blockers.group(1)
        if re.search(r"P0|未解决|open|blocking", section, re.I):
            issues.append({"id": "PQ-05", "severity": sev, "message": "unresolved P0 blockers in plan"})
    return issues


def check_pq06(index_text: str, tier: str, rules: dict) -> list[dict]:
    issues = []
    rule = rules["rules"]["PQ-06"]
    min_chars = rule.get(f"{tier}_min_chars", rule.get("standard_min_chars", 200))
    pseudo = re.search(r"伪代码|pseudocode", index_text, re.I)
    if not pseudo:
        issues.append({"id": "PQ-06", "severity": "warn", "message": "no pseudocode section"})
        return issues
    start = pseudo.start()
    chunk = index_text[start : start + 4000]
    if len(chunk.strip()) < min_chars:
        issues.append({
            "id": "PQ-06",
            "severity": "warn" if tier == "standard" else "block",
            "message": f"pseudocode section shorter than {min_chars} chars",
        })
    return issues


def _write_set_paths(index_text: str) -> list[str]:
    ws = re.search(
        r"(?:write_set\s*[:：]|##\s*(?:write_set|写集|范围与写集))\s*(.+?)(?:\n##|\Z)",
        index_text,
        re.I | re.S,
    )
    if not ws:
        return []
    paths: list[str] = []
    for line in ws.group(1).splitlines():
        s = line.strip()
        if s.startswith("- "):
            s = s[2:].strip()
        s = s.strip("`").strip()
        if s.startswith("src/") or s.startswith("docs/"):
            paths.append(s.replace("\\", "/"))
    return paths


def _write_set_touches_pages(paths: list[str]) -> bool:
    for path in paths:
        if path.startswith("src/pages/") or path in ("src/App.tsx", "src/pages/index.ts"):
            return True
        if path.endswith("/") and path.startswith("src/pages/"):
            return True
    return False


def check_pq07(index_text: str, tier: str, rules: dict) -> list[dict]:
    issues = []
    sev = severity_for(rules["rules"]["PQ-07"], tier)
    paths = _write_set_paths(index_text)
    if not _write_set_touches_pages(paths):
        return issues
    # Accept explicit build:beta, V0x build rows, or h5-profile verification template markers
    has_build = bool(
        re.search(
            r"build:beta|yarn\s+build:beta|CI=\s*yarn\s+build|h5-build|V0\d+.*build|验证命令.*build",
            index_text,
            re.I,
        )
    )
    if not has_build:
        issues.append(
            {
                "id": "PQ-07",
                "severity": sev,
                "message": (
                    "write_set touches src/pages but index.md missing build:beta — "
                    "add acceptance row e.g. `| V02 | yarn build:beta | automated |` "
                    "or verification_commands with `CI= yarn build:beta`"
                ),
                "template_hint": "| V02 | 构建通过 | CI= yarn build:beta | automated |",
            }
        )
    return issues


def run_gate(task_dir: str, tier: str, rules_path: str) -> dict:
    index_path = os.path.join(task_dir, "index.md")
    if not os.path.isfile(index_path):
        return {"passed": False, "blocked": True, "issues": [{"id": "PQ-00", "severity": "block", "message": "index.md missing"}]}

    rules = load_rules(rules_path)
    text = open(index_path, encoding="utf-8").read()
    fm = front_matter(index_path)
    tier = fm.get("quality_tier", tier) or tier

    issues: list[dict] = []
    for fn in (check_pq01, check_pq02, check_pq03, check_pq04, check_pq05, check_pq06, check_pq07):
        issues.extend(fn(text, tier, rules))

    blocked = any(i["severity"] == "block" for i in issues)
    return {
        "passed": not blocked,
        "blocked": blocked,
        "tier": tier,
        "issues": issues,
        "warnings": [i for i in issues if i["severity"] == "warn"],
    }


def main():
    args = parse_args()
    result = run_gate(args.task_dir, args.tier, args.rules)
    if args.as_json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        for i in result["issues"]:
            print(f"[{i['severity'].upper()}] {i['id']}: {i['message']}")
    sys.exit(0 if result["passed"] else 1)


if __name__ == "__main__":
    main()
