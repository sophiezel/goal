#!/usr/bin/env python3
"""resolve-artifact-paths — Tier-G (repo) vs Tier-R (goal-state) path resolver.

Usage:
  resolve-artifact-paths.py --task-dir <path> [--state-file PATH] [--project-root PATH] [--format json|shell]
  resolve-artifact-paths.py --purge-repo-tier-r --task-dir <path> [--state-file PATH]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

GOAL_STATE_HOME = Path(os.environ.get("GOAL_STATE_HOME", os.path.expanduser("~/.goal-state")))

TIER_R_EVIDENCE_FILES = (
    "verification-oracle.json",
    "runtime-smoke.md",
    "review-unified.json",
    "review-run.json",
    "review-fix-input.json",
    "review-transcript.md",
    "review-packet.json",
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


def task_rel_path(repo_task_dir: Path, project_root: Path | None) -> str:
    if project_root is None:
        project_root = git_root(repo_task_dir)
    if project_root is None:
        return ""
    try:
        return str(repo_task_dir.resolve().relative_to(project_root.resolve())).replace("\\", "/")
    except ValueError:
        return ""


def is_guazi_flow_task_dir(repo_task_dir: Path, project_root: Path | None) -> bool:
    rel = task_rel_path(repo_task_dir, project_root)
    if not rel:
        return False
    parts = rel.split("/")
    return len(parts) >= 2 and parts[0] == "docs" and parts[1] == "guazi-flow"


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
    rel_str = task_rel_path(task_dir, project_root)
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
    if goal_ev.is_dir() and any(goal_ev.glob("*-gate-fix-input.json")):
        return True
    return False


def purge_repo_tier_r(repo_task_dir: Path) -> list[str]:
    """Remove Tier-R artifacts from repo task dir; preserve Tier-G evidence."""
    purged: list[str] = []
    repo = repo_task_dir.resolve()
    handoff = repo / "handoff"
    if handoff.is_dir():
        shutil.rmtree(handoff)
        purged.append("handoff/")
    evidence = repo / "evidence"
    if evidence.is_dir():
        for name in TIER_R_EVIDENCE_FILES:
            p = evidence / name
            if p.is_file():
                p.unlink()
                purged.append(f"evidence/{name}")
        for legacy in ("review-goal.json", "review-gf.json"):
            p = evidence / legacy
            if p.is_file():
                p.unlink()
                purged.append(f"evidence/{legacy}")
        for p in list(evidence.glob("*-gate-fix-input.json")):
            p.unlink()
            purged.append(f"evidence/{p.name}")
    return purged


def sync_repo_tier_r_to_runtime(repo_task_dir: Path, paths: dict) -> list[str]:
    """Move repo Tier-R into runtime (overwrite runtime copies), then purge repo."""
    moved: list[str] = []
    repo = repo_task_dir.resolve()
    runtime = Path(paths["runtime_root"])
    handoff_src = repo / "handoff"
    handoff_dest = runtime / "handoff"
    evidence_src = repo / "evidence"
    evidence_dest = runtime / "evidence"

    runtime.mkdir(parents=True, exist_ok=True)
    if handoff_src.is_dir():
        handoff_dest.mkdir(parents=True, exist_ok=True)
        for item in sorted(handoff_src.iterdir()):
            target = handoff_dest / item.name
            if target.exists():
                if target.is_dir():
                    shutil.rmtree(target)
                else:
                    target.unlink()
            shutil.move(str(item), str(target))
            moved.append(f"handoff/{item.name}")
        if not any(handoff_src.iterdir()):
            handoff_src.rmdir()
            moved.append("handoff/ (removed empty dir)")

    if evidence_src.is_dir():
        evidence_dest.mkdir(parents=True, exist_ok=True)
        for name in TIER_R_EVIDENCE_FILES:
            src = evidence_src / name
            if src.is_file():
                dest = evidence_dest / name
                if dest.exists():
                    dest.unlink()
                shutil.move(str(src), str(dest))
                moved.append(f"evidence/{name}")
        for p in list(evidence_src.glob("*-gate-fix-input.json")):
            dest = evidence_dest / p.name
            if dest.exists():
                dest.unlink()
            shutil.move(str(p), str(dest))
            moved.append(f"evidence/{p.name}")

    return moved


def default_mode(
    env_mode: str,
    layout: dict,
    state: dict,
    repo_task_dir: Path,
    project_root: Path | None,
) -> str:
    if env_mode:
        return env_mode
    if layout.get("mode"):
        return str(layout["mode"])
    if state.get("guazi_flow_task"):
        return "split"
    if is_guazi_flow_task_dir(repo_task_dir, project_root):
        return "split"
    return "repo_full"


def ensure_artifact_layout(paths: dict) -> dict:
    """Persist artifact_layout to state.json; sync/migrate Tier-R; purge repo leaks."""
    sf_s = paths.get("state_file") or ""
    if not sf_s:
        return {"ensured": False, "reason": "no_state_file"}

    sf = Path(sf_s)
    if not sf.is_file():
        return {"ensured": False, "reason": "state_missing"}

    state = json.loads(sf.read_text(encoding="utf-8"))
    layout = dict(state.get("artifact_layout") or {})
    changed = False
    migrated = False
    purged: list[str] = []
    synced: list[str] = []

    if layout.get("mode") != paths["mode"]:
        layout["mode"] = paths["mode"]
        changed = True
    if layout.get("repo_task_dir") != paths["repo_task_dir"]:
        layout["repo_task_dir"] = paths["repo_task_dir"]
        changed = True
    if layout.get("runtime_root") != paths["runtime_root"]:
        layout["runtime_root"] = paths["runtime_root"]
        changed = True

    repo = Path(paths["repo_task_dir"])
    if paths["mode"] == "split":
        if repo_has_tier_r(repo):
            synced = sync_repo_tier_r_to_runtime(repo, paths)
            if synced:
                migrated = True
                if not layout.get("migrated_at"):
                    layout["migrated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                    changed = True
            paths = resolve(
                paths["repo_task_dir"],
                state_file=str(sf),
                project_root=paths.get("project_root") or None,
            )

        purged = purge_repo_tier_r(repo)
        if purged and not layout.get("migrated_at"):
            layout["migrated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            changed = True

    if changed:
        state["artifact_layout"] = layout
        sf.write_text(json.dumps(state, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    runtime = Path(paths["runtime_root"])
    (runtime / "handoff").mkdir(parents=True, exist_ok=True)
    (runtime / "evidence").mkdir(parents=True, exist_ok=True)

    return {
        "ensured": True,
        "mode": paths["mode"],
        "runtime_root": paths["runtime_root"],
        "migrated": migrated,
        "synced": synced,
        "purged": purged,
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

    mode = default_mode(env_mode, layout, state, repo_task_dir, proj)
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
        help="Write artifact_layout to state.json, sync/migrate Tier-R, purge repo leaks",
    )
    ap.add_argument(
        "--purge-repo-tier-r",
        action="store_true",
        help="Remove Tier-R files from repo task dir (split hygiene); prints JSON report",
    )
    args = ap.parse_args()

    paths = resolve(
        args.task_dir,
        state_file=args.state_file or None,
        project_root=args.project_root or None,
    )

    if args.purge_repo_tier_r:
        if paths["mode"] != "split":
            print(json.dumps({"purged": [], "skipped": True, "reason": "not split mode"}, indent=2))
            return
        purged = purge_repo_tier_r(Path(paths["repo_task_dir"]))
        print(json.dumps({"purged": purged, "repo_task_dir": paths["repo_task_dir"]}, indent=2, ensure_ascii=False))
        return

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
