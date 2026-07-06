#!/usr/bin/env python3
"""resolve-artifact-paths — Tier-G (repo) vs Tier-R (goal-state) path resolver.

Usage:
  resolve-artifact-paths.py --task-dir <path> [--state-file PATH] [--project-root PATH] [--format json|shell]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

GOAL_STATE_HOME = Path(os.environ.get("GOAL_STATE_HOME", os.path.expanduser("~/.goal-state")))

TIER_R_EVIDENCE_FILES = (
    "runtime-smoke.md",
    "review-goal.json",
    "review-gf.json",
    "review-run.json",
    "review-fix-input.json",
    "review-transcript.md",
)


def git_root(start: Path) -> Path | None:
    try:
        r = subprocess.run(
            ["git", "-C", str(start), "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if r.returncode == 0 and r.stdout.strip():
            return Path(r.stdout.strip()).resolve()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return None


def project_id(project_root: Path) -> str:
    return hashlib.sha256(str(project_root.resolve()).encode()).hexdigest()[:12]


def find_state_file(task_dir: Path, project_root: Path | None) -> Path | None:
    task_dir = task_dir.resolve()
    if project_root is None:
        project_root = git_root(task_dir)
    if project_root is None:
        return None
    pid = project_id(project_root)
    base = GOAL_STATE_HOME / "projects" / pid
    if not base.is_dir():
        return None
    task_name = task_dir.name
    try:
        rel = task_dir.relative_to(project_root.resolve())
        rel_str = str(rel).replace("\\", "/")
    except ValueError:
        rel_str = ""
    candidates: list[Path] = []
    for sf in base.rglob("state.json"):
        try:
            st = json.loads(sf.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        gft = (st.get("guazi_flow_task") or "").strip().rstrip("/")
        if gft and rel_str and (gft == rel_str or gft.endswith("/" + task_name)):
            candidates.append(sf)
        elif sf.parent.name == task_name:
            candidates.append(sf)
    if not candidates:
        return None
    candidates.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return candidates[0]


def default_runtime_root(state_file: Path | None, repo_task_dir: Path) -> Path:
    if state_file and state_file.is_file():
        return state_file.parent / "artifacts"
    return GOAL_STATE_HOME / "runtime" / repo_task_dir.name


def repo_has_tier_r(repo_task_dir: Path) -> bool:
    handoff = repo_task_dir / "handoff"
    if handoff.is_dir() and any(handoff.glob("*.json")):
        return True
    evidence = repo_task_dir / "evidence"
    for name in TIER_R_EVIDENCE_FILES:
        if (evidence / name).is_file():
            return True
    if evidence.is_dir() and any(evidence.glob("*-gate-fix-input.json")):
        return True
    return False


def runtime_has_tier_r(paths: dict) -> bool:
    handoff = Path(paths["handoff_dir"])
    if handoff.is_dir() and any(handoff.glob("*.json")):
        return True
    goal_ev = Path(paths["goal_evidence_dir"])
    for name in TIER_R_EVIDENCE_FILES:
        if (goal_ev / name).is_file():
            return True
    return False


def inject_gitignore(project_root: str) -> None:
    if not project_root:
        return
    script_dir = Path(__file__).resolve().parent
    candidates = [
        script_dir.parent.parent / "guazi-flow-goal" / "scripts" / "inject-docs-gitignore.sh",
        GOAL_STATE_HOME / "scripts" / "inject-docs-gitignore.sh",
        Path(os.environ.get("GOAL_PIPELINE_REPO", str(Path.home() / ".goal-pipeline-repo")))
        / "guazi-flow-goal"
        / "scripts"
        / "inject-docs-gitignore.sh",
    ]
    for inj in candidates:
        if inj.is_file():
            subprocess.run(
                ["bash", str(inj), "--project-root", project_root, "--mode", "split"],
                check=False,
                capture_output=True,
                text=True,
            )
            return


def ensure_artifact_layout(paths: dict) -> dict:
    """Persist artifact_layout to state.json; auto-migrate Tier-R from repo once."""
    sf_s = paths.get("state_file") or ""
    if not sf_s:
        return {"ensured": False, "reason": "no_state_file"}

    sf = Path(sf_s)
    if not sf.is_file():
        return {"ensured": False, "reason": "state_missing"}

    state = json.loads(sf.read_text(encoding="utf-8"))
    layout = dict(state.get("artifact_layout") or {})
    changed = False

    if layout.get("mode") != paths["mode"]:
        layout["mode"] = paths["mode"]
        changed = True
    if layout.get("repo_task_dir") != paths["repo_task_dir"]:
        layout["repo_task_dir"] = paths["repo_task_dir"]
        changed = True
    if layout.get("runtime_root") != paths["runtime_root"]:
        layout["runtime_root"] = paths["runtime_root"]
        changed = True

    migrated = False
    repo = Path(paths["repo_task_dir"])
    if paths["mode"] == "split" and not layout.get("migrated_at"):
        if repo_has_tier_r(repo) and not runtime_has_tier_r(paths):
            migrate_py = Path(__file__).resolve().parent / "migrate-artifacts.py"
            alt = GOAL_STATE_HOME / "scripts" / "migrate-artifacts.py"
            script = migrate_py if migrate_py.is_file() else alt
            if script.is_file():
                subprocess.run(
                    [
                        sys.executable,
                        str(script),
                        "--task-dir",
                        paths["repo_task_dir"],
                        "--state-file",
                        str(sf),
                        *(["--project-root", paths["project_root"]] if paths.get("project_root") else []),
                    ],
                    check=True,
                )
                migrated = True
                layout["migrated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                changed = True
                paths = resolve(paths["repo_task_dir"], state_file=str(sf), project_root=paths.get("project_root") or None)

    if changed:
        state["artifact_layout"] = layout
        sf.write_text(json.dumps(state, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    if paths["mode"] == "split":
        inject_gitignore(paths.get("project_root") or state.get("project_root") or "")

    runtime = Path(paths["runtime_root"])
    (runtime / "handoff").mkdir(parents=True, exist_ok=True)
    (runtime / "evidence").mkdir(parents=True, exist_ok=True)

    return {
        "ensured": True,
        "mode": paths["mode"],
        "runtime_root": paths["runtime_root"],
        "migrated": migrated,
        "state_updated": changed,
    }


def resolve(
    task_dir: str,
    state_file: str | None = None,
    project_root: str | None = None,
) -> dict:
    repo_task_dir = Path(task_dir).resolve()
    if not repo_task_dir.is_dir():
        raise SystemExit(f"resolve-artifact-paths: task dir not found: {repo_task_dir}")

    proj = Path(project_root).resolve() if project_root else git_root(repo_task_dir)
    sf: Path | None = Path(state_file).resolve() if state_file else None
    if sf is None:
        sf = find_state_file(repo_task_dir, proj)

    env_mode = os.environ.get("GOAL_ARTIFACT_MODE", "").strip()
    state: dict = {}
    layout: dict = {}
    if sf and sf.is_file():
        try:
            state = json.loads(sf.read_text(encoding="utf-8"))
            layout = state.get("artifact_layout") or {}
        except (json.JSONDecodeError, OSError):
            pass

    mode = env_mode or layout.get("mode") or ("split" if state.get("guazi_flow_task") else "repo_full")
    if mode not in ("split", "repo_full"):
        mode = "repo_full"

    runtime_root_s = layout.get("runtime_root") or ""
    if mode == "split":
        runtime_root = Path(runtime_root_s).expanduser().resolve() if runtime_root_s else default_runtime_root(sf, repo_task_dir)
        handoff_dir = runtime_root / "handoff"
        goal_evidence_dir = runtime_root / "evidence"
        repo_evidence_dir = repo_task_dir / "evidence"
    else:
        runtime_root = repo_task_dir
        handoff_dir = repo_task_dir / "handoff"
        goal_evidence_dir = repo_task_dir / "evidence"
        repo_evidence_dir = goal_evidence_dir

    return {
        "mode": mode,
        "repo_task_dir": str(repo_task_dir),
        "runtime_root": str(runtime_root),
        "handoff_dir": str(handoff_dir),
        "repo_evidence_dir": str(repo_evidence_dir),
        "goal_evidence_dir": str(goal_evidence_dir),
        "state_file": str(sf) if sf else "",
        "project_root": str(proj) if proj else "",
    }


def sh_quote(value: str) -> str:
    return "'" + str(value).replace("'", "'\"'\"'") + "'"


def shell_export(paths: dict) -> str:
    exports = {
        "ARTIFACT_MODE": paths["mode"],
        "REPO_TASK_DIR": paths["repo_task_dir"],
        "RUNTIME_ROOT": paths["runtime_root"],
        "HANDOFF_DIR": paths["handoff_dir"],
        "REPO_EVIDENCE_DIR": paths["repo_evidence_dir"],
        "GOAL_EVIDENCE_DIR": paths["goal_evidence_dir"],
        "GOAL_STATE_FILE": paths.get("state_file", ""),
    }
    lines = [f"export {k}={sh_quote(v)}" for k, v in exports.items()]
    # Legacy aliases
    lines.append(f"export TASK_DIR={sh_quote(paths['repo_task_dir'])}")
    lines.append(f"export EVIDENCE_DIR={sh_quote(paths['repo_evidence_dir'])}")
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser(description="Resolve Tier-G / Tier-R artifact paths")
    ap.add_argument("--task-dir", required=True)
    ap.add_argument("--state-file", default="")
    ap.add_argument("--project-root", default="")
    ap.add_argument("--format", choices=("json", "shell", "ensure-report"), default="json")
    ap.add_argument(
        "--ensure-state",
        action="store_true",
        help="Write artifact_layout to state.json, auto-migrate Tier-R once, inject gitignore",
    )
    args = ap.parse_args()

    paths = resolve(
        args.task_dir,
        state_file=args.state_file or None,
        project_root=args.project_root or None,
    )

    ensure_report = None
    if args.ensure_state:
        ensure_report = ensure_artifact_layout(paths)
        paths = resolve(
            args.task_dir,
            state_file=args.state_file or None,
            project_root=args.project_root or None,
        )

    if args.format == "shell":
        print(shell_export(paths))
    elif args.format == "ensure-report":
        print(json.dumps({"paths": paths, "ensure": ensure_report or {}}, indent=2, ensure_ascii=False))
    else:
        out = dict(paths)
        if ensure_report:
            out["ensure"] = ensure_report
        print(json.dumps(out, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
