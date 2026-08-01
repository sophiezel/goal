#!/usr/bin/env python3
"""P1-9 gate audit: UX auto-fix ⊆ write_set; feature implement diff not mistaken for autofix."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

# Import sibling module (goal-pipeline/scripts)
_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))
from diff_resolver import implement_scope_changed_files, path_allowed  # noqa: E402

_D2_PATTERNS = (
    re.compile(r"loading\s*=\s*\{"),
    re.compile(r"disabled\s*=\s*\{"),
    re.compile(r"loading\s*&&"),
)
_D5_PATTERNS = (
    re.compile(r"aria-label\s*="),
    re.compile(r"aria-labelledby\s*="),
)
_FORBIDDEN_PATH_RE = re.compile(r"(^|/)(App\.tsx|pages/index|/services/|/routes/)", re.I)


def _load_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def load_write_set(handoff_dir: Path) -> list[str]:
    plan = _load_json(handoff_dir / "plan.json")
    return list(plan.get("write_set") or [])


def diff_hunks(repo_root: Path, path: str) -> str:
    r = subprocess.run(
        ["git", "-C", str(repo_root), "-c", "core.quotepath=false", "diff", "HEAD", "--", path],
        capture_output=True,
        text=True,
        check=False,
    )
    if not (r.stdout or "").strip():
        r = subprocess.run(
            ["git", "-C", str(repo_root), "-c", "core.quotepath=false", "diff", "--", path],
            capture_output=True,
            text=True,
            check=False,
        )
    return r.stdout or ""


def _added_lines(hunk_text: str) -> list[str]:
    return [ln[1:] for ln in hunk_text.splitlines() if ln.startswith("+") and not ln.startswith("+++")]


def has_d2_d5_added(hunk_text: str) -> bool:
    for line in _added_lines(hunk_text):
        stripped = line.strip()
        if not stripped or stripped.startswith("//") or stripped.startswith("/*"):
            continue
        if any(p.search(line) for p in _D2_PATTERNS) or any(p.search(line) for p in _D5_PATTERNS):
            return True
    return False


def hunks_match_d2_d5_only(hunk_text: str) -> bool:
    """Added lines should only touch D2/D5-style UX fixes (heuristic)."""
    added = _added_lines(hunk_text)
    if not added:
        return True
    for line in added:
        stripped = line.strip()
        if not stripped or stripped.startswith("//") or stripped.startswith("/*"):
            continue
        if any(p.search(line) for p in _D2_PATTERNS) or any(p.search(line) for p in _D5_PATTERNS):
            continue
        if re.search(r"^\+\s*import\s+", line):
            return False
        if re.search(r"createRequest|axios|fetch\(|router|Route|navigate\(", line, re.I):
            return False
        if re.search(r"export\s+(default\s+)?function|export\s+const", line):
            return False
        if re.fullmatch(r"[}\]);,\s]*", stripped):
            continue
        return False
    return True


def audit(*, repo_root: Path, handoff_dir: Path, strict: bool) -> dict[str, Any]:
    write_set = load_write_set(handoff_dir)
    violations: list[dict[str, str]] = []
    audited: list[str] = []
    changed = implement_scope_changed_files(str(repo_root))

    for path in changed:
        hunk = diff_hunks(repo_root, path)
        if not hunk.strip():
            continue
        in_ws = bool(write_set) and path_allowed(path, write_set)
        d2d5_only = hunks_match_d2_d5_only(hunk)
        has_d2d5 = has_d2_d5_added(hunk)

        if not in_ws:
            if has_d2d5:
                violations.append(
                    {
                        "id": "AUTOFIX-WS",
                        "summary": f"D2/D5 change outside write_set: {path}",
                        "severity": "blocker" if strict else "warn",
                    }
                )
            continue

        # In write_set: police only narrow UX auto-fix deltas, not full feature implement.
        if not d2d5_only:
            continue

        audited.append(path)
        if _FORBIDDEN_PATH_RE.search(path):
            violations.append(
                {
                    "id": "AUTOFIX-ROUTE",
                    "summary": f"forbidden path class for auto-fix: {path}",
                    "severity": "blocker" if strict else "warn",
                }
            )
        elif not has_d2d5:
            violations.append(
                {
                    "id": "AUTOFIX-PATTERN",
                    "summary": f"diff not limited to D2/D5 patterns: {path}",
                    "severity": "blocker" if strict else "warn",
                }
            )

    blockers = [v for v in violations if v.get("severity") == "blocker"]
    return {
        "ok": not blockers,
        "audited_files": audited,
        "violations": violations,
        "write_set_size": len(write_set),
        "scope_changed_files": len(changed),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo-root", required=True)
    ap.add_argument("--handoff-dir", required=True)
    ap.add_argument("--evidence", default="", help="optional evidence/ux-autofix.json path")
    ap.add_argument("--strict", action="store_true", help="block on any violation (S+ tier)")
    ap.add_argument("--format", choices=("json", "text"), default="json")
    args = ap.parse_args()

    repo_root = Path(args.repo_root).resolve()
    handoff_dir = Path(args.handoff_dir).resolve()
    doc = audit(repo_root=repo_root, handoff_dir=handoff_dir, strict=args.strict)
    doc["schema_version"] = 1
    doc["generated_by"] = "ux-auto-fix-audit.py"

    if args.evidence:
        out = Path(args.evidence)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    if args.format == "text":
        print(f"ux-auto-fix-audit ok={doc['ok']} violations={len(doc['violations'])}")
    else:
        print(json.dumps(doc, ensure_ascii=False, indent=2))
    return 0 if doc["ok"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
