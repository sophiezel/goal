#!/usr/bin/env python3
"""Index contract fingerprint helpers for goal-pipeline gates.

index_contract_hash covers stable plan contract sections only.
Execution records (## 执行记录 and after) are excluded so append-only
stage logs do not invalidate plan handoff freshness.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from typing import Any, Iterable, List, Optional, Tuple


EXEC_RECORD_RE = re.compile(r"(?m)^##\s*执行记录\b")
FM_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n?", re.DOTALL)


def sha16(data: str | bytes) -> str:
    if isinstance(data, str):
        data = data.encode("utf-8")
    return hashlib.sha256(data).hexdigest()[:16]


def _normalize_frontmatter(fm_raw: str) -> str:
    """Keep stable frontmatter keys; drop volatile current_stage (flat or nested)."""
    lines_out = []
    in_flow = False
    for line in fm_raw.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        # Detect nested flow block
        if re.match(r"^flow\s*:", stripped):
            in_flow = True
            lines_out.append("flow:")
            continue
        if in_flow:
            if line.startswith(" ") or line.startswith("\t"):
                if "current_stage" in stripped.split(":", 1)[0]:
                    continue
                lines_out.append(line.rstrip())
                continue
            in_flow = False
        key = stripped.split(":", 1)[0].strip()
        if key == "current_stage":
            continue
        lines_out.append(stripped)
    return "\n".join(lines_out)


def split_index(text: str) -> Tuple[str, str]:
    """Return (contract_body, execution_tail)."""
    m = EXEC_RECORD_RE.search(text)
    if m:
        return text[: m.start()], text[m.start() :]
    return text, ""


def contract_fingerprint_text(text: str) -> str:
    """Stable contract text used for hashing."""
    contract, _ = split_index(text)
    fm = FM_RE.match(contract)
    if fm:
        body = contract[fm.end() :]
        fm_norm = _normalize_frontmatter(fm.group(1))
        return fm_norm + "\n---\n" + body
    return contract


def index_contract_hash(path: str) -> str:
    text = open(path, encoding="utf-8").read()
    return sha16(contract_fingerprint_text(text))


def index_execution_tail_hash(path: str) -> str:
    text = open(path, encoding="utf-8").read()
    _, tail = split_index(text)
    return sha16(tail) if tail else sha16("")


_WRITE_SET_EXCLUSION_MARKERS = (
    "排除",
    "除外",
    "不做",
    "不包含",
    "exclude",
    "exclusion",
    "out of scope",
    "out-of-scope",
    "not in write",
    "非写集",
)


def is_write_set_contamination(entry: str) -> bool:
    """True for prose / exclusion bullets that must not enter write_set paths."""
    raw = (entry or "").strip()
    if not raw:
        return True
    low = raw.lower()
    if any(m in low or m in raw for m in _WRITE_SET_EXCLUSION_MARKERS):
        return True
    # Pure path-ish: allow alnum, slash, underscore, dash, dot, @
    # Reject sentences / Chinese prose / spaces with explanation.
    if " " in raw and not raw.startswith("src/") and "/" not in raw.split()[0]:
        return True
    if any(ch in raw for ch in ("：", "。", "，", "（", "）", "(", ")")) and not raw.startswith("`"):
        # Allow path(with)parens rarely — but Chinese punctuation ⇒ prose
        if any("\u4e00" <= c <= "\u9fff" for c in raw):
            return True
    return False


def _is_api_path_not_repo_path(p: str) -> bool:
    """HTTP API paths mistaken for repo paths (AM-07 / iter_write_set_files)."""
    if p.startswith("/external/") or p.startswith("/api/"):
        return True
    if p.startswith("/") and not p.startswith("/Users") and "/" in p[1:]:
        # Leading-slash path without src/docs/config — likely URI, not filesystem
        if not p.startswith(("/src/", "/docs/", "/config/", "/public/")):
            return True
    return False


_APP_ENTRY_ALIASES = {
    "App.tsx": "src/App.tsx",
    "pages/index.ts": "src/pages/index.ts",
    "pages/index.tsx": "src/pages/index.tsx",
}


def normalize_write_set_entry(path: str) -> str:
    p = (path or "").strip().strip("`").strip()
    if not p:
        return ""
    if is_write_set_contamination(p):
        return ""
    if _is_api_path_not_repo_path(p):
        return ""
    if p in _APP_ENTRY_ALIASES:
        p = _APP_ENTRY_ALIASES[p]
    elif p.endswith("App.tsx") and not p.startswith("src/"):
        p = f"src/{p}"
    elif p.startswith("pages/") and not p.startswith("src/"):
        p = f"src/{p}"
    # src/foo/** → src/foo/
    if p.endswith("/**"):
        p = p[:-3] + "/"
    elif p.endswith("/**/"):
        p = p[:-4] + "/"
    # collapse duplicate slashes except leading
    while "//" in p:
        p = p.replace("//", "/")
    return p


def normalize_write_set(paths: Iterable[str]) -> List[str]:
    out: List[str] = []
    seen = set()
    for p in paths:
        n = normalize_write_set_entry(p)
        if not n or n in seen:
            continue
        seen.add(n)
        out.append(n)
    return out


def path_allowed(path: str, write_set: Iterable[str]) -> bool:
    for w in write_set:
        w = normalize_write_set_entry(w).rstrip("/")
        if not w:
            continue
        if path == w or path.startswith(w + "/"):
            return True
    return False


def stored_contract_hash(plan: dict) -> str:
    """Prefer index_contract_hash; fall back to legacy index_schema_hash."""
    return (
        plan.get("index_contract_hash")
        or plan.get("index_schema_hash")
        or ""
    )


def _extract_write_set_paths_from_index(index_text: str) -> List[str]:
    """Best-effort write_set paths from index.md bullets/tables."""
    m = re.search(
        r"(?:##\s*(?:write_set|写集|范围与写集)|write_set\s*[:：])\s*\n([\s\S]*?)(?:\n##|\Z)",
        index_text,
        re.I,
    )
    if not m:
        return []
    paths: List[str] = []
    for line in m.group(1).splitlines():
        line = line.strip()
        if not line:
            continue
        if re.match(r"^(排除|除外|不做|不包含|exclude)", line, re.I):
            break
        bm = re.match(r"^[-*]\s+`?([^`]+)`?", line)
        if bm:
            n = normalize_write_set_entry(bm.group(1))
            if n:
                paths.append(n)
            continue
        tm = re.match(r"^\|\s*`?([^`|]+)`?\s*\|", line)
        if tm:
            n = normalize_write_set_entry(tm.group(1))
            if n and "路径" not in n and "path" not in n.lower():
                paths.append(n)
    return normalize_write_set(paths)


def write_set_shrink_only(index_path: str, plan: dict) -> bool:
    """True when index write_set is a proper subset of plan write_set (removals only)."""
    try:
        index_text = open(index_path, encoding="utf-8").read()
    except OSError:
        return False
    new_ws = set(_extract_write_set_paths_from_index(index_text))
    old_ws = set(normalize_write_set(plan.get("write_set") or []))
    if not old_ws or not new_ws:
        return False
    if new_ws == old_ws:
        return False
    return new_ws.issubset(old_ws)


def compare_plan_freshness(index_path: str, plan: dict) -> dict:
    """Compare current index contract vs plan handoff."""
    current = index_contract_hash(index_path)
    stored = stored_contract_hash(plan)
    exec_cur = index_execution_tail_hash(index_path)
    exec_stored = plan.get("index_execution_tail_hash", "")
    contract_changed = bool(stored) and stored != current
    # Legacy full-file hash: if only index_schema_hash exists and equals full file,
    # treat as stale-unknown; callers should refresh. For migration, if stored
    # equals current contract hash we're good; if stored equals full-file hash
    # of old content we can't know — contract_changed True only when stored set
    # and differs from current contract.
    exec_changed = bool(exec_stored) and exec_stored != exec_cur
    if not exec_stored and not contract_changed:
        # no exec hash stored: infer exec may have changed if legacy full hash differs
        legacy = plan.get("index_schema_hash", "")
        if legacy and not plan.get("index_contract_hash") and legacy != current:
            # Could be full-file hash; check if full file hash matches legacy
            full = sha16(open(index_path, encoding="utf-8").read().encode("utf-8"))
            if legacy == full:
                exec_changed = True
                contract_changed = False
            elif legacy != current:
                # ambiguous: prefer contract_changed only if contract differs
                # Recompute: if contract matches somehow via coincidence skip
                contract_changed = True
    shrink_only = False
    if contract_changed and write_set_shrink_only(index_path, plan):
        # Pack B: write_set shrink must not force mini-replan / invalidate review
        shrink_only = True
        contract_changed = False
        exec_changed = True
    return {
        "current_contract_hash": current,
        "stored_contract_hash": stored,
        "current_execution_tail_hash": exec_cur,
        "stored_execution_tail_hash": exec_stored,
        "contract_changed": contract_changed,
        "execution_changed": exec_changed and not contract_changed,
        "write_set_shrink_only": shrink_only,
        "fresh": not contract_changed,
    }


def extract_verification_hints(index_text: str) -> dict:
    """Pull test_pattern / build_command hints from acceptance matrix lines."""
    hints: dict[str, Any] = {}
    # yarn build:beta / npm run build
    if re.search(r"yarn\s+build:beta", index_text):
        hints["build_command"] = "CI= yarn build:beta"
    elif re.search(r"yarn\s+build\b", index_text):
        hints["build_command"] = "CI= yarn build"
    # testPathPattern=...
    m = re.search(r"testPathPattern[=:]?\s*[`\"]?([^`\"\\s|]+)", index_text)
    if m:
        hints["test_pattern"] = m.group(1).strip()
    return hints


def main(argv: Optional[List[str]] = None) -> int:
    argv = list(argv or sys.argv[1:])
    if not argv or argv[0] in ("-h", "--help"):
        print(
            "Usage: index_contract_hash.py <index.md>\n"
            "       index_contract_hash.py --json <index.md> [plan.json]\n"
            "       index_contract_hash.py --normalize-write-set 'a/**,b/'",
            file=sys.stderr,
        )
        return 2
    if argv[0] == "--normalize-write-set":
        raw = argv[1] if len(argv) > 1 else ""
        items = [x.strip() for x in raw.replace("\n", ",").split(",") if x.strip()]
        print(json.dumps(normalize_write_set(items), ensure_ascii=False))
        return 0
    if argv[0] == "--json":
        index_path = argv[1]
        plan = {}
        if len(argv) > 2 and argv[2]:
            plan = json.load(open(argv[2], encoding="utf-8"))
        out = {
            "index_contract_hash": index_contract_hash(index_path),
            "index_execution_tail_hash": index_execution_tail_hash(index_path),
        }
        if plan:
            out.update(compare_plan_freshness(index_path, plan))
        print(json.dumps(out, ensure_ascii=False))
        return 0
    print(index_contract_hash(argv[0]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
