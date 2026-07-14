#!/usr/bin/env python3
"""quality_plane_check — Block silent pass / forged review / illegal UVO skip at complete or audit."""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


def load_json(p: Path) -> dict:
    if not p.is_file():
        return {}
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def resolve_dirs(task_dir: str, state_file: str, project_root: str) -> tuple[Path, Path]:
    script_dir = Path(__file__).resolve().parent
    resolver = script_dir / "resolve-artifact-paths.py"
    if resolver.is_file():
        import subprocess

        args = [sys.executable, str(resolver), "--task-dir", task_dir, "--format", "json"]
        if state_file:
            args.extend(["--state-file", state_file])
        if project_root:
            args.extend(["--project-root", project_root])
        r = subprocess.run(args, capture_output=True, text=True, check=True)
        d = json.loads(r.stdout)
        return Path(d["repo_evidence_dir"]), Path(d["goal_evidence_dir"])
    t = Path(task_dir)
    return t / "evidence", t / "evidence"


def review_frontmatter(text: str) -> dict:
    m = re.match(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return {}
    out = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--task-dir", required=True)
    ap.add_argument("--state-file", default="")
    ap.add_argument("--project-root", default="")
    ap.add_argument("--mode", choices=("complete", "audit"), default="complete")
    ap.add_argument("--format", choices=("json", "text"), default="json")
    args = ap.parse_args()

    repo_ev, goal_ev = resolve_dirs(args.task_dir, args.state_file, args.project_root)
    errors: list[dict] = []

    review_md = repo_ev / "review.md"
    run = goal_ev / "review-run.json"
    unified = goal_ev / "review-unified.json"
    degraded = goal_ev / "review-channel-degraded.json"
    uvo = goal_ev / "verification-oracle.json"

    if review_md.is_file():
        fm = review_frontmatter(review_md.read_text(encoding="utf-8"))
        result = (fm.get("result") or "").lower()
        conf = (fm.get("confidence") or fm.get("separation") or "").lower()
        if result == "pass" and not run.is_file() and not unified.is_file():
            # allow skip only if explicitly skipped classification? else forged
            errors.append({"failure_code": "review_forged", "summary": "review.md pass without review-run/unified"})
        if result == "pass" and degraded.is_file() and conf not in ("degraded", "low", "medium"):
            # degraded evidence exists but review claims full pass without confidence tag
            deg = load_json(degraded)
            if deg.get("separation") == "degraded" and conf != "degraded":
                errors.append(
                    {
                        "failure_code": "review_degraded_as_pass",
                        "summary": "channel degraded but review.md missing confidence: degraded",
                    }
                )

    if args.mode == "complete":
        # UVO should exist for any completed implement path
        impl_handoff = Path(args.task_dir) / "handoff" / "implement.json"
        # also check runtime handoff via resolver parent
        if not uvo.is_file() and impl_handoff.is_file():
            # split mode: uvo in goal_ev
            pass
        st = load_json(Path(args.state_file)) if args.state_file else {}
        stages = st.get("guazi_flow_stages") or {}
        if stages.get("implement", {}).get("gate", {}).get("passed_at") and not uvo.is_file():
            # try artifacts path
            if not list(goal_ev.glob("verification-oracle.json")):
                errors.append(
                    {
                        "failure_code": "uvo_skipped_illegally",
                        "summary": "implement gate passed but verification-oracle.json missing",
                    }
                )

    ok = not errors
    out = {"ok": ok, "plane": "quality", "errors": errors, "silent_pass_forbidden": True}
    if args.format == "text":
        print(f"quality_plane_check ok={ok}")
        for e in errors:
            print(f"  FAIL {e['failure_code']}: {e['summary']}")
    else:
        print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0 if ok else 2


if __name__ == "__main__":
    raise SystemExit(main())
