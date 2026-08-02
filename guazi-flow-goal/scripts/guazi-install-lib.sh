#!/bin/bash
# guazi-install-lib.sh — Deploy guazi runtime bundle to GUAZI_STATE_HOME (v1.4)
set -euo pipefail

_guazi_deploy_runtime() {
  local source_root="$1"
  local state_home="$2"
  local guazi_scripts="$3"

  local gp_scripts="$source_root/goal-pipeline/scripts"
  [[ -d "$gp_scripts" ]] || {
    echo "guazi-install: goal-pipeline/scripts missing at $gp_scripts" >&2
    return 1
  }

  mkdir -p "$state_home/projects" "$state_home/archive" "$state_home/scripts/gate-lib" "$state_home/references" "$state_home/kernel" "$state_home/schemas"

  shopt -s nullglob
  local deployed=0
  local skip_re
  skip_re='^(gate-goal-stage|goal-pipeline-kernel|goal-stage-driver|gf-stage-driver|goal-pipeline-stop-hook|goal-pipeline-session-start-hook|goal-pipeline-doctor|deploy-skills|sync-install-repo|goal-install|goal-install-lib|source-goal-install-paths|goal-env-bootstrap)\.sh$'
  for src in "$gp_scripts"/*.sh "$gp_scripts"/*.py "$gp_scripts"/check-consistency \
    "$gp_scripts"/detect-review-channels "$gp_scripts"/detect-platform; do
    [[ -f "$src" ]] || continue
    local base
    base="$(basename "$src")"
    [[ "$base" =~ $skip_re ]] && continue
    install -m 0755 "$src" "$state_home/scripts/$base"
    deployed=$((deployed + 1))
  done
  shopt -u nullglob

  # guazi-owned gate + advance + paths (overlay)
  install -m 0755 "$guazi_scripts/guazi-gate-stage.sh" "$state_home/scripts/guazi-gate-stage.sh"
  install -m 0755 "$guazi_scripts/guazi-advance-stage.sh" "$state_home/scripts/guazi-advance-stage.sh"
  install -m 0755 "$guazi_scripts/resolve-guazi-state-home.sh" "$state_home/scripts/resolve-guazi-state-home.sh"
  install -m 0755 "$guazi_scripts/guazi-env-bootstrap.sh" "$state_home/scripts/guazi-env-bootstrap.sh"
  install -m 0755 "$guazi_scripts/source-guazi-install-paths.sh" "$state_home/scripts/source-guazi-install-paths.sh"
  install -m 0755 "$guazi_scripts/goal-env-bootstrap-compat.sh" "$state_home/scripts/goal-env-bootstrap.sh"
  install -m 0755 "$guazi_scripts/source-goal-install-paths-compat.sh" "$state_home/scripts/source-goal-install-paths.sh"
  install -m 0755 "$guazi_scripts/refresh-handoffs-after-index.sh" "$state_home/scripts/refresh-handoffs-after-index.sh"
  printf 'GUAZI_PIPELINE_REPO=%s\n' "$source_root" >"$state_home/guazi-install-meta.env"
  rm -rf "$state_home/scripts/gate-lib"
  mkdir -p "$state_home/scripts/gate-lib"
  rsync -aL "$guazi_scripts/gate-lib/" "$state_home/scripts/gate-lib/"

  local kernel_src="$source_root/goal-pipeline/kernel"
  if [[ -d "$kernel_src" ]]; then
    rm -rf "$state_home/kernel"
    mkdir -p "$state_home/kernel"
    cp -R "$kernel_src/." "$state_home/kernel/"
  fi
  local guazi_merge="$source_root/guazi-flow-goal/kernel/review/merge.py"
  if [[ -f "$guazi_merge" ]]; then
    install -m 0644 "$guazi_merge" "$state_home/kernel/review/merge.py"
  fi

  local schemas_src="$source_root/goal-pipeline/schemas"
  if [[ -d "$schemas_src" ]]; then
    rm -rf "$state_home/schemas"
    mkdir -p "$state_home/schemas"
    cp -R "$schemas_src/." "$state_home/schemas/"
  fi

  local gz_schema="$source_root/guazi-flow-goal/references/guazi-flow-artifact-schema"
  [[ -d "$gz_schema" ]] || gz_schema="$source_root/goal-pipeline/references/guazi-flow-artifact-schema"
  if [[ -d "$gz_schema" ]]; then
    rm -rf "$state_home/references/guazi-flow-artifact-schema"
    mkdir -p "$state_home/references/guazi-flow-artifact-schema"
    cp -R "$gz_schema/." "$state_home/references/guazi-flow-artifact-schema/"
  fi

  local goal_schema="$source_root/goal-pipeline/references/goal-artifact-schema"
  if [[ -d "$goal_schema" ]]; then
    mkdir -p "$state_home/references/goal-artifact-schema"
    cp -R "$goal_schema/." "$state_home/references/goal-artifact-schema/"
  fi

  local profiles_src="$source_root/goal-pipeline/references/profiles"
  if [[ -d "$profiles_src" ]]; then
    rm -rf "$state_home/references/profiles"
    mkdir -p "$state_home/references/profiles"
    cp -R "$profiles_src/." "$state_home/references/profiles/"
  fi

  local ref_dst="$state_home/references"
  for ref in failure-codes.json failure-code-dictionary.md four-planes-checklist.json \
             plan-before-code.md plan-quality-rules.json index-lite-protocol.md \
             response-playbook.md measure-field-template.json; do
    [[ -f "$source_root/goal-pipeline/references/$ref" ]] || continue
    cp "$source_root/goal-pipeline/references/$ref" "$ref_dst/$ref"
  done
  for ref in "$source_root/guazi-flow-goal/references/"*.md; do
    [[ -f "$ref" ]] || continue
    cp "$ref" "$ref_dst/$(basename "$ref")"
  done

  # review-kernel resolve helper (read-only shared service)
  if [[ -f "$gp_scripts/resolve-review-kernel-home.sh" ]]; then
    install -m 0755 "$gp_scripts/resolve-review-kernel-home.sh" "$state_home/scripts/resolve-review-kernel-home.sh"
  fi

  echo "guazi-install: deployed $deployed helper scripts + guazi gate to $state_home"
}
