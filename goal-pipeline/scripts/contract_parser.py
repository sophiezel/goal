#!/usr/bin/env python3
"""Parse plan index API mapping tables and extract HTTP client bindings (profile adapters)."""
from __future__ import annotations

import hashlib
import json
import os
import re
from dataclasses import dataclass, field
from typing import Iterable


API_SECTION_RE = re.compile(
    r"(?ms)^#{2,3}\s*(API\s*与\s*工程\s*映射|API\s+mapping)\s*$"
)
VO_SECTION_RE = re.compile(
    r"(?ms)^#{2,3}\s*(响应\s*VO|Response\s+VO|响应字段)\s*$"
)
FROZEN_SECTION_RE = re.compile(r"(?ms)^##\s*冻结决策\s*$")

PATH_LIKE_RE = re.compile(r"(/external/[^\s`|'\"]+|/api/[^\s`|'\"]+)")

H5_KEY_RE = re.compile(r"\bkey\s*:\s*['\"]([^'\"]+)['\"]", re.I)
H5_URI_RE = re.compile(r"\buri\s*:\s*['\"]([^'\"]+)['\"]", re.I)
REQUEST_KEY_MENTION_RE = re.compile(
    r"\b(request_key|CSP_[A-Z0-9_]+|createRequest)\b", re.I
)


@dataclass
class ApiMappingRow:
    http_method: str = ""
    path: str = ""
    request_key: str = ""
    required_params: list[str] = field(default_factory=list)
    raw: str = ""


def sha16(data: str) -> str:
    return hashlib.sha256(data.encode("utf-8")).hexdigest()[:16]


def canonical_json_obj(obj: object) -> str:
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def decisions_file_hash(path: str) -> str:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return sha16(canonical_json_obj(data))


def _section_body(text: str, header_re: re.Pattern[str]) -> str:
    m = header_re.search(text)
    if not m:
        return ""
    start = m.end()
    rest = text[start:]
    nxt = re.search(r"(?m)^##\s+", rest)
    return rest[: nxt.start()] if nxt else rest


def _parse_markdown_table(body: str) -> list[list[str]]:
    rows: list[list[str]] = []
    for line in body.splitlines():
        s = line.strip()
        if not s.startswith("|"):
            continue
        if re.match(r"^\|[\s\-:|]+\|$", s):
            continue
        cells = [c.strip() for c in s.strip("|").split("|")]
        rows.append(cells)
    return rows


def _header_map(header: list[str]) -> dict[str, int]:
    m: dict[str, int] = {}
    for i, h in enumerate(header):
        key = h.lower().replace(" ", "")
        if "method" in key or h in ("方法", "HTTP"):
            m["method"] = i
        elif "path" in key or "路径" in h or "uri" in key:
            m["path"] = i
        elif ("request" in key and "key" in key) or h == "request_key" or "工程key" in h:
            m["request_key"] = i
        elif "param" in key or "参数" in h or "必填" in h:
            m["params"] = i
    return m


def parse_api_mapping_table(index_text: str) -> list[ApiMappingRow]:
    body = _section_body(index_text, API_SECTION_RE)
    if not body.strip():
        return []
    table = _parse_markdown_table(body)
    if len(table) < 2:
        return []
    hdr = _header_map(table[0])
    if "path" not in hdr:
        return []
    out: list[ApiMappingRow] = []
    for row in table[1:]:
        if len(row) <= max(hdr.values()):
            continue
        path = row[hdr["path"]].strip().strip("`")
        if not path.startswith("/"):
            continue
        method = row[hdr["method"]].strip().upper() if "method" in hdr else ""
        rk = row[hdr["request_key"]].strip().strip("`") if "request_key" in hdr else ""
        params: list[str] = []
        if "params" in hdr:
            raw_p = row[hdr["params"]]
            params = [p.strip() for p in re.split(r"[,，;；\s]+", raw_p) if p.strip()]
        out.append(
            ApiMappingRow(
                http_method=method,
                path=path,
                request_key=rk,
                required_params=params,
                raw="|".join(row),
            )
        )
    return out


def api_mapping_table_hash(index_text: str) -> str:
    rows = parse_api_mapping_table(index_text)
    if not rows:
        return ""
    payload = [
        {
            "http_method": r.http_method,
            "path": r.path,
            "request_key": r.request_key,
            "required_params": sorted(r.required_params),
        }
        for r in rows
    ]
    return sha16(canonical_json_obj(payload))


def scan_path_request_key_mentions(index_text: str) -> dict[str, set[str]]:
    """Find request_key / CSP_* mentions near path literals in full index (PQ-10)."""
    path_keys: dict[str, set[str]] = {}
    for path in PATH_LIKE_RE.findall(index_text):
        path = path.rstrip(".,;)")
        window_pat = re.compile(
            re.escape(path) + r".{0,120}|.{0,120}" + re.escape(path),
            re.I | re.S,
        )
        for m in window_pat.finditer(index_text):
            chunk = m.group(0)
            keys = set(re.findall(r"\b(CSP_[A-Z0-9_]+)\b", chunk))
            rk = re.search(r"request_key\s*[:：]\s*[`']?([A-Z0-9_]+)", chunk, re.I)
            if rk:
                keys.add(rk.group(1).upper())
            if keys:
                path_keys.setdefault(path, set()).update(keys)
    for row in parse_api_mapping_table(index_text):
        if row.path and row.request_key:
            path_keys.setdefault(row.path, set()).add(row.request_key.upper())
    return path_keys


def api_mapping_self_consistency_issues(index_text: str) -> list[str]:
    issues: list[str] = []
    rows = parse_api_mapping_table(index_text)
    by_path: dict[str, set[str]] = {}
    for r in rows:
        if not r.path:
            continue
        if r.request_key:
            by_path.setdefault(r.path, set()).add(r.request_key.upper())
    mentions = scan_path_request_key_mentions(index_text)
    all_paths = set(by_path) | set(mentions)
    for path in sorted(all_paths):
        keys = set()
        keys |= by_path.get(path, set())
        keys |= mentions.get(path, set())
        if len(keys) > 1:
            issues.append(f"path {path} has multiple request_key mentions: {sorted(keys)}")
    return issues


def has_api_contract_intent(index_text: str) -> bool:
    if parse_api_mapping_table(index_text):
        return True
    if PATH_LIKE_RE.search(index_text) and REQUEST_KEY_MENTION_RE.search(index_text):
        return True
    return False


def response_vo_section_present(index_text: str) -> bool:
    body = _section_body(index_text, VO_SECTION_RE)
    if not body.strip():
        return False
    vo_names = re.findall(r"\b\w+VO\b", body)
    return len(set(vo_names)) >= 1 or len(_parse_markdown_table(body)) >= 2


def requires_response_vo_table(index_text: str, frontmatter: dict) -> bool:
    if str(frontmatter.get("requires_response_vo", "")).lower() in ("1", "true", "yes"):
        return True
    for row in parse_api_mapping_table(index_text):
        if row.http_method == "GET" and "detail" in row.path.lower():
            return True
    return False


def frozen_decisions_issues(task_dir: str, index_text: str) -> list[str]:
    dec_path = os.path.join(task_dir, "handoff", "decisions.json")
    if not os.path.isfile(dec_path):
        return []
    issues: list[str] = []
    if not FROZEN_SECTION_RE.search(index_text):
        issues.append("handoff/decisions.json exists but index.md missing ## 冻结决策")
        return issues
    h = decisions_file_hash(dec_path)
    short = h[:16]
    if h not in index_text and short not in index_text and "decisions_hash" not in index_text.lower():
        issues.append(f"index 冻结决策 missing decisions hash (expected {short} or full hash)")
    return issues


def iter_write_set_files(repo_root: str, write_set: Iterable[str]) -> list[str]:
    files: list[str] = []
    for entry in write_set:
        entry = str(entry).strip().strip("`")
        if not entry:
            continue
        full = os.path.join(repo_root, entry)
        if os.path.isfile(full):
            files.append(full)
            continue
        if entry.endswith("/"):
            entry = entry.rstrip("/")
        base = os.path.join(repo_root, entry)
        if not os.path.isdir(base):
            continue
        for root, _dirs, names in os.walk(base):
            for name in names:
                if name.endswith((".ts", ".tsx", ".js", ".jsx", ".vue")):
                    files.append(os.path.join(root, name))
    return sorted(set(files))


@dataclass
class HttpBinding:
    request_key: str
    uri: str
    source_file: str
    snippet: str = ""


def extract_h5_bindings(file_path: str, content: str) -> list[HttpBinding]:
    bindings: list[HttpBinding] = []
    for m in re.finditer(r"createRequest\s*\(\s*\{", content):
        start = m.start()
        end = min(len(content), start + 800)
        chunk = content[start:end]
        key_m = H5_KEY_RE.search(chunk)
        uri_m = H5_URI_RE.search(chunk)
        if key_m and uri_m:
            bindings.append(
                HttpBinding(
                    request_key=key_m.group(1).upper(),
                    uri=uri_m.group(1),
                    source_file=file_path,
                    snippet=chunk[:200],
                )
            )
    return bindings


def extract_bindings_for_profile(profile: str, file_path: str, content: str) -> list[HttpBinding]:
    p = (profile or "h5").lower()
    if p in ("h5", "react", "vue", ""):
        return extract_h5_bindings(file_path, content)
    return extract_h5_bindings(file_path, content)


def main() -> int:
    import sys

    if len(sys.argv) >= 3 and sys.argv[1] == "--api-mapping-hash":
        path = sys.argv[2]
        text = open(path, encoding="utf-8").read()
        print(api_mapping_table_hash(text))
        return 0
    if len(sys.argv) >= 4 and sys.argv[1] == "--api-mapping-stale":
        index_path, plan_path = sys.argv[2], sys.argv[3]
        plan = json.load(open(plan_path, encoding="utf-8"))
        stored = (plan.get("api_mapping_table_hash") or "").strip()
        if not stored:
            print("false")
            return 0
        text = open(index_path, encoding="utf-8").read()
        cur = api_mapping_table_hash(text)
        print("true" if cur and stored != cur else "false")
        return 0
    print(
        "Usage: contract_parser.py --api-mapping-hash <index.md> | --api-mapping-stale <index.md> <plan.json>",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
