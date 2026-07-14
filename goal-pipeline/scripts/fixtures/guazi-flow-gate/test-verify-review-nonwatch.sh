#!/bin/bash
# test-verify-review-nonwatch.sh — stale UVO path must invoke yarn with non-watch flags (no hang)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 - "$TMP" "$SCRIPTS" << 'PY'
import json, os, subprocess, sys, time

tmp, scripts = sys.argv[1:3]
fake_bin = os.path.join(tmp, "fake-bin")
os.makedirs(fake_bin, exist_ok=True)
args_log = os.path.join(tmp, "yarn-args.log")

# Fake yarn: record argv; if --watchAll=false missing, sleep (would hang agents).
yarn_path = os.path.join(fake_bin, "yarn")
with open(yarn_path, "w") as f:
    f.write(
        f"""#!/bin/bash
printf '%s\\n' "$@" >> '{args_log}'
if [[ " $* " != *" --watchAll=false "* ]]; then
  echo "FAKE_YARN: missing --watchAll=false — would hang" >&2
  sleep 120
  exit 99
fi
exit 0
"""
    )
os.chmod(yarn_path, 0o755)

subprocess.run(["git", "init", tmp], capture_output=True, check=True)
subprocess.run(["git", "-C", tmp, "config", "user.email", "t@t.com"], check=True)
subprocess.run(["git", "-C", tmp, "config", "user.name", "t"], check=True)
subprocess.run(["git", "-C", tmp, "checkout", "-b", "main"], capture_output=True, check=True)

task_dir = os.path.join(tmp, "docs", "guazi-flow", "task")
handoff = os.path.join(task_dir, "handoff")
evidence = os.path.join(task_dir, "evidence")
os.makedirs(handoff, exist_ok=True)
os.makedirs(evidence, exist_ok=True)

open(os.path.join(tmp, "package.json"), "w").write(
    '{"scripts":{"test":"echo test","build:beta":"echo build"}}'
)
open(os.path.join(tmp, "yarn.lock"), "w").write("# fake lock\n")
os.makedirs(os.path.join(tmp, "src"), exist_ok=True)
open(os.path.join(tmp, "src", "app.ts"), "w").write("export const a = 1;\n")
subprocess.run(["git", "-C", tmp, "add", "package.json", "yarn.lock", "src", "docs"], check=True)
subprocess.run(["git", "-C", tmp, "commit", "-m", "init"], capture_output=True, check=True)

# Stale UVO (wrong hash) so check_tests actually runs
json.dump(
    {
        "overall": "pass",
        "git_head": "deadbeefdeadbeef",
        "code_subject_hash": "stale",
        "write_set": ["src/"],
        "reference_branch": "main...HEAD",
        "steps": [],
    },
    open(os.path.join(evidence, "verification-oracle.json"), "w"),
    indent=2,
)
json.dump({"write_set": ["src/"]}, open(os.path.join(handoff, "plan.json"), "w"))

env = os.environ.copy()
env["PATH"] = fake_bin + os.pathsep + env.get("PATH", "")
env["GOAL_EVIDENCE_DIR"] = evidence
env["GOAL_SKIP_SCOPE"] = "1"
env["GOAL_SKIP_SECRET"] = "1"
env["GOAL_SKIP_LINT"] = "1"
env["GOAL_SKIP_BUILD"] = "1"
# Must not inherit agent skip flags — we need the test runner path.
env["GOAL_SKIP_TEST"] = "0"
# Explicitly unset pattern so we hit the bare-test branch that previously hung
env.pop("GOAL_TEST_PATTERN", None)
env.pop("CI", None)  # script must set CI=true itself on the yarn invocation

t0 = time.time()
try:
    out = subprocess.check_output(
        [os.path.join(scripts, "verify-review.sh"), task_dir, "src/", "json"],
        env=env,
        text=True,
        timeout=30,
    )
except subprocess.TimeoutExpired:
    sys.exit("FAIL: verify-review hung (>30s) — likely watch mode")
elapsed = time.time() - t0

data = json.loads(out)
assert data["checks"]["test"]["command"] != "skipped", data["checks"]["test"]
assert "--watchAll=false" in data["checks"]["test"]["command"], data["checks"]["test"]
assert "CI=true" in data["checks"]["test"]["command"], data["checks"]["test"]
assert "--forceExit" in data["checks"]["test"]["command"], data["checks"]["test"]
assert os.path.isfile(args_log), "fake yarn was not invoked"
logged = open(args_log).read()
assert "--watchAll=false" in logged, logged
assert "forceExit" in logged or "--forceExit" in logged, logged
assert elapsed < 25, f"too slow: {elapsed}s"
print(f"verify-review non-watch OK ({elapsed:.2f}s)")
PY

echo "test-verify-review-nonwatch passed"
