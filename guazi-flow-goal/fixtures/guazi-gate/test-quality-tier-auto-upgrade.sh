#!/bin/bash
# test-quality-tier-auto-upgrade.sh — security write_set → strict tier
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_SCRIPTS:-${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts}"
MOD="$SCRIPTS/quality_policy_tier.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/index-auth.md" << 'IDX'
# 登录改造
write_set:
- src/pages/auth/login.tsx
- src/utils/token.ts
IDX

cat > "$TMP/index-normal.md" << 'IDX'
# 列表页
write_set:
- src/pages/foo/list.tsx
IDX

python3 - "$MOD" "$TMP/index-auth.md" "$TMP/index-normal.md" << 'PY'
import importlib.util, sys, os
mod_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("qpt", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

auth_text = open(sys.argv[2]).read()
norm_text = open(sys.argv[3]).read()

tier_a, meta_a = mod.resolve_quality_tier(auth_text, {})
assert tier_a == "strict", (tier_a, meta_a)
assert meta_a.get("reason") == "auto_upgrade_security_write_set", meta_a
assert len(meta_a.get("strict_signals") or []) >= 1

tier_n, meta_n = mod.resolve_quality_tier(norm_text, {})
assert tier_n == "standard", (tier_n, meta_n)
print("quality tier auto-upgrade OK")
PY

echo "test-quality-tier-auto-upgrade passed"
