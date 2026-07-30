#!/usr/bin/env python3
"""plan-quality-gate — PQ firewall for plan stage (shared by both tracks)."""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

# Shared contract parsing (same directory)
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if _SCRIPT_DIR not in sys.path:
    sys.path.insert(0, _SCRIPT_DIR)
from contract_parser import (  # noqa: E402
    api_mapping_self_consistency_issues,
    api_mapping_table_hash,
    frozen_decisions_issues,
    has_api_contract_intent,
    parse_api_mapping_table,
    requires_response_vo_table,
    response_vo_section_present,
)

def parse_args():
    p = argparse.ArgumentParser(description="Plan quality gate (PQ-01..PQ-14)")
    p.add_argument("--task-dir", required=True)
    p.add_argument("--tier", choices=("standard", "strict"), default="standard")
    p.add_argument("--rules", default="")
    p.add_argument("--plan-profile", default="", choices=("", "lite", "full"))
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


def resolve_profile(task_dir: str, explicit: str, index_path: str) -> str:
    if explicit:
        return explicit
    try:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        resolver = os.path.join(script_dir, "resolve_plan_index_rules.py")
        if os.path.isfile(resolver) and os.path.isfile(index_path):
            plan_json = os.path.join(task_dir, "handoff", "plan.json")
            import subprocess
            out = subprocess.check_output(
                [sys.executable, resolver, "--index", index_path, "--plan-json", plan_json, "--format", "json"],
                text=True,
            )
            return json.loads(out).get("profile", "full")
    except Exception:
        pass
    return "full"


def check_pq01(index_text: str, tier: str, rules: dict) -> list[dict]:
    issues = []
    sev = severity_for(rules["rules"]["PQ-01"], tier)
    has_ws = bool(re.search(r"write_set\s*[:：]|##\s*(write_set|写集|范围与写集)", index_text, re.I))
    if not has_ws:
        issues.append({"id": "PQ-01", "severity": sev, "message": "index.md missing write_set section"})
        return issues
    ws = re.search(r"(?:write_set\s*[:：]|##\s*(?:write_set|写集|范围与写集))\s*(.+?)(?:\n##|\Z)", index_text, re.I | re.S)
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


def _pq06_min_chars(rule: dict, tier: str, plan_profile: str) -> int:
    if plan_profile == "lite":
        return int(rule.get("lite_min_chars", 80))
    return int(rule.get(f"{tier}_min_chars", rule.get("standard_min_chars", 200)))


def check_pq06(index_text: str, tier: str, rules: dict, plan_profile: str = "full") -> list[dict]:
    issues = []
    rule = rules["rules"]["PQ-06"]
    min_chars = _pq06_min_chars(rule, tier, plan_profile)
    pseudo = re.search(r"伪代码|pseudocode", index_text, re.I)
    if not pseudo:
        issues.append({"id": "PQ-06", "severity": "warn", "message": "no pseudocode section"})
        return issues
    start = pseudo.start()
    chunk = index_text[start : start + 4000]
    if len(chunk.strip()) < min_chars:
        issues.append({
            "id": "PQ-06",
            "severity": "warn" if tier == "standard" or plan_profile == "lite" else "block",
            "message": f"pseudocode section shorter than {min_chars} chars (profile={plan_profile})",
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


def _acceptance_rows(index_text: str) -> list[str]:
    """Extract acceptance matrix table rows (lines starting with | after a header row)."""
    rows: list[str] = []
    in_matrix = False
    for line in index_text.splitlines():
        s = line.strip()
        if re.search(r"验收|acceptance", s, re.I) and s.startswith("##"):
            in_matrix = True
            continue
        if in_matrix:
            if s.startswith("##"):
                break
            if s.startswith("|") and not re.match(r"^\|[\s\-:|]+\|$", s):
                rows.append(s)
    return rows


def check_pq08(index_text: str, tier: str, rules: dict, plan_profile: str = "full") -> list[dict]:
    """PQ-08: each acceptance row must contain a machine-verifiable column."""
    rule = rules["rules"].get("PQ-08")
    if not rule:
        return []
    # lite → always warn; full+standard → warn; full+strict → block
    if plan_profile == "lite":
        sev = "warn"
    else:
        sev = severity_for(rule, tier)
    rows = _acceptance_rows(index_text)
    issues: list[dict] = []
    machine_re = re.compile(r"verify_command|data-testid|http_assert|automated|CI=|yarn\s|tsc\s|jest\s|pytest|curl\s", re.I)
    for row in rows:
        if not machine_re.search(row):
            issues.append({
                "id": "PQ-08",
                "severity": sev,
                "message": f"acceptance row not machine-verifiable: {row[:80]}",
            })
    return issues


def check_pq09(index_text: str, tier: str, rules: dict, plan_profile: str = "full") -> list[dict]:
    """PQ-09: lite acceptance rows should be 3-5 (warn only, lite only)."""
    rule = rules["rules"].get("PQ-09")
    if not rule or plan_profile != "lite":
        return []
    rows = _acceptance_rows(index_text)
    n = len(rows)
    lo = int(rule.get("lite_min_rows", 3))
    hi = int(rule.get("lite_max_rows", 5))
    if n < lo or n > hi:
        return [{
            "id": "PQ-09",
            "severity": "warn",
            "message": f"lite acceptance rows {n} outside recommended {lo}-{hi}",
        }]
    return []


def _semantic_block_severity(tier: str, rules: dict, rule_id: str, plan_profile: str, fm: dict) -> str:
    rule = rules["rules"].get(rule_id, {})
    if str(fm.get("contract_semantic", "")).lower() in ("required", "1", "true"):
        return "block"
    tt = str(fm.get("task_tier") or "").upper()
    if tt in ("M", "L", "XL"):
        return severity_for(rule, tier)
    if plan_profile == "lite":
        return "warn"
    return severity_for(rule, tier)


def check_pq10(index_text: str, tier: str, rules: dict, plan_profile: str, fm: dict) -> list[dict]:
    issues: list[dict] = []
    inconsistencies = api_mapping_self_consistency_issues(index_text)
    sev_hard = "block"
    for msg in inconsistencies:
        issues.append({"id": "PQ-10", "severity": sev_hard, "message": msg})
    rows = parse_api_mapping_table(index_text)
    if has_api_contract_intent(index_text) and not rows:
        sev = _semantic_block_severity(tier, rules, "PQ-10", plan_profile, fm)
        issues.append(
            {
                "id": "PQ-10",
                "severity": sev,
                "message": "index mentions API paths/keys but missing ## API 与工程映射 table",
            }
        )
    return issues


def check_pq11(index_text: str, tier: str, rules: dict, plan_profile: str, fm: dict) -> list[dict]:
    if not requires_response_vo_table(index_text, fm):
        return []
    if response_vo_section_present(index_text):
        return []
    sev = _semantic_block_severity(tier, rules, "PQ-11", plan_profile, fm)
    return [
        {
            "id": "PQ-11",
            "severity": sev,
            "message": "GET detail (or requires_response_vo) requires ## 响应 VO section with VO fields",
        }
    ]


def check_pq12(task_dir: str, index_text: str, tier: str, rules: dict) -> list[dict]:
    issues: list[dict] = []
    sev = severity_for(rules["rules"].get("PQ-12", {"standard": "block"}), tier)
    for msg in frozen_decisions_issues(task_dir, index_text):
        issues.append({"id": "PQ-12", "severity": sev, "message": msg})
    return issues


def check_pq13(index_text: str, tier: str, rules: dict) -> list[dict]:
    """Warn on duplicate numeric limits for same field label in index."""
    rule = rules["rules"].get("PQ-13")
    if not rule:
        return []
    sev = severity_for(rule, tier)
    issues: list[dict] = []
    # e.g. 凭证 5 张 vs 20 张
    for label in ("凭证", "voucher", "图片"):
        nums = re.findall(rf"{label}[^\d]{{0,20}}(\d+)\s*张", index_text, re.I)
        if len(set(nums)) > 1:
            issues.append(
                {
                    "id": "PQ-13",
                    "severity": sev,
                    "message": f"conflicting counts for {label}: {sorted(set(nums))}",
                }
            )
    return issues


def check_pq14(index_text: str, tier: str, rules: dict, plan_profile: str, fm: dict) -> list[dict]:
    rule = rules["rules"].get("PQ-14")
    if not rule:
        return []
    if not has_api_contract_intent(index_text):
        return []
    sev = severity_for(rule, tier)
    if plan_profile == "lite":
        sev = "warn"
    if re.search(r"display_assert|展示契约|字段路径", index_text, re.I):
        return []
    return [
        {
            "id": "PQ-14",
            "severity": sev,
            "message": "API contract present but acceptance matrix missing display_assert / 展示契约 rows",
        }
    ]


def run_gate(task_dir: str, tier: str, rules_path: str, plan_profile: str = "") -> dict:
    index_path = os.path.join(task_dir, "index.md")
    if not os.path.isfile(index_path):
        return {"passed": False, "blocked": True, "plan_profile": plan_profile or "full", "issues": [{"id": "PQ-00", "severity": "block", "message": "index.md missing"}]}

    rules = load_rules(rules_path)
    text = open(index_path, encoding="utf-8").read()
    fm = front_matter(index_path)
    tier = fm.get("quality_tier", tier) or tier
    plan_profile = plan_profile or resolve_profile(task_dir, str(fm.get("plan_profile") or "").lower(), index_path)

    issues: list[dict] = []
    for fn in (check_pq01, check_pq02, check_pq03, check_pq04, check_pq05):
        issues.extend(fn(text, tier, rules))
    issues.extend(check_pq06(text, tier, rules, plan_profile))
    issues.extend(check_pq07(text, tier, rules))
    issues.extend(check_pq08(text, tier, rules, plan_profile))
    issues.extend(check_pq09(text, tier, rules, plan_profile))
    issues.extend(check_pq10(text, tier, rules, plan_profile, fm))
    issues.extend(check_pq11(text, tier, rules, plan_profile, fm))
    issues.extend(check_pq12(task_dir, text, tier, rules))
    issues.extend(check_pq13(text, tier, rules))
    issues.extend(check_pq14(text, tier, rules, plan_profile, fm))

    api_hash = api_mapping_table_hash(text)
    blocked = any(i["severity"] == "block" for i in issues)
    return {
        "passed": not blocked,
        "blocked": blocked,
        "tier": tier,
        "plan_profile": plan_profile,
        "api_mapping_table_hash": api_hash,
        "issues": issues,
        "warnings": [i for i in issues if i["severity"] == "warn"],
    }


def main():
    args = parse_args()
    result = run_gate(args.task_dir, args.tier, args.rules, args.plan_profile)
    if args.as_json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        for i in result["issues"]:
            print(f"[{i['severity'].upper()}] {i['id']}: {i['message']}")
    sys.exit(0 if result["passed"] else 1)


if __name__ == "__main__":
    main()
