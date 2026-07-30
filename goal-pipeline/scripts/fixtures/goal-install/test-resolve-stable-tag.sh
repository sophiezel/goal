#!/bin/bash
# test-resolve-stable-tag.sh — unit test for stable SemVer tag selection (no network).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../../goal-install-lib.sh"
PICKER="$SCRIPT_DIR/../../goal-semver-pick.py"
# shellcheck disable=SC1091
source "$LIB"

pick() {
  printf '%s\n' "$@" | _goal_semver_pick_stable_tag
}

got="$(pick v1.0.0 v2.0.0 v1.9.9)"
[[ "$got" == "v2.0.0" ]] || { echo "FAIL expected v2.0.0 got $got"; exit 1; }

got="$(pick v3.0.0-rc.1 v3.0.0-beta.1 v2.9.0)"
[[ "$got" == "v2.9.0" ]] || { echo "FAIL prerelease filter got $got"; exit 1; }

got="$(pick v3.1.0 v3.0.10 v3.0.9)"
[[ "$got" == "v3.1.0" ]] || { echo "FAIL semver order got $got"; exit 1; }

got="$(pick v3.0.0-alpha.1 v3.0.0)"
[[ "$got" == "v3.0.0" ]] || { echo "FAIL alpha excluded got $got"; exit 1; }

got="$(printf '%s\n' | python3 "$PICKER" || true)"
[[ -z "$got" ]] || { echo "FAIL expected empty got $got"; exit 1; }

echo "OK test-resolve-stable-tag"
