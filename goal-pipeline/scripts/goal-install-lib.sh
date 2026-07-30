#!/bin/bash
# goal-install-lib.sh — Install channel/ref resolution and git sync (source only).
set -euo pipefail

GOAL_INSTALL_DEFAULT_BRANCH="${GOAL_INSTALL_DEFAULT_BRANCH:-main}"

# shellcheck disable=SC1091
_goal_install_lib_source_paths() {
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=source-goal-install-paths.sh
  source "$lib_dir/source-goal-install-paths.sh"
  _goal_install_paths
}

# Print highest stable SemVer tag from stdin (one tag per line, with or without v prefix).
_goal_semver_pick_stable_tag() {
  local picker
  picker="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/goal-semver-pick.py"
  python3 "$picker"
}

goal_get_pipeline_version_from_repo() {
  local repo_dir="${1:?repo_dir}"
  local vf="$repo_dir/goal-pipeline/VERSION"
  if [[ -f "$vf" ]]; then
    tr -d '[:space:]' <"$vf"
    return 0
  fi
  echo "unknown"
}

goal_repo_has_local_changes() {
  local repo_dir="${1:?}"
  ! git -C "$repo_dir" diff --quiet || ! git -C "$repo_dir" diff --cached --quiet
}

# List remote tags (one name per line). Uses ls-remote if repo missing, else local after fetch.
_goal_list_remote_tags() {
  local repo_url="${1:-}"
  local repo_dir="${2:-}"
  if [[ -n "$repo_dir" && -d "$repo_dir/.git" ]]; then
    git -C "$repo_dir" fetch origin --tags --quiet 2>/dev/null || true
    git -C "$repo_dir" tag -l 'v*' 2>/dev/null || true
    return 0
  fi
  if [[ -n "$repo_url" ]]; then
    git ls-remote --tags "$repo_url" 2>/dev/null | awk '{print $2}' | sed 's|refs/tags/||' | grep -E '^v[0-9]' || true
  fi
}

# Resolve channel + optional user ref → checkout spec on stdout: "branch:main" | "tag:vX.Y.Z" | "commit:SHA"
goal_resolve_checkout_spec() {
  local channel="${1:?channel}"
  local user_ref="${2:-}"
  local repo_url="${3:-}"
  local repo_dir="${4:-}"

  if [[ -n "$user_ref" ]]; then
    channel="pinned"
  fi

  case "$channel" in
    pinned)
      [[ -n "$user_ref" ]] || {
        echo "goal-install: pinned channel requires --ref or GOAL_REF" >&2
        return 1
      }
      if [[ "$user_ref" =~ ^[0-9a-f]{7,40}$ ]]; then
        echo "commit:$user_ref"
      else
        local t="$user_ref"
        [[ "$t" == v* ]] || t="v$t"
        echo "tag:$t"
      fi
      ;;
    latest)
      echo "branch:${GOAL_INSTALL_DEFAULT_BRANCH}"
      ;;
    stable)
      local tag
      tag="$(_goal_list_remote_tags "$repo_url" "$repo_dir" | _goal_semver_pick_stable_tag || true)"
      if [[ -z "$tag" ]]; then
        echo "goal-install: no stable SemVer tag found; fallback to ${GOAL_INSTALL_DEFAULT_BRANCH}" >&2
        echo "branch:${GOAL_INSTALL_DEFAULT_BRANCH}"
      else
        echo "tag:$tag"
      fi
      ;;
    *)
      echo "goal-install: unknown channel: $channel (use stable|latest|pinned)" >&2
      return 1
      ;;
  esac
}

goal_apply_checkout_spec() {
  local repo_dir="${1:?}"
  local spec="${2:?}"
  local kind="${spec%%:*}"
  local ref="${spec#*:}"

  case "$kind" in
    branch)
      git -C "$repo_dir" fetch origin "$ref" --quiet
      git -C "$repo_dir" checkout -B "$ref" "origin/$ref" --quiet 2>/dev/null || {
        git -C "$repo_dir" checkout "$ref" --quiet
        git -C "$repo_dir" pull --ff-only origin "$ref" --quiet
      }
      ;;
    tag)
      git -C "$repo_dir" fetch origin "refs/tags/$ref:refs/tags/$ref" --quiet 2>/dev/null || \
        git -C "$repo_dir" fetch origin --tags --quiet
      git -C "$repo_dir" checkout --detach "refs/tags/$ref" --quiet 2>/dev/null || \
        git -C "$repo_dir" checkout --detach "$ref" --quiet
      ;;
    commit)
      git -C "$repo_dir" fetch origin --quiet
      git -C "$repo_dir" checkout --detach "$ref" --quiet
      ;;
    *)
      echo "goal-install: invalid checkout spec: $spec" >&2
      return 1
      ;;
  esac
}

# Clone if needed, then checkout per channel. Sets GOAL_RESOLVED_* env vars.
goal_sync_repository() {
  local repo_url="${1:?}"
  local repo_dir="${2:?}"
  local channel="${3:-stable}"
  local user_ref="${4:-}"

  mkdir -p "$(dirname "$repo_dir")"
  if [[ ! -d "$repo_dir/.git" ]]; then
    git clone "$repo_url" "$repo_dir" --quiet
  fi

  if goal_repo_has_local_changes "$repo_dir"; then
    echo "goal-install: repository has local changes; skip git sync ($repo_dir)" >&2
  else
    local spec
    spec="$(goal_resolve_checkout_spec "$channel" "$user_ref" "$repo_url" "$repo_dir")"
    goal_apply_checkout_spec "$repo_dir" "$spec"
    export GOAL_RESOLVED_CHECKOUT_SPEC="$spec"
  fi

  local resolved_ref resolved_commit git_tag
  resolved_commit="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || echo unknown)"
  resolved_ref="$(git -C "$repo_dir" describe --tags --exact-match 2>/dev/null || true)"
  if [[ -z "$resolved_ref" ]]; then
    resolved_ref="$(git -C "$repo_dir" symbolic-ref -q --short HEAD 2>/dev/null || echo "$resolved_commit")"
  fi
  git_tag="$(git -C "$repo_dir" describe --tags --exact-match 2>/dev/null || true)"

  export GOAL_RESOLVED_REF="$resolved_ref"
  export GOAL_RESOLVED_COMMIT="$resolved_commit"
  export GOAL_RESOLVED_GIT_TAG="$git_tag"
}

goal_read_install_config() {
  local cfg="${GOAL_STATE_HOME:?}/config.json"
  GOAL_INSTALL_CHANNEL="${GOAL_INSTALL_CHANNEL:-}"
  GOAL_INSTALL_REF="${GOAL_INSTALL_REF:-}"
  if [[ ! -f "$cfg" ]]; then
    GOAL_INSTALL_CHANNEL="${GOAL_INSTALL_CHANNEL:-stable}"
    GOAL_INSTALL_REF="${GOAL_INSTALL_REF:-}"
    export GOAL_INSTALL_CHANNEL GOAL_INSTALL_REF
    return 0
  fi
  eval "$(python3 - "$cfg" <<'PY'
import json, sys, os
path = sys.argv[1]
ch = os.environ.get("GOAL_CHANNEL", "")
ref = os.environ.get("GOAL_REF", "")
try:
    cfg = json.load(open(path, encoding="utf-8"))
except Exception:
    cfg = {}
inst = cfg.get("install") or {}
if not ch:
    ch = inst.get("channel") or "stable"
if not ref:
    ref = inst.get("ref") or ""
print(f'GOAL_INSTALL_CHANNEL={json.dumps(ch)}')
print(f'GOAL_INSTALL_REF={json.dumps(ref)}')
PY
)"
  export GOAL_INSTALL_CHANNEL GOAL_INSTALL_REF
}

goal_write_install_config() {
  local channel="${1:?}"
  local ref="${2:-}"
  local resolved_ref="${3:-}"
  local resolved_commit="${4:-}"
  local cfg="${GOAL_STATE_HOME:?}/config.json"
  mkdir -p "$(dirname "$cfg")"
  python3 - "$cfg" "$channel" "$ref" "$resolved_ref" "$resolved_commit" "${GOAL_INSTALL_DEFAULT_BRANCH}" <<'PY'
import json, sys
from datetime import datetime, timezone
path, channel, ref, resolved_ref, resolved_commit, default_branch = sys.argv[1:7]
try:
    cfg = json.load(open(path, encoding="utf-8"))
except Exception:
    cfg = {"version": 1}
inst = cfg.setdefault("install", {})
inst["channel"] = channel
inst["ref"] = ref
inst["resolved_ref"] = resolved_ref
inst["resolved_commit"] = resolved_commit
inst["default_branch"] = default_branch
inst["installed_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
}

goal_normalize_channel_ref() {
  local channel="${GOAL_CHANNEL:-${GOAL_INSTALL_CHANNEL:-stable}}"
  local ref="${GOAL_REF:-${GOAL_INSTALL_REF:-}}"
  if [[ -n "$ref" && "$channel" != "pinned" ]]; then
    channel="pinned"
  fi
  if [[ -z "$ref" && "$channel" == "pinned" ]]; then
    echo "goal-install: pinned channel requires --ref or GOAL_REF" >&2
    return 1
  fi
  export GOAL_INSTALL_CHANNEL="$channel"
  export GOAL_INSTALL_REF="$ref"
}

goal_print_install_status() {
  _goal_install_lib_source_paths
  goal_read_install_config
  local repo_dir="$GOAL_PIPELINE_REPO"
  echo "GOAL_HOME:          $GOAL_HOME"
  echo "GOAL_PIPELINE_REPO: $repo_dir"
  echo "GOAL_STATE_HOME:    $GOAL_STATE_HOME"
  echo "install.channel:    ${GOAL_INSTALL_CHANNEL:-?}"
  echo "install.ref:        ${GOAL_INSTALL_REF:-}"
  if [[ -d "$repo_dir/.git" ]]; then
    echo "repository.head:    $(git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null || echo '?')"
    echo "repository.describe: $(git -C "$repo_dir" describe --tags --always 2>/dev/null || echo '?')"
  else
    echo "repository:         (not cloned)"
  fi
  if [[ -f "$GOAL_STATE_HOME/VERSION" ]]; then
    python3 - "$GOAL_STATE_HOME/VERSION" <<'PY'
import json, sys
try:
    v = json.load(open(sys.argv[1]))
    for k in ("goal_pipeline_version", "install_channel", "git_tag", "git_rev", "installed_at"):
        if v.get(k):
            print(f"VERSION.{k}: {v[k]}")
except Exception as e:
    print(f"VERSION: (unreadable: {e})")
PY
  fi
}

# Called from sync-install-repo.sh when syncing from origin (not --from-dev).
goal_sync_git_from_install_config() {
  local repo_dir="${1:?}"
  local repo_url="${2:-}"
  _goal_install_lib_source_paths
  goal_read_install_config
  goal_normalize_channel_ref || return 0
  if goal_repo_has_local_changes "$repo_dir"; then
    echo "sync-install-repo: skip git sync — local changes in $repo_dir" >&2
    return 0
  fi
  if [[ -z "$repo_url" ]]; then
    repo_url="$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)"
  fi
  goal_sync_repository "$repo_url" "$repo_dir" "$GOAL_INSTALL_CHANNEL" "$GOAL_INSTALL_REF"
  goal_write_install_config "$GOAL_INSTALL_CHANNEL" "$GOAL_INSTALL_REF" \
    "${GOAL_RESOLVED_REF:-}" "${GOAL_RESOLVED_COMMIT:-}"
}
