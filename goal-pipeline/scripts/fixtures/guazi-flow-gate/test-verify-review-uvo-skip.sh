#!/bin/bash
# test-verify-review-uvo-skip.sh — verify-review skips test/build when UVO fresh pass
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
VERIFY="$SCRIPTS/verify-review.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 - "$TMP" "$SCRIPTS" << 'PY'
import importlib.util, json, os, subprocess, sys

tmp, scripts = sys.argv[1:3]
spec = importlib.util.spec_from_file_location("uvo", os.path.join(scripts, "verification_oracle_core.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

spec2 = importlib.util.spec_from_file_location("dr", os.path.join(scripts, "diff_resolver.py"))
dr = importlib.util.module_from_spec(spec2)
spec2.loader.exec_module(dr)

subprocess.run(["git", "init", tmp], capture_output=True, check=True)
subprocess.run(["git", "-C", tmp, "config", "user.email", "t@t.com"], check=True)
subprocess.run(["git", "-C", tmp, "config", "user.name", "t"], check=True)
subprocess.run(["git", "-C", tmp, "checkout", "-b", "main"], capture_output=True, check=True)

task_dir = os.path.join(tmp, "docs", "guazi-flow", "task")
handoff = os.path.join(task_dir, "handoff")
evidence = os.path.join(task_dir, "evidence")
os.makedirs(handoff, exist_ok=True)
os.makedirs(evidence, exist_ok=True)

open(os.path.join(tmp, "package.json"), "w").write('{"scripts":{"test":"exit 1","build:beta":"exit 1"}}')
os.makedirs(os.path.join(tmp, "src"), exist_ok=True)
open(os.path.join(tmp, "src", "app.ts"), "w").write("export const a = 1;\n")
subprocess.run(["git", "-C", tmp, "add", "package.json", "src/app.ts", "docs"], check=True)
subprocess.run(["git", "-C", tmp, "commit", "-m", "init"], capture_output=True, check=True)

json.dump(
    {"write_set": ["src/"], "reference_branch": "main...HEAD", "verification": {"test_pattern": "foo"}},
    open(os.path.join(handoff, "plan.json"), "w"),
)

gh = subprocess.check_output(["git", "-C", tmp, "rev-parse", "--short=16", "HEAD"], text=True).strip()
csh = mod.code_subject_hash(tmp, ["src/"], "main...HEAD")
fresh = mod.check_freshness(
    os.path.join(evidence, "verification-oracle.json"),
    tmp,
    task_dir,
)
# Write UVO after computing expected hash
json.dump(
    {
        "overall": "pass",
        "git_head": gh,
        "code_subject_hash": csh,
        "write_set": ["src/"],
        "reference_branch": "main...HEAD",
        "steps": [],
    },
    open(os.path.join(evidence, "verification-oracle.json"), "w"),
    indent=2,
)
fresh = mod.check_freshness(os.path.join(evidence, "verification-oracle.json"), tmp, task_dir)
assert fresh.get("fresh"), fresh

env = os.environ.copy()
env["GOAL_EVIDENCE_DIR"] = evidence
env["GOAL_SKIP_SCOPE"] = "1"
env["GOAL_SKIP_SECRET"] = "1"
env["GOAL_SKIP_LINT"] = "1"
out = subprocess.check_output(
    [os.path.join(scripts, "verify-review.sh"), task_dir, "src/", "json"],
    env=env,
    text=True,
)
data = json.loads(out)
assert data["overall"] == "pass", data
assert "UVO fresh pass" in data["checks"]["test"]["output"], data["checks"]["test"]
assert "UVO fresh pass" in data["checks"]["build"]["output"], data["checks"]["build"]
print("verify-review UVO skip OK")
PY

echo "test-verify-review-uvo-skip passed"
