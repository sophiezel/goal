#!/usr/bin/env bash
# validate-state-path.sh — Reject non-canonical project_id / cross-project state paths.
# Usage: validate-state-path.sh --state-file PATH --project-root PATH [--format json|text]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE=""
PROJECT_ROOT=""
FORMAT="text"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --state-file PATH --project-root PATH [--format json|text]"
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$STATE_FILE" && -n "$PROJECT_ROOT" ]] || {
  echo "validate-state-path: --state-file and --project-root required" >&2
  exit 2
}
[[ -f "$STATE_FILE" ]] || { echo "validate-state-path: state file missing" >&2; exit 2; }
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

python3 - "$STATE_FILE" "$PROJECT_ROOT" "$FORMAT" "$SCRIPT_DIR" <<'PY'
import hashlib, json, os, sys
from pathlib import Path

state_path, project_root, fmt, script_dir = sys.argv[1:5]
# import helper from resolve-artifact-paths
sys.path.insert(0, script_dir)
from importlib import util
spec = util.spec_from_file_location("rap", os.path.join(script_dir, "resolve-artifact-paths.py"))
rap = util.module_from_spec(spec)
spec.loader.exec_module(rap)

sf = Path(state_path)
root = Path(project_root)
ok, err = rap.validate_state_project_id(sf, root)
expected = rap.project_id(root)
branch = rap.current_git_branch(root)
out = {
    "ok": ok,
    "project_id_expected": expected,
    "branch": branch,
    "state_file": str(sf),
    "error": err or "",
}
if fmt == "json":
    print(json.dumps(out, ensure_ascii=False, indent=2))
else:
    if ok:
        print(f"validate-state-path: OK project_id={expected} branch={branch}")
    else:
        print(f"validate-state-path: FAIL {err}", file=sys.stderr)
sys.exit(0 if ok else 2)
PY
