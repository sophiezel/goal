#!/usr/bin/env python3
"""UX scan v1 — heuristics UX-D1/D2/D5 on write_set paths (warn-only)."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


def resolve_paths(task_dir: str, state_file: str, project_root: str) -> tuple[Path, Path, Path]:
    script_dir = Path(__file__).resolve().parent
    resolver = script_dir / "resolve-artifact-paths.py"
    if resolver.is_file():
        args = [sys.executable, str(resolver), "--task-dir", task_dir, "--format", "json"]
        if state_file:
            args.extend(["--state-file", state_file])
        if project_root:
            args.extend(["--project-root", project_root])
        r = subprocess.run(args, capture_output=True, text=True, check=True)
        d = json.loads(r.stdout)
        return Path(d["repo_evidence_dir"]), Path(d["goal_evidence_dir"]), Path(d.get("repo_root") or project_root or ".")
    t = Path(task_dir)
    return t / "evidence", t / "evidence", Path(project_root or ".")


def load_write_set(task_dir: Path) -> list[str]:
    import importlib.util

    script_dir = Path(__file__).resolve().parent
    spec = importlib.util.spec_from_file_location("uvo", script_dir / "verification_oracle_core.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    plan = mod.load_plan_handoff(str(task_dir))
    return list(plan.get("write_set") or [])


def iter_tsx_files(repo_root: Path, write_set: list[str]) -> list[Path]:
    files: list[Path] = []
    for entry in write_set:
        entry = entry.rstrip("/")
        p = repo_root / entry
        if p.is_file() and p.suffix in (".tsx", ".jsx"):
            files.append(p)
        elif p.is_dir():
            for f in p.rglob("*.tsx"):
                files.append(f)
            for f in p.rglob("*.jsx"):
                files.append(f)
    return sorted(set(files))


def scan_d1(text: str, path: str) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    if re.search(r"useEffect\s*\([^)]*fetch|\.then\s*\(|await\s+createRequest", text):
        if not re.search(r"Skeleton|skeleton|loading\s*&&|isLoading|pending", text):
            findings.append(
                {
                    "id": "UX-D1",
                    "severity": "warn",
                    "path": path,
                    "summary": "async fetch without obvious skeleton/loading UI",
                }
            )
    return findings


def scan_d2(text: str, path: str) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    if re.search(r"<Button[^>]+onClick", text) and re.search(r"提交|确认|apply|submit", text, re.I):
        if not re.search(r"loading\s*=\s*\{|disabled\s*=\s*\{|loading\s*&&", text):
            findings.append(
                {
                    "id": "UX-D2",
                    "severity": "warn",
                    "path": path,
                    "summary": "primary Button onClick without loading/disabled binding",
                }
            )
    return findings


def scan_d5(text: str, path: str) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    for m in re.finditer(r"<Button[^>]*>", text):
        tag = m.group(0)
        if "aria-label" in tag or "aria-labelledby" in tag:
            continue
        if re.search(r"icon|Icon|only", tag, re.I) or (">" not in tag and "children" not in tag):
            if ">" in text[m.end(): m.end() + 80] and re.match(r"\s*</Button>", text[m.end(): m.end() + 80]):
                findings.append(
                    {
                        "id": "UX-D5",
                        "severity": "warn",
                        "path": path,
                        "summary": "icon-only or empty Button missing aria-label",
                    }
                )
                break
    return findings


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--task-dir", required=True)
    ap.add_argument("--repo-root", default="")
    ap.add_argument("--state-file", default="")
    ap.add_argument("--project-root", default="")
    ap.add_argument("--format", choices=("json", "text"), default="json")
    args = ap.parse_args()

    task_dir = Path(args.task_dir).resolve()
    repo_ev, goal_ev, repo_root = resolve_paths(args.task_dir, args.state_file, args.project_root or args.repo_root)
    if args.repo_root:
        repo_root = Path(args.repo_root).resolve()

    write_set = load_write_set(task_dir)
    findings: list[dict[str, Any]] = []
    for f in iter_tsx_files(repo_root, write_set):
        try:
            text = f.read_text(encoding="utf-8")
        except OSError:
            continue
        rel = str(f.relative_to(repo_root))
        findings.extend(scan_d1(text, rel))
        findings.extend(scan_d2(text, rel))
        findings.extend(scan_d5(text, rel))

    doc: dict[str, Any] = {
        "schema_version": 1,
        "generated_by": "ux_scan_v1.py",
        "mode": "warn_only",
        "coverage": ["UX-D1", "UX-D2", "UX-D5"],
        "finding_count": len(findings),
        "findings": findings,
    }
    out = goal_ev / "ux-scan.json"
    goal_ev.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    if args.format == "text":
        print(f"ux_scan_v1: {len(findings)} findings -> {out}")
    else:
        print(json.dumps({"ok": True, "path": str(out), "finding_count": len(findings)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
