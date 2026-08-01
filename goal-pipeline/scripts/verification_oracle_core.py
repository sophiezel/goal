#!/usr/bin/env python3
"""Unified Verification Oracle (UVO) core — single L1 gate for test+lint+build."""
from __future__ import annotations

import fnmatch
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from typing import Any


SMOKE_REQUIRED_PATTERNS = (
    "src/App.tsx",
    "src/pages/index.ts",
    "config-overrides.js",
    "package.json",
    "**/routes/**",
    "**/router/**",
)

# G2: default hub sources are not findRelatedTests seeds (hub tests e.g. App.test.tsx still via colocation/write_set).
HUB_FIND_RELATED_SEED_PATHS = (
    "src/App.tsx",
    "src/pages/index.ts",
)

_FAIL_TEST_LINE_RE = re.compile(
    r"^\s*FAIL\s+((?:src|test)/[^\s]+\.(?:test|spec)\.(?:tsx?|jsx?))\s*$",
    re.M,
)
_FAIL_TEST_AT_RE = re.compile(
    r"\(((?:src|test)/[^\s]+\.(?:test|spec)\.(?:tsx?|jsx?)):\d+",
)

CODE_EXTENSIONS = (".ts", ".tsx", ".js", ".jsx", ".vue", ".scss", ".css")


def _script_dir() -> str:
    return os.path.dirname(os.path.abspath(__file__))


def _load_module(name: str, path: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def resolve_handoff_dir(task_dir: str) -> str:
    sd = _script_dir()
    if sd not in sys.path:
        sys.path.insert(0, sd)
    from handoff_path_resolver import resolve_handoff_dir as _ssot_handoff_dir

    state_file = os.environ.get("GOAL_STATE_FILE", "")
    project_root = os.environ.get("GOAL_REPO_ROOT", "")
    return _ssot_handoff_dir(task_dir, state_file=state_file, project_root=project_root)


def load_plan_handoff(task_dir: str) -> dict[str, Any]:
    handoff_dir = resolve_handoff_dir(task_dir)
    plan_path = os.path.join(handoff_dir, "plan.json")
    if os.path.isfile(plan_path):
        return json.load(open(plan_path, encoding="utf-8"))
    return {}


def git_head(repo_root: str) -> str:
    try:
        r = subprocess.run(
            ["git", "-C", repo_root, "rev-parse", "--short=16", "HEAD"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if r.returncode == 0:
            return r.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        pass
    return "unknown"


def git_changed_files(repo_root: str) -> list[str]:
    if not repo_root or not os.path.isdir(os.path.join(repo_root, ".git")):
        return []
    files: list[str] = []
    for args in (
        ["git", "-C", repo_root, "-c", "core.quotepath=false", "diff", "--name-only", "HEAD"],
        ["git", "-C", repo_root, "-c", "core.quotepath=false", "ls-files", "--others", "--exclude-standard"],
    ):
        try:
            r = subprocess.run(args, capture_output=True, text=True, timeout=30)
            if r.returncode == 0 and r.stdout.strip():
                files.extend(line.strip() for line in r.stdout.splitlines() if line.strip())
        except (OSError, subprocess.TimeoutExpired):
            continue
    return list(dict.fromkeys(files))


def diff_hash(repo_root: str) -> str:
    """Hash full working tree diff including untracked (legacy / artifact tracking)."""
    if not repo_root or not os.path.isdir(os.path.join(repo_root, ".git")):
        return "unknown"
    try:
        diff = subprocess.check_output(
            ["git", "-C", repo_root, "-c", "core.quotepath=false", "diff", "HEAD"],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=30,
        )
        untracked = subprocess.check_output(
            ["git", "-C", repo_root, "-c", "core.quotepath=false", "ls-files", "--others", "--exclude-standard"],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=30,
        ).splitlines()
        for f in untracked:
            fp = os.path.join(repo_root, f)
            if os.path.isfile(fp):
                try:
                    diff += f"\n--- new file: {f} ---\n{open(fp, encoding='utf-8', errors='replace').read()}\n"
                except OSError:
                    pass
        return hashlib.sha256(diff.encode("utf-8")).hexdigest()[:16]
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"


def _load_diff_resolver():
    path = os.path.join(_script_dir(), "diff_resolver.py")
    return _load_module("diff_resolver", path)


def code_subject_hash(repo_root: str, write_set: list[str] | None = None, ref_branch: str = "") -> str:
    try:
        dr = _load_diff_resolver()
        return dr.code_subject_hash(repo_root, write_set, ref_branch)
    except Exception:
        return diff_hash(repo_root)


def artifact_diff_hash(repo_root: str, task_dir: str) -> str:
    try:
        dr = _load_diff_resolver()
        return dr.artifact_diff_hash(repo_root, task_dir)
    except Exception:
        return "unknown"


def _path_in_write_set_tree(path: str, write_set: list[str]) -> bool:
    normalized = path.replace("\\", "/")
    if not write_set:
        return False
    for w in write_set:
        prefix = w.rstrip("/").rstrip("/**")
        if normalized == prefix or normalized.startswith(prefix + "/"):
            return True
    return False


def _related_union_mode() -> str:
    """G6: default narrow write_set closure; legacy_wide opt-in via env."""
    raw = (os.environ.get("GOAL_UVO_RELATED_UNION_MODE") or "write_set_closure").strip().lower()
    if raw in ("legacy_wide", "wide", "legacy"):
        return "legacy_wide"
    return "write_set_closure"


def _hub_expansion_enabled(plan: dict[str, Any] | None = None, task_dir: str = "") -> bool:
    if os.environ.get("GOAL_UVO_HUB_EXPANSION", "0") == "1":
        return True
    verification = (plan or {}).get("verification") or {}
    if verification.get("uvo_hub_expansion") is True:
        return True
    index_path = os.path.join(task_dir, "index.md") if task_dir else ""
    if index_path and os.path.isfile(index_path):
        text = open(index_path, encoding="utf-8").read()
        if re.search(r"uvo_hub_expansion\s*:\s*true", text, re.I):
            return True
    return False


def _is_hub_find_related_seed(path: str, plan: dict[str, Any] | None = None, task_dir: str = "") -> bool:
    if _hub_expansion_enabled(plan, task_dir):
        return False
    normalized = path.replace("\\", "/")
    return normalized in HUB_FIND_RELATED_SEED_PATHS


def _matches_patterns(path: str, patterns: tuple[str, ...] | list[str]) -> bool:
    normalized = path.replace("\\", "/")
    for pattern in patterns:
        if fnmatch.fnmatch(normalized, pattern):
            return True
        if pattern.endswith("/**"):
            prefix = pattern[:-3].rstrip("/")
            if normalized.startswith(prefix + "/") or normalized == prefix:
                return True
    return False


def smoke_required(changed_files: list[str], write_set: list[str], tier: str) -> bool:
    if tier == "strict":
        return True
    candidates = list(changed_files) + list(write_set)
    return any(_matches_patterns(p, SMOKE_REQUIRED_PATTERNS) for p in candidates)


def _write_set_from_plan(plan: dict[str, Any], task_dir: str) -> list[str]:
    ws = plan.get("write_set") or []
    if ws:
        return [str(p) for p in ws]
    index_path = os.path.join(task_dir, "index.md")
    if not os.path.isfile(index_path):
        return []
    text = open(index_path, encoding="utf-8").read()
    m = re.search(
        r"(?:##\s*(?:write_set|写集|范围与写集)|write_set\s*[:：])\s*\n([\s\S]*?)(?:\n##|\Z)",
        text,
        re.I,
    )
    if not m:
        return []
    paths: list[str] = []
    for line in m.group(1).splitlines():
        s = line.strip().strip("- ").strip("`").strip()
        if s.startswith("src/") or s.startswith("docs/"):
            paths.append(s)
    return paths


def _changed_files_for_related_union(changed_files: list[str], write_set: list[str]) -> list[str]:
    """G3: in write_set_closure mode, seeds only from write_set ∩ changed (scope still uses full diff)."""
    if _related_union_mode() == "legacy_wide" or not write_set:
        return list(changed_files)
    return [f for f in changed_files if _path_in_write_set_tree(f, write_set)]


def _related_source_files(
    changed_files: list[str],
    write_set: list[str],
    *,
    plan: dict[str, Any] | None = None,
    task_dir: str = "",
) -> list[str]:
    allowed = write_set or changed_files
    out: list[str] = []
    for f in changed_files:
        if not any(
            f == w.rstrip("/") or f.startswith(w.rstrip("/").rstrip("/**") + "/")
            for w in allowed
        ):
            continue
        if _is_hub_find_related_seed(f, plan, task_dir):
            continue
        if f.endswith(CODE_EXTENSIONS) and not f.endswith((".test.ts", ".test.tsx", ".test.js", ".spec.ts")):
            out.append(f)
    return out


def _find_related_test_targets(
    changed_files: list[str],
    write_set: list[str],
    repo_root: str,
    plan: dict[str, Any] | None = None,
    task_dir: str = "",
) -> tuple[list[str], list[str]]:
    """G3: related_source(write_set∩changed) + colocated_tests(write_set); split seeds vs direct test paths."""
    effective = _changed_files_for_related_union(changed_files, write_set)
    related_seeds = _related_source_files(
        effective, write_set, plan=plan, task_dir=task_dir
    )
    direct_tests = _test_files_for_write_set(effective, repo_root, write_set)
    if _related_union_mode() == "write_set_closure":
        return related_seeds, direct_tests
    merged = list(dict.fromkeys(related_seeds + direct_tests))
    return merged, []


def _compose_find_related_test_cmd(repo_root: str, related_seeds: list[str], direct_tests: list[str]) -> str | None:
    parts: list[str] = []
    if related_seeds:
        parts.append("--findRelatedTests")
        parts.extend(f'"{s}"' for s in related_seeds[:40])
    for t in direct_tests[:40]:
        if t not in related_seeds:
            parts.append(f'"{t}"')
    if not parts:
        return None
    if os.path.isfile(os.path.join(repo_root, "yarn.lock")):
        return f"CI=true yarn test {' '.join(parts)} --watchAll=false"
    return f"CI=true npm test -- {' '.join(parts)} --watchAll=false"


def _colocated_test_paths_for_source(repo_root: str, source_rel: str) -> list[str]:
    """G1: same-directory test pairing only (no repo-wide basename scan)."""
    base = os.path.splitext(os.path.basename(source_rel))[0]
    if base == "index" or len(base) <= 2:
        return []
    dir_rel = os.path.dirname(source_rel).replace("\\", "/")
    dir_abs = os.path.join(repo_root, dir_rel)
    if not os.path.isdir(dir_abs):
        return []
    found: list[str] = []
    for name in os.listdir(dir_abs):
        if not re.search(r"\.(test|spec)\.(tsx?|jsx?)$", name):
            continue
        stem = re.sub(r"\.(test|spec)\.", ".", name).split(".")[0]
        if stem == base:
            rel = f"{dir_rel}/{name}" if dir_rel else name
            found.append(rel.replace("\\", "/"))
    return found


def _test_files_for_write_set(
    changed_files: list[str],
    repo_root: str,
    write_set: list[str] | None = None,
) -> list[str]:
    write_set = write_set or []
    tests: list[str] = []
    allowed = write_set or changed_files
    code_changed = [
        f for f in changed_files
        if f.startswith("src/") and not f.endswith(".md") and "index.md" not in f
        and not re.search(r"\.(test|spec)\.(tsx?|jsx?)$", f)
    ]
    for f in code_changed:
        if not any(
            f == w.rstrip("/") or f.startswith(w.rstrip("/").rstrip("/**") + "/")
            for w in allowed
        ):
            continue
        tests.extend(_colocated_test_paths_for_source(repo_root, f))
    for f in changed_files:
        if not re.search(r"\.(test|spec)\.(tsx?|jsx?)$", f):
            continue
        if any(
            f == w.rstrip("/") or f.startswith(w.rstrip("/").rstrip("/**") + "/")
            for w in allowed
        ):
            tests.append(f.replace("\\", "/"))
    return list(dict.fromkeys(tests))


def _extract_failing_test_files(output: str) -> list[str]:
    paths: list[str] = []
    for pat in (_FAIL_TEST_LINE_RE, _FAIL_TEST_AT_RE):
        for m in pat.finditer(output or ""):
            p = m.group(1).replace("\\", "/")
            if p not in paths:
                paths.append(p)
    return paths


def _test_file_in_write_set_closure(test_path: str, write_set: list[str]) -> bool:
    normalized = test_path.replace("\\", "/")
    if _path_in_write_set_tree(normalized, write_set):
        return True
    dir_rel = os.path.dirname(normalized)
    stem = re.sub(r"\.(test|spec)\.", ".", os.path.basename(normalized)).split(".")[0]
    for ext in (".ts", ".tsx", ".js", ".jsx"):
        src = f"{dir_rel}/{stem}{ext}" if dir_rel else f"{stem}{ext}"
        if _path_in_write_set_tree(src, write_set):
            return True
    return False


def _dem08_diagnostics(
    steps: list[dict[str, Any]],
    write_set: list[str],
) -> dict[str, Any]:
    failing: list[str] = []
    for step in steps:
        sid = str(step.get("id") or "")
        if not sid.startswith("test:") and sid != "test":
            continue
        if step.get("ok") is True or step.get("pass") is True:
            continue
        tail = str(step.get("output_tail") or step.get("output") or "")
        failing.extend(_extract_failing_test_files(tail))
    failing = list(dict.fromkeys(failing))
    if not write_set:
        return {
            "failing_test_files": failing,
            "out_of_write_set_closure": [],
            "verification_scope_overreach": False,
        }
    out_of_closure = [p for p in failing if not _test_file_in_write_set_closure(p, write_set)]
    scope_overreach = bool(failing) and len(out_of_closure) == len(failing)
    return {
        "failing_test_files": failing,
        "out_of_write_set_closure": out_of_closure,
        "verification_scope_overreach": scope_overreach,
    }


def _dem08_implement_warn_pass(
    test_ok: bool,
    dem08: dict[str, Any],
    related_union_mode: str,
) -> bool:
    """Pure DEM-08: every failing test file is outside write_set closure — warn, do not block implement."""
    if test_ok or not dem08.get("verification_scope_overreach"):
        return False
    if related_union_mode != "write_set_closure":
        return False
    return True


def _annotate_dem08_warn_steps(steps: list[dict[str, Any]]) -> None:
    for step in steps:
        sid = str(step.get("id") or "")
        if not sid.startswith("test:") and sid != "test":
            continue
        if step.get("ok") is False or step.get("pass") is False:
            step["dem08_warn"] = True


def _is_build_command(cmd: str) -> bool:
    c = cmd.lower()
    return ("build" in c or "build:" in c) and "test" not in c


def build_test_commands(
    repo_root: str,
    task_dir: str,
    plan: dict[str, Any],
    changed_files: list[str],
    oracle_mode: str,
) -> list[dict[str, Any]]:
    cmds: list[dict[str, Any]] = []
    write_set = _write_set_from_plan(plan, task_dir)
    verification = plan.get("verification") or {}
    test_pattern = verification.get("test_pattern") or os.environ.get("GOAL_TEST_PATTERN", "")

    resolver_path = os.path.join(_script_dir(), "resolve_verification_commands.py")
    if os.path.isfile(resolver_path):
        resolver = _load_module("resolve_verification_commands", resolver_path)
        os.environ.setdefault("GOAL_HANDOFF_DIR", resolve_handoff_dir(task_dir))
        resolved = resolver.resolve_verification_commands(task_dir, repo_root, "h5")
        for item in resolved.get("commands") or []:
            cmd = str(item.get("cmd", ""))
            if "test" in str(item.get("id", "")).lower() or "test" in cmd.lower():
                if oracle_mode != "full_suite" and "watchAll=false" in cmd and "--findRelatedTests" not in cmd:
                    continue
                kind = "build" if _is_build_command(cmd) else "test"
                cmds.append({"id": item.get("id", "handoff-test"), "cmd": cmd, "source": item.get("source", "handoff"), "kind": kind})

    handoff_cmds = plan.get("verification_commands") or []
    for item in handoff_cmds:
        if isinstance(item, dict) and item.get("cmd"):
            cmd = str(item["cmd"])
            entry = {"id": item.get("id", "plan-cmd"), "cmd": cmd, "source": "plan"}
            if _is_build_command(cmd):
                entry["kind"] = "build"
            else:
                entry["kind"] = "test"
            cmds.append(entry)

    has_plan_test = any(c.get("kind") == "test" for c in cmds)

    if oracle_mode == "full_suite":
        if os.path.isfile(os.path.join(repo_root, "yarn.lock")):
            cmds.append({"id": "full-suite", "cmd": "CI=true yarn test --watchAll=false", "source": "oracle_mode"})
        elif os.path.isfile(os.path.join(repo_root, "package.json")):
            cmds.append({"id": "full-suite", "cmd": "CI=true npm test -- --watchAll=false", "source": "oracle_mode"})
        return _dedupe_commands(cmds)

    if has_plan_test:
        return _dedupe_commands(cmds)

    related_seeds, direct_tests = _find_related_test_targets(
        changed_files, write_set, repo_root, plan=plan, task_dir=task_dir
    )
    related_cmd = _compose_find_related_test_cmd(repo_root, related_seeds, direct_tests)

    if related_cmd and os.path.isfile(os.path.join(repo_root, "package.json")):
        cmds.append(
            {
                "id": "related-tests",
                "cmd": related_cmd,
                "source": "findRelatedTests",
                "related_union_mode": _related_union_mode(),
            }
        )
    elif test_pattern and len(str(test_pattern).strip()) >= 2 and str(test_pattern).strip() not in ("=", "-"):
        if os.path.isfile(os.path.join(repo_root, "yarn.lock")):
            cmds.append(
                {
                    "id": "pattern-tests",
                    "cmd": f"CI=true yarn test --testPathPattern={test_pattern} --watchAll=false",
                    "source": "test_pattern",
                }
            )

    return _dedupe_commands(cmds)


def _dedupe_commands(cmds: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: dict[str, dict[str, Any]] = {}
    for c in cmds:
        seen[c["cmd"]] = c
    return list(seen.values())


def build_build_command(plan: dict[str, Any], task_dir: str) -> str | None:
    verification = plan.get("verification") or {}
    if verification.get("build_command"):
        return str(verification["build_command"])
    if os.environ.get("GOAL_BUILD_COMMAND"):
        return os.environ["GOAL_BUILD_COMMAND"]
    index_path = os.path.join(task_dir, "index.md")
    if os.path.isfile(index_path):
        text = open(index_path, encoding="utf-8").read()
        if re.search(r"build:beta|V0[0-9].*build", text, re.I):
            return "CI= yarn build:beta"
    return None


def run_shell(cmd: str, repo_root: str, timeout: int = 900) -> dict[str, Any]:
    start = datetime.now(timezone.utc)
    try:
        r = subprocess.run(cmd, shell=True, cwd=repo_root, capture_output=True, text=True, timeout=timeout)
        tail = ((r.stdout or "") + (r.stderr or ""))[-2000:]
        ok = r.returncode == 0
    except subprocess.TimeoutExpired as e:
        tail = str(e)[-500:]
        ok = False
        r = type("R", (), {"returncode": 124})()
    elapsed = int((datetime.now(timezone.utc) - start).total_seconds() * 1000)
    return {"cmd": cmd, "exit_code": r.returncode, "ok": ok, "output_tail": tail, "duration_ms": elapsed}


def _inject_jest_max_workers(cmd: str) -> str:
    """Ensure jest/yarn test uses --maxWorkers=50% (Pack E CPU)."""
    if "test" not in cmd.lower():
        return cmd
    if "--maxWorkers" in cmd or "--maxWorkers=" in cmd:
        return cmd
    if "watchAll=false" in cmd or "findRelatedTests" in cmd or "yarn test" in cmd or "npm test" in cmd:
        return cmd + " --maxWorkers=50%"
    return cmd


def _resolve_typecheck_cmd(repo_root: str) -> str | None:
    """Best-effort typecheck command when tsconfig exists (Pack E parallel with tests)."""
    if not os.path.isfile(os.path.join(repo_root, "tsconfig.json")):
        return None
    pkg = os.path.join(repo_root, "package.json")
    if os.path.isfile(pkg):
        try:
            scripts = (json.load(open(pkg, encoding="utf-8")).get("scripts") or {})
            for name in ("typecheck", "tsc", "ts:check"):
                if name in scripts:
                    pm = "yarn" if os.path.isfile(os.path.join(repo_root, "yarn.lock")) else "npm run"
                    return f"{pm} {name}" if pm == "yarn" else f"npm run {name}"
        except (OSError, json.JSONDecodeError):
            pass
    # Fallback: tsc --noEmit when local tsc available via yarn/npx
    if os.path.isfile(os.path.join(repo_root, "node_modules", "typescript", "bin", "tsc")):
        return "npx tsc --noEmit"
    return None


def _prior_build_attested(evidence_dir: str | None, code_hash: str) -> bool:
    """Pack D: same code_subject_hash + prior UVO build pass → skip rebuild."""
    if not evidence_dir or not code_hash or code_hash in ("unknown", ""):
        return False
    path = os.path.join(evidence_dir, "verification-oracle.json")
    if not os.path.isfile(path):
        return False
    try:
        prev = json.load(open(path, encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    if prev.get("overall") != "pass":
        return False
    stored = prev.get("code_subject_hash") or prev.get("candidate_diff_hash") or ""
    if stored != code_hash:
        return False
    for step in prev.get("steps") or []:
        sid = str(step.get("id") or "")
        if sid == "build" or sid.startswith("build"):
            if step.get("ok") is True or step.get("pass") is True:
                return True
            cmd = str(step.get("command") or step.get("cmd") or "")
            if "skipped" in cmd.lower() or "attested" in str(step.get("output") or step.get("output_tail") or "").lower():
                return True
    return False


def _run_parallel(cmds: list[tuple[str, str]], repo_root: str, timeout: int = 900) -> list[dict[str, Any]]:
    """Run named commands in parallel; fail-fast join. cmds: list of (id, cmd)."""
    from concurrent.futures import ThreadPoolExecutor, as_completed

    if not cmds:
        return []
    if len(cmds) == 1:
        cid, cmd = cmds[0]
        ex = run_shell(cmd, repo_root, timeout=timeout)
        ex["id"] = cid
        return [ex]

    results: dict[str, dict[str, Any]] = {}
    with ThreadPoolExecutor(max_workers=min(4, len(cmds))) as pool:
        futs = {pool.submit(run_shell, cmd, repo_root, timeout): cid for cid, cmd in cmds}
        for fut in as_completed(futs):
            cid = futs[fut]
            try:
                ex = fut.result()
            except Exception as e:  # noqa: BLE001
                ex = {"cmd": "", "exit_code": 1, "ok": False, "output_tail": str(e)[:500], "duration_ms": 0}
            ex["id"] = cid
            results[cid] = ex
    return [results[cid] for cid, _ in cmds if cid in results]


def check_scope(repo_root: str, write_set: list[str]) -> dict[str, Any]:
    changed = git_changed_files(repo_root)
    out_of_scope: list[str] = []
    for f in changed:
        if f.startswith("docs/guazi-flow/"):
            continue
        allowed = any(
            f == w.rstrip("/") or f.startswith(w.rstrip("/").rstrip("/**") + "/")
            for w in write_set
        )
        if write_set and not allowed:
            out_of_scope.append(f)
    return {"pass": len(out_of_scope) == 0, "modified_files": changed, "out_of_scope": out_of_scope}


def check_secrets(repo_root: str) -> dict[str, Any]:
    try:
        diff = subprocess.check_output(["git", "-C", repo_root, "diff", "HEAD"], text=True, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.CalledProcessError):
        diff = ""
    patterns = [
        r"API_KEY[=:]\s*['\"]?\w{8,}",
        r"AKIA[0-9A-Z]{16}",
        r"ghp_[a-zA-Z0-9]{36}",
        r"sk-[a-zA-Z0-9]{20,}",
    ]
    findings: list[str] = []
    for pat in patterns:
        for line in diff.splitlines():
            if line.startswith("-") or line.startswith("#"):
                continue
            if re.search(pat, line, re.I):
                findings.append(line[:80])
    return {"pass": len(findings) == 0, "findings": findings}


def check_lint(repo_root: str) -> dict[str, Any]:
    try:
        lint_files = subprocess.check_output(
            ["git", "-C", repo_root, "diff", "--name-only", "HEAD"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        files = [f for f in lint_files.splitlines() if re.search(r"\.(tsx?|jsx?|vue)$", f)]
    except (OSError, subprocess.CalledProcessError):
        files = []
    if not files:
        return {"pass": True, "command": "skipped", "output": "no lintable files in diff"}
    cmd = f"npx eslint --quiet {' '.join(files[:30])}"
    r = run_shell(cmd, repo_root, timeout=300)
    return {"pass": r["ok"], "command": cmd, "output": r["output_tail"][:500]}


def run_oracle(
    task_dir: str,
    repo_root: str,
    tier: str = "standard",
    oracle_mode: str | None = None,
    skip_build: bool = False,
    evidence_dir: str | None = None,
) -> dict[str, Any]:
    task_dir = os.path.abspath(task_dir)
    repo_root = os.path.abspath(repo_root or os.getcwd())
    mode = oracle_mode or ("full_suite" if tier == "strict" else "related_union")
    plan = load_plan_handoff(task_dir)
    write_set = _write_set_from_plan(plan, task_dir)
    changed = git_changed_files(repo_root)
    gh = git_head(repo_root)
    ref_branch = plan.get("reference_branch") or plan.get("reference_impl_branch") or ""
    dh = code_subject_hash(repo_root, write_set, ref_branch)
    artifact_h = artifact_diff_hash(repo_root, task_dir)

    start_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
    steps: list[dict[str, Any]] = []

    scope = check_scope(repo_root, write_set)
    steps.append({"id": "scope", **scope})
    secret = check_secrets(repo_root)
    steps.append({"id": "secret", **secret})
    lint = check_lint(repo_root)
    steps.append({"id": "lint", **lint})

    all_cmds = build_test_commands(repo_root, task_dir, plan, changed, mode)
    test_cmds = [c for c in all_cmds if c.get("kind") != "build" and not _is_build_command(c.get("cmd", ""))]
    build_cmds = [c for c in all_cmds if c.get("kind") == "build" or _is_build_command(c.get("cmd", ""))]


    # Pack E: typecheck ∥ jest (maxWorkers); fail-fast on join
    parallel_jobs: list[tuple[str, str]] = []
    tc_cmd = _resolve_typecheck_cmd(repo_root)
    if tc_cmd and os.environ.get("GOAL_UVO_SKIP_TYPECHECK", "0") != "1":
        parallel_jobs.append(("typecheck", tc_cmd))
    for tc in test_cmds:
        cmd = _inject_jest_max_workers(str(tc["cmd"]))
        parallel_jobs.append((f"test:{tc['id']}", cmd))

    test_ok = True
    typecheck_ok = True
    if parallel_jobs:
        for ex in _run_parallel(parallel_jobs, repo_root):
            cid = ex.get("id", "step")
            if cid == "typecheck":
                steps.append({"id": "typecheck", **ex})
                if not ex.get("ok"):
                    typecheck_ok = False
            else:
                steps.append({"id": cid, **ex, "source": "uvo_parallel"})
                if not ex.get("ok"):
                    test_ok = False
    else:
        steps.append({"id": "test", "pass": True, "command": "skipped", "output": "no test commands resolved"})

    build_ok = True
    build_cmd = None
    if build_cmds:
        build_cmd = build_cmds[0]["cmd"]
    elif not skip_build:
        build_cmd = build_build_command(plan, task_dir)

    # Pack D: same code_subject_hash + prior build pass → skip build:beta
    if not skip_build and build_cmd and _prior_build_attested(evidence_dir, dh):
        steps.append({
            "id": "build",
            "pass": True,
            "ok": True,
            "command": "skipped",
            "cmd": build_cmd,
            "output": f"UVO cache hit — same code_subject_hash={dh}, prior build pass",
        })
        build_ok = True
    elif not skip_build and build_cmd:
        ex = run_shell(build_cmd, repo_root)
        ex["id"] = "build"
        steps.append(ex)
        build_ok = ex["ok"]
    else:
        steps.append({"id": "build", "pass": True, "command": "skipped", "output": "no build required"})

    overall = (
        scope["pass"]
        and secret["pass"]
        and lint.get("pass", lint.get("ok", True))
        and test_ok
        and typecheck_ok
        and build_ok
    )

    end_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
    dem08 = _dem08_diagnostics(steps, write_set)
    union_mode = _related_union_mode()
    dem08_implement_warn = _dem08_implement_warn_pass(test_ok, dem08, union_mode)
    if dem08_implement_warn:
        test_ok = True
        _annotate_dem08_warn_steps(steps)
        overall = (
            scope["pass"]
            and secret["pass"]
            and lint.get("pass", lint.get("ok", True))
            and test_ok
            and typecheck_ok
            and build_ok
        )
    result = {
        "schema_version": 1,
        "runner": "verification-oracle.sh",
        "overall": "pass" if overall else "not_pass",
        "oracle_mode": mode,
        "related_union_mode": union_mode,
        "dem08_implement_warn": dem08_implement_warn,
        "tier": tier,
        "git_head": gh,
        "candidate_diff_hash": dh,
        "code_subject_hash": dh,
        "artifact_hash": artifact_h,
        "reference_branch": ref_branch,
        "changed_files": changed,
        "write_set": write_set,
        "smoke_required": smoke_required(changed, write_set, tier),
        "duration_ms": end_ms - start_ms,
        "steps": steps,
        "commands": [s.get("cmd") for s in steps if s.get("cmd")],
        "passed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "failing_test_files": dem08["failing_test_files"],
        "out_of_write_set_closure": dem08["out_of_write_set_closure"],
        "verification_scope_overreach": dem08["verification_scope_overreach"],
    }

    if evidence_dir:
        os.makedirs(evidence_dir, exist_ok=True)
        out_path = os.path.join(evidence_dir, "verification-oracle.json")
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2, ensure_ascii=False)
        result["evidence_path"] = out_path

    return result


def _plan_ref_branch(task_dir: str) -> str:
    if not task_dir:
        return ""
    handoff = os.path.join(task_dir, "handoff", "plan.json")
    if os.path.isfile(handoff):
        try:
            plan = json.load(open(handoff, encoding="utf-8"))
            return plan.get("reference_branch") or plan.get("reference_impl_branch") or ""
        except (OSError, json.JSONDecodeError):
            pass
    return ""


def check_freshness(evidence_path: str, repo_root: str, task_dir: str = "") -> dict[str, Any]:
    if not os.path.isfile(evidence_path):
        return {"fresh": False, "reason": "missing"}
    data = json.load(open(evidence_path, encoding="utf-8"))
    if data.get("overall") != "pass":
        return {"fresh": False, "reason": "overall_not_pass"}
    gh = git_head(repo_root)
    stored_gh = data.get("git_head") or ""
    if stored_gh and stored_gh not in ("unknown", "") and gh not in ("unknown", "") and stored_gh != gh:
        return {"fresh": False, "reason": "git_head_mismatch", "expected": gh, "stored": stored_gh}
    ref_branch = data.get("reference_branch") or _plan_ref_branch(task_dir) or "main...HEAD"
    plan = load_plan_handoff(task_dir) if task_dir else {}
    write_set = _write_set_from_plan(plan, task_dir) if plan else (data.get("write_set") or [])
    dh = code_subject_hash(repo_root, write_set, ref_branch)
    stored_dh = data.get("code_subject_hash") or data.get("candidate_diff_hash") or ""
    if stored_dh and stored_dh not in ("unknown", "") and dh not in ("unknown", "") and stored_dh != dh:
        return {"fresh": False, "reason": "diff_hash_mismatch", "expected": dh, "stored": stored_dh}
    return {"fresh": True, "evidence": data}


def main():
    import argparse

    p = argparse.ArgumentParser(description="Unified Verification Oracle core")
    p.add_argument("--task-dir", required=True)
    p.add_argument("--repo-root", default=".")
    p.add_argument("--tier", choices=("standard", "strict"), default="standard")
    p.add_argument("--oracle-mode", choices=("related_union", "full_suite"), default="")
    p.add_argument("--evidence-dir", default="")
    p.add_argument("--skip-build", action="store_true")
    p.add_argument("--check-freshness", action="store_true")
    p.add_argument("--json", action="store_true", dest="as_json")
    args = p.parse_args()

    repo = os.path.abspath(args.repo_root)
    evidence = args.evidence_dir or os.environ.get("GOAL_EVIDENCE_DIR", "")

    if args.check_freshness:
        ep = os.path.join(evidence, "verification-oracle.json") if evidence else ""
        if not ep:
            ep = os.path.join(args.task_dir, "evidence", "verification-oracle.json")
        result = check_freshness(ep, repo, args.task_dir)
    else:
        mode = args.oracle_mode or None
        result = run_oracle(
            args.task_dir,
            repo,
            tier=args.tier,
            oracle_mode=mode,
            skip_build=args.skip_build,
            evidence_dir=evidence or None,
        )

    if args.as_json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(result.get("overall", result.get("fresh", False)))

    ok = result.get("overall") == "pass" if "overall" in result else result.get("fresh", False)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
