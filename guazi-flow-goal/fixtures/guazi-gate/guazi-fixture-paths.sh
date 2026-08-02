#!/bin/bash
# guazi-fixture-paths.sh — Shared SCRIPTS/GUAZI_STATE_HOME for fixture tests
set -euo pipefail

_guazi_fixture_scripts() {
  echo "${GUAZI_STATE_HOME:-${HOME}/.guazi-flow/state}/scripts"
}
