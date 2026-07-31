#!/bin/bash
# Regression: extract_verification_hints must not set test_pattern to "=" from --testPathPattern=
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HASH_PY="$SCRIPT_DIR/../../index_contract_hash.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/index.md" <<'MD'
| C01 | x | `CI=true yarn test --testPathPattern=suspectedDealerCollectionApproval` |
MD
OUT=$(python3 -c "
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location('ich', sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(json.dumps(mod.extract_verification_hints(open(sys.argv[2], encoding='utf-8').read())))
" "$HASH_PY" "$TMP/index.md")
TP=$(echo "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('test_pattern',''))")
[[ "$TP" == "suspectedDealerCollectionApproval" ]] || {
  echo "FAIL: expected suspectedDealerCollectionApproval got: $TP (full=$OUT)" >&2
  exit 1
}
echo "OK test-extract-verification-hints"
