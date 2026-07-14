#!/bin/bash
# test-write-set-contamination.sh — exclusions/prose must not enter write_set
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"

python3 - "$SCRIPTS" << 'PY'
import importlib.util, os, sys

scripts = sys.argv[1]
spec = importlib.util.spec_from_file_location("ich", os.path.join(scripts, "index_contract_hash.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

raw = [
    "src/pages/evaluateRecoveryList/",
    "排除：RN 首页入口",
    "不做项：改原生",
    "docs/guazi-flow/task/index.md",
    "exclude node_modules",
]
out = mod.normalize_write_set(raw)
assert "src/pages/evaluateRecoveryList/" in out, out
assert "docs/guazi-flow/task/index.md" in out, out
assert not any("排除" in x or "不做" in x or "exclude" in x.lower() for x in out), out
assert mod.is_write_set_contamination("排除 RN")
assert not mod.is_write_set_contamination("src/foo/")
print("write_set_contamination OK", out)
PY

echo "test-write-set-contamination passed"
