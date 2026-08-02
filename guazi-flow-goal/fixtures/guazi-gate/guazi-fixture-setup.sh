#!/bin/bash
# guazi-fixture-setup.sh — Deploy guazi runtime for fixture tests (idempotent per shell)
set -euo pipefail

_guazi_fixture_setup() {
  local repo_root="$1"
  local guazi_scripts="$repo_root/guazi-flow-goal/scripts"
  local guazi_root="$repo_root/guazi-flow-goal"
  local cache_root="${GUAZI_FIXTURE_INSTALL:-$repo_root/.cache/guazi-fixture-runtime}"

  if [[ -n "${GUAZI_FIXTURE_STATE_READY:-}" && -x "${GUAZI_STATE_HOME:-}/scripts/guazi-gate-stage.sh" ]]; then
    return 0
  fi

  export GUAZI_INSTALL_TARGET="${cache_root}/guazi"
  export GUAZI_STATE_HOME="${GUAZI_INSTALL_TARGET}/state"
  bash "$repo_root/guazi-flow-goal/scripts/guazi-install.sh" >/dev/null
  export GUAZI_FIXTURE_STATE_READY=1
  export GUAZI_SCRIPTS="$GUAZI_STATE_HOME/scripts"
  export PATH="$GUAZI_SCRIPTS:${PATH:-}"
  export PYTHONPATH="$GUAZI_SCRIPTS:$GUAZI_STATE_HOME/kernel:${PYTHONPATH:-}"

  # Stale symlinks (old mktemp paths) break ../../ fixture imports
  find "$guazi_root" -maxdepth 2 -type l ! -path '*/.git/*' -delete 2>/dev/null || true
  [[ -L "$repo_root/kernel" ]] && rm -f "$repo_root/kernel"

  mkdir -p "$guazi_root/gate-lib"
  ln -sfn "$GUAZI_SCRIPTS/guazi-gate-stage.sh" "$guazi_root/guazi-gate-stage.sh"
  ln -sfn "$GUAZI_SCRIPTS/guazi-advance-stage.sh" "$guazi_root/guazi-advance-stage.sh"
  ln -sfn "$GUAZI_STATE_HOME/kernel" "$repo_root/kernel"

  local f base
  for f in "$GUAZI_SCRIPTS"/*; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"
    case "$base" in
      guazi-install.sh|guazi-install-lib.sh|goal-env-bootstrap.sh|source-goal-install-paths.sh|gate-goal-stage.sh|goal-pipeline-kernel.sh|goal-advance-stage.sh|goal-stage-driver.sh|gf-stage-driver.sh|goal-pipeline-stop-hook.sh|goal-pipeline-session-start-hook.sh|goal-pipeline-doctor.sh|deploy-skills.sh|sync-install-repo.sh) continue ;;
    esac
    ln -sfn "$f" "$guazi_root/$base"
  done
  for f in "$GUAZI_SCRIPTS/gate-lib"/*; do
    [[ -e "$f" ]] || continue
    ln -sfn "$f" "$guazi_root/gate-lib/$(basename "$f")"
  done
  if [[ -d "$GUAZI_STATE_HOME/references" ]]; then
    mkdir -p "$guazi_root/references"
    cp -R "$GUAZI_STATE_HOME/references/." "$guazi_root/references/"
  fi
  local goal_schema="$repo_root/goal-pipeline/references/goal-artifact-schema"
  if [[ -d "$goal_schema" ]]; then
    mkdir -p "$guazi_root/references/goal-artifact-schema"
    cp -R "$goal_schema/." "$guazi_root/references/goal-artifact-schema/"
  fi
}
