#!/usr/bin/env bash
# integration-contract-check.sh — read-only cross_app checks from integration-manifest.json
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${1:-}"
if [[ -z "$MANIFEST" || ! -f "$MANIFEST" ]]; then
  echo "usage: integration-contract-check.sh <handoff/integration-manifest.json>" >&2
  exit 2
fi
python3 - "$MANIFEST" << 'PY'
import json, os, re, sys
manifest_path = sys.argv[1]
manifest = json.load(open(manifest_path, encoding="utf-8"))
roots = {e["id"]: e["project_root"] for e in manifest.get("project_roots", []) if e.get("id")}
errors = []
for item in manifest.get("cross_app", []):
    path = item.get("path", "")
    queries = item.get("query") or []
    globs = item.get("scan_globs") or []
    for pid, globs_entry in [(item.get("from_project"), item.get("from_scan_globs")),
                             (item.get("to_project"), item.get("to_scan_globs"))]:
        if not pid or pid not in roots:
            continue
        root = roots[pid]
        scan = globs_entry or globs
        if not scan:
            errors.append(f"{pid}: no scan_globs for cross_app path {path}")
            continue
        found_path = False
        found_queries = {q: False for q in queries}
        for g in scan:
            base = os.path.join(root, g.rstrip("/"))
            if os.path.isfile(base):
                files = [base]
            elif os.path.isdir(base):
                files = []
                for r, _, names in os.walk(base):
                    for n in names:
                        if n.endswith((".ts", ".tsx", ".js", ".jsx", ".vue")):
                            files.append(os.path.join(r, n))
            else:
                continue
            for fp in files:
                try:
                    text = open(fp, encoding="utf-8").read()
                except OSError:
                    continue
                if path in text:
                    found_path = True
                for q in queries:
                    if re.search(rf"['\"]?{re.escape(q)}['\"]?\s*[:?]", text) or q in text:
                        found_queries[q] = True
        if not found_path:
            errors.append(f"{pid}: path {path} not found under {scan}")
        for q, ok in found_queries.items():
            if not ok:
                errors.append(f"{pid}: query param {q} not found for path {path}")
if errors:
    for e in errors:
        print("BLOCK:", e)
    sys.exit(1)
print("OK integration-contract-check")
PY
