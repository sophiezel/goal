#!/usr/bin/env python3
"""Resolve implementation diffs and subject hashes for review / stale detection."""
from __future__ import annotations

import hashlib
import os
import re
import subprocess
from typing import Any


def _normalize_write_set_glob(entry: str) -> str:
    """Normalize write_set entry: src/foo/** → src/foo (directory prefix)."""
    w = (entry or "").strip().strip("`").strip()
    if not w:
        return ""
    if w.endswith("/**/"):
        w = w[:-4]
    elif w.endswith("/**"):
        w = w[:-3]
    return w.rstrip("/")


DOCS_GUZI_FLOW_PREFIX = "docs/guazi-flow/"


def git_changed_and_untracked(git_root: str) -> list[str]:
    """Working-tree changed paths (quotepath=false), deduped order-stable."""
    if not git_root or not os.path.isdir(os.path.join(git_root, ".git")):
        return []
    names: list[str] = []
    for args in (
        ["git", "-C", git_root, "-c", "core.quotepath=false", "diff", "--name-only", "HEAD"],
        [
            "git",
            "-C",
            git_root,
            "-c",
            "core.quotepath=false",
            "ls-files",
            "--others",
            "--exclude-standard",
        ],
    ):
        try:
            out = subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL, timeout=30)
            names.extend(line.strip() for line in out.splitlines() if line.strip())
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
            continue
    return list(dict.fromkeys(names))


def implement_scope_changed_files(git_root: str) -> list[str]:
    """Paths for implement post scope checks; skips docs/guazi-flow (matches write_set gate)."""
    return [f for f in git_changed_and_untracked(git_root) if not f.startswith(DOCS_GUZI_FLOW_PREFIX)]


def path_allowed(path: str, allowed: list[str]) -> bool:
    for raw in allowed:
        w = _normalize_write_set_glob(raw)
        if not w:
            continue
        if path == w or path.startswith(w + "/"):
            return True
    return False


def filter_diff_by_write_set(diff_text: str, write_set: list[str]) -> str:
    if not write_set or not diff_text:
        return diff_text
    lines = diff_text.splitlines(keepends=True)
    filtered: list[str] = []
    include = False
    current_path = ""
    for line in lines:
        if line.startswith("diff --git "):
            parts = line.split()
            current_path = parts[-1].lstrip("b/") if len(parts) >= 4 else ""
            include = path_allowed(current_path, write_set) if current_path else False
        elif line.startswith("--- new file:"):
            m = re.search(r"--- new file:\s+(\S+)", line)
            current_path = m.group(1) if m else ""
            include = path_allowed(current_path, write_set) if current_path else False
        if include:
            filtered.append(line)
    return "".join(filtered)


def _git_diff(git_root: str, *extra: str) -> str:
    args = ["git", "-C", git_root, "-c", "core.quotepath=false", "diff", *extra]
    return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL)


def _untracked_in_write_set(git_root: str, write_set: list[str]) -> str:
    out = ""
    try:
        untracked = subprocess.check_output(
            ["git", "-C", git_root, "-c", "core.quotepath=false", "ls-files", "--others", "--exclude-standard"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).splitlines()
    except (OSError, subprocess.CalledProcessError):
        return out
    for f in untracked:
        if write_set and not path_allowed(f, write_set):
            continue
        fp = os.path.join(git_root, f)
        if os.path.isfile(fp):
            try:
                content = open(fp, encoding="utf-8", errors="replace").read()
                out += f"\n--- new file: {f} ---\n{content}\n"
            except OSError:
                pass
    return out


def git_diff_working_tree(git_root: str, write_set: list[str] | None = None) -> str:
    if not git_root or not os.path.isdir(os.path.join(git_root, ".git")):
        return ""
    try:
        diff_text = _git_diff(git_root, "HEAD")
        diff_text += _untracked_in_write_set(git_root, write_set or [])
        return diff_text
    except (OSError, subprocess.CalledProcessError):
        return ""


def git_diff_reference(git_root: str, ref_branch: str, ref_paths: list[str] | None = None) -> str:
    args: list[str] = [ref_branch, "--"]
    if ref_paths:
        args.extend(ref_paths)
    return _git_diff(git_root, *args)


def src_write_set(write_set: list[str] | None) -> list[str]:
    """Narrow write_set to src/** paths for code-only review packets."""
    if not write_set:
        return ["src/"]
    src_ws: list[str] = []
    for raw in write_set:
        w = (raw or "").strip().rstrip("/")
        if not w:
            continue
        norm = w.replace("/**", "").rstrip("/")
        if norm == "src" or norm.startswith("src/"):
            src_ws.append(w if w.startswith("src") else norm)
    return src_ws or ["src/"]


def filter_diff_to_src(diff_text: str) -> str:
    return filter_diff_by_write_set(diff_text, ["src/"])


def resolve_code_subject_diff(
    git_root: str,
    plan: dict[str, Any],
    write_set: list[str],
    max_bytes: int = 80000,
) -> tuple[str, str, bool]:
    """Return src/**-only diff for L2 review (excludes docs/guazi-flow noise)."""
    src_ws = src_write_set(write_set)
    diff_text, inner_source, truncated = resolve_implementation_diff(
        git_root, plan, src_ws, max_bytes=max_bytes
    )
    diff_text = filter_diff_to_src(diff_text)
    if diff_text.strip():
        return diff_text, "code_subject_hash", truncated
    return diff_text, inner_source if inner_source != "reference_branch" else "code_subject_hash", truncated


def resolve_implementation_diff(
    git_root: str,
    plan: dict[str, Any],
    write_set: list[str],
    max_bytes: int = 80000,
) -> tuple[str, str, bool]:
    """Return (diff_text, diff_source, truncated)."""
    ref_branch = plan.get("reference_branch") or plan.get("reference_impl_branch") or ""
    ref_paths = plan.get("reference_impl_paths") or []
    diff_text = ""
    diff_source = "working_tree"
    truncated = False

    if git_root and ref_branch:
        try:
            ref_diff = git_diff_reference(git_root, ref_branch, ref_paths if ref_paths else None)
            if ref_paths:
                diff_text = ref_diff
            elif write_set:
                diff_text = filter_diff_by_write_set(ref_diff, write_set)
            else:
                diff_text = ref_diff
            if diff_text.strip():
                diff_source = "reference_branch"
        except (OSError, subprocess.CalledProcessError):
            diff_text = ""

    if not diff_text.strip() and git_root:
        diff_text = git_diff_working_tree(git_root, write_set)
        if write_set:
            diff_text = filter_diff_by_write_set(diff_text, write_set)
        diff_source = "working_tree"

    if len(diff_text.encode("utf-8")) > max_bytes:
        diff_text = diff_text[:max_bytes] + "\n...[diff truncated]..."
        truncated = True

    return diff_text, diff_source, truncated


def src_files_in_diff(diff_text: str) -> list[str]:
    files: set[str] = set()
    for line in diff_text.splitlines():
        if line.startswith("diff --git "):
            parts = line.split()
            if len(parts) >= 4:
                p = parts[-1].lstrip("b/")
                if p.startswith("src/"):
                    files.add(p)
        elif line.startswith("--- new file:"):
            m = re.search(r"--- new file:\s+(\S+)", line)
            if m and m.group(1).startswith("src/"):
                files.add(m.group(1))
    return sorted(files)


def _hash_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def _src_only_diff_text(git_root: str, write_set: list[str], ref_branch: str = "") -> str:
    plan_stub = {"reference_branch": ref_branch} if ref_branch else {}
    diff_text, _, _ = resolve_implementation_diff(git_root, plan_stub, write_set, max_bytes=10_000_000)
    lines = diff_text.splitlines(keepends=True)
    filtered: list[str] = []
    include = False
    for line in lines:
        if line.startswith("diff --git "):
            parts = line.split()
            current = parts[-1].lstrip("b/") if len(parts) >= 4 else ""
            include = current.startswith("src/")
        elif line.startswith("--- new file:"):
            m = re.search(r"--- new file:\s+(\S+)", line)
            current = m.group(1) if m else ""
            include = current.startswith("src/")
        if include:
            filtered.append(line)
    return "".join(filtered)


def code_subject_hash(repo_root: str, write_set: list[str] | None = None, ref_branch: str = "") -> str:
    """Hash src/** implementation diff only — stable across evidence/handoff writes."""
    if not repo_root or not os.path.isdir(os.path.join(repo_root, ".git")):
        return "unknown"
    ws = write_set or []
    try:
        text = _src_only_diff_text(repo_root, ws, ref_branch)
        if text.strip():
            return _hash_text(text)
        # fallback: staged+untracked src paths in write_set
        names: list[str] = []
        for args in (
            ["git", "-C", repo_root, "-c", "core.quotepath=false", "diff", "--name-only", "HEAD", "--", "src/"],
            ["git", "-C", repo_root, "-c", "core.quotepath=false", "ls-files", "--others", "--exclude-standard", "--", "src/"],
        ):
            r = subprocess.run(args, capture_output=True, text=True, timeout=30)
            if r.returncode == 0 and r.stdout.strip():
                names.extend(line.strip() for line in r.stdout.splitlines() if line.strip())
        if ws:
            names = [n for n in names if path_allowed(n, ws)]
        # Include file contents so untracked/new write_set files change the hash
        # (name-only hash caused noop_fix after creating new pages).
        chunks: list[str] = []
        for n in sorted(set(names)):
            fp = os.path.join(repo_root, n)
            try:
                with open(fp, "rb") as fh:
                    digest = hashlib.sha256(fh.read()).hexdigest()[:16]
                chunks.append(f"{n}:{digest}")
            except OSError:
                chunks.append(f"{n}:missing")
        if chunks:
            return _hash_text("\n".join(chunks))
        return _hash_text("\n".join(sorted(set(names))))
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"


def artifact_diff_hash(repo_root: str, task_dir: str) -> str:
    """Hash docs/guazi-flow task artifacts (handoff + evidence), not src."""
    if not repo_root:
        return "unknown"
    rel_task = os.path.relpath(task_dir, repo_root).replace("\\", "/") if task_dir.startswith(repo_root) else ""
    prefix = rel_task if rel_task and not rel_task.startswith("..") else ""
    parts: list[str] = []
    try:
        if prefix:
            diff = subprocess.check_output(
                ["git", "-C", repo_root, "-c", "core.quotepath=false", "diff", "HEAD", "--", prefix],
                text=True,
                stderr=subprocess.DEVNULL,
                timeout=30,
            )
            parts.append(diff)
        for sub in ("handoff", "evidence"):
            d = os.path.join(task_dir, sub)
            if not os.path.isdir(d):
                continue
            for root, _, files in os.walk(d):
                for name in sorted(files):
                    fp = os.path.join(root, name)
                    rel = os.path.relpath(fp, task_dir).replace("\\", "/")
                    try:
                        parts.append(f"--- {rel} ---\n{open(fp, encoding='utf-8', errors='replace').read()}\n")
                    except OSError:
                        pass
        return _hash_text("".join(parts)) if parts else "empty"
    except (OSError, subprocess.TimeoutExpired, subprocess.CalledProcessError):
        return "unknown"


def changed_files_for_plan(git_root: str, plan: dict[str, Any], write_set: list[str]) -> list[str]:
    ref_branch = plan.get("reference_branch") or plan.get("reference_impl_branch") or ""
    names: list[str] = []
    if git_root and ref_branch:
        try:
            names = subprocess.check_output(
                ["git", "-C", git_root, "-c", "core.quotepath=false", "diff", "--name-only", ref_branch],
                text=True,
                stderr=subprocess.DEVNULL,
            ).splitlines()
        except (OSError, subprocess.CalledProcessError):
            names = []
    if not names and git_root:
        try:
            names = subprocess.check_output(
                ["git", "-C", git_root, "-c", "core.quotepath=false", "diff", "--name-only", "HEAD"],
                text=True,
                stderr=subprocess.DEVNULL,
            ).splitlines()
            unt = subprocess.check_output(
                ["git", "-C", git_root, "-c", "core.quotepath=false", "ls-files", "--others", "--exclude-standard"],
                text=True,
                stderr=subprocess.DEVNULL,
            ).splitlines()
            names = names + unt
        except (OSError, subprocess.CalledProcessError):
            pass
    names = [n.strip() for n in names if n.strip()]
    if write_set:
        names = [f for f in names if path_allowed(f, write_set)]
    return list(dict.fromkeys(names))
