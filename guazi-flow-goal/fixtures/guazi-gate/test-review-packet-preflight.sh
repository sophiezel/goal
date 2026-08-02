#!/bin/bash
# test-review-packet-preflight.sh — PKT-01 blocks empty/docs-only diff
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_SCRIPTS:-${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/packet-empty.json" << 'JSON'
{"diff":"","reference_impl_diff":"","changed_files":["docs/guazi-flow/x/index.md"],"integrity":{"ok":true,"errors":[]}}
JSON

cat > "$TMP/uvo-pass.json" << 'JSON'
{"overall":"pass"}
JSON

if python3 "$SCRIPTS/review_packet_preflight.py" --packet "$TMP/packet-empty.json" --uvo "$TMP/uvo-pass.json" 2>/dev/null; then
  echo "expected preflight fail for empty diff"
  exit 1
fi

python3 - "$SCRIPTS/review_packet_preflight.py" << 'PY'
import importlib.util, json, os, sys, tempfile
script_dir = os.path.dirname(os.path.dirname(sys.argv[1]))
spec = importlib.util.spec_from_file_location("preflight", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
pkt = {
    "diff": "diff --git a/src/foo.ts b/src/foo.ts\n" + "+export const x = 1;\n" * 20,
    "diff_source": "reference_branch",
    "integrity": {"ok": True, "errors": []},
}
uvo = os.path.join(tempfile.mkdtemp(), "uvo.json")
json.dump({"overall": "pass"}, open(uvo, "w"))
r = mod.run_preflight(pkt, uvo)
assert r["ok"], r
print("preflight pass OK for src diff")
PY

echo "test-review-packet-preflight passed"
