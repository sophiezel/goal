#!/bin/bash
# test-code-subject-hash.sh — evidence writes must not change code_subject_hash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_SCRIPTS:-${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts}"

python3 - "$SCRIPTS" << 'PY'
import importlib.util, json, os, sys, tempfile, subprocess

scripts = sys.argv[1]
spec = importlib.util.spec_from_file_location("uvo", os.path.join(scripts, "verification_oracle_core.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

tmp = tempfile.mkdtemp()
subprocess.run(["git", "init", tmp], capture_output=True, check=True)
subprocess.run(["git", "-C", tmp, "config", "user.email", "t@t.com"], check=True)
subprocess.run(["git", "-C", tmp, "config", "user.name", "t"], check=True)
os.makedirs(os.path.join(tmp, "src"), exist_ok=True)
open(os.path.join(tmp, "src", "app.ts"), "w").write("export const a = 1;\n")
subprocess.run(["git", "-C", tmp, "add", "src/app.ts"], check=True)
subprocess.run(["git", "-C", tmp, "commit", "-m", "init"], capture_output=True, check=True)

ws = ["src/"]
h1 = mod.code_subject_hash(tmp, ws, "")
evidence = os.path.join(tmp, "docs/guazi-flow/task/evidence")
os.makedirs(evidence, exist_ok=True)
open(os.path.join(evidence, "review-run.json"), "w").write('{"x":1}')
h2 = mod.code_subject_hash(tmp, ws, "")
assert h1 == h2, (h1, h2)

a1 = mod.artifact_diff_hash(tmp, os.path.join(tmp, "docs/guazi-flow/task"))
a2 = mod.artifact_diff_hash(tmp, os.path.join(tmp, "docs/guazi-flow/task"))
assert a1 != "unknown"
print("code_subject_hash stable OK")
PY

echo "test-code-subject-hash passed"
