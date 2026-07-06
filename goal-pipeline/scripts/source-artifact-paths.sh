#!/bin/bash
# source-artifact-paths.sh — Load Tier-G / Tier-R paths into current shell
# Usage: source source-artifact-paths.sh --task-dir <path> [--state-file PATH] [--project-root PATH]

_ARTIFACT_RESOLVER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve-artifact-paths.py"
_ARTIFACT_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir|--state-file|--project-root)
      _ARTIFACT_ARGS+=("$1" "$2")
      shift 2
      ;;
    *) shift ;;
  esac
done

if [[ ! -f "$_ARTIFACT_RESOLVER" ]]; then
  echo "source-artifact-paths: resolver not found: $_ARTIFACT_RESOLVER" >&2
  return 1 2>/dev/null || exit 1
fi

eval "$(python3 "$_ARTIFACT_RESOLVER" "${_ARTIFACT_ARGS[@]}" --format shell)"
