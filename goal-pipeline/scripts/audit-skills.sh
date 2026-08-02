#!/bin/bash
# audit-skills.sh — Tier A/B structure lint (writing-great-skills gate, v1.4)
# Usage: audit-skills.sh [--tier a|b|all] [--repo-root <path>]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TIER="all"
FAIL=0
WARN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tier) TIER="$2"; shift 2 ;;
    --repo-root) REPO_ROOT="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--tier a|b|all] [--repo-root <path>]"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

fail() { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }
warn() { echo "WARN: $1" >&2; WARN=$((WARN + 1)); }
pass() { echo "PASS: $1"; }

tier_a_files() {
  echo "$REPO_ROOT/goal-pipeline/SKILL.md"
  find "$REPO_ROOT/goal-pipeline/stages" -name 'SKILL.md' 2>/dev/null | sort
  echo "$REPO_ROOT/guazi-flow-goal/SKILL.md"
  local rk_readme="$REPO_ROOT/shared/review-kernel/README.md"
  [[ -f "$rk_readme" ]] && echo "$rk_readme"
}

audit_skill_file() {
  local f="$1"
  local label="${f#$REPO_ROOT/}"
  local file_fail=0
  [[ -f "$f" ]] || { fail "$label — file missing"; return; }

  local body
  body="$(sed -n '/^---$/,/^---$/d; p' "$f")"

  local is_rk_readme=false
  [[ "$label" == "shared/review-kernel/README.md" ]] && is_rk_readme=true

  if [[ "$is_rk_readme" != true ]]; then
    if ! head -n 30 "$f" | grep -q '^description:'; then
      fail "$label — missing YAML description"
      file_fail=1
    fi

    if ! echo "$body" | grep -qiE '^##[[:space:]]+NEVER'; then
      fail "$label — missing ## NEVER section"
      file_fail=1
    fi

    local never_count
    never_count=$(echo "$body" | awk '
      /^##[[:space:]]+NEVER/ { in_never=1; next }
      /^##[[:space:]]+/ { in_never=0 }
      in_never && /^-[[:space:]]+(\*\*)?NEVER/ { c++ }
      END { print c+0 }
    ')
    if [[ "$never_count" -eq 0 ]]; then
      fail "$label — no NEVER bullets"
      file_fail=1
    elif [[ "$never_count" -gt 7 ]]; then
      warn "$label — NEVER count $never_count (>7 recommended)"
    fi
  else
    if ! grep -q 'REVIEW_KERNEL_HOME' "$f"; then
      fail "$label — missing REVIEW_KERNEL_HOME documentation"
      file_fail=1
    fi
  fi

  if [[ "$label" == "goal-pipeline/SKILL.md" ]]; then
    if grep -qiE 'pipeline_track=guazi|guazi adapter|guazi-flow-plan|guazi-flow-implement' "$f"; then
      fail "$label — v1.4 boundary: contains guazi references"
      file_fail=1
    fi
  fi

  if [[ "$label" == "guazi-flow-goal/SKILL.md" ]]; then
    if grep -vE 'NEVER|禁止|不依赖|fallback|Do NOT' "$f" | grep -qE 'goal-pipeline/scripts|goal-pipeline-kernel|goal-advance-stage'; then
      fail "$label — v1.4 boundary: depends on goal-pipeline scripts"
      file_fail=1
    fi
    if ! grep -q 'REVIEW_KERNEL_HOME' "$f"; then
      fail "$label — missing REVIEW_KERNEL_HOME"
      file_fail=1
    fi
    if ! grep -q 'GUAZI_STATE_HOME' "$f"; then
      fail "$label — missing GUAZI_STATE_HOME"
      file_fail=1
    fi
  fi

  if [[ "$file_fail" -eq 0 ]]; then
    pass "$label"
  fi
}

echo "=== audit-skills (tier=$TIER) repo=$REPO_ROOT ==="

if [[ "$TIER" == "a" || "$TIER" == "all" ]]; then
  echo "--- Tier A ---"
  while IFS= read -r f; do
    [[ -n "$f" ]] && audit_skill_file "$f"
  done < <(tier_a_files)
fi

if [[ "$TIER" == "b" || "$TIER" == "all" ]]; then
  echo "--- Tier B (goal-engineering) ---"
  find "$REPO_ROOT/goal-pipeline/skills/goal-engineering" -name 'SKILL.md' 2>/dev/null | sort | while read -r f; do
    audit_skill_file "$f"
  done
fi

echo "=== summary: fail=$FAIL warn=$WARN ==="
[[ "$FAIL" -eq 0 ]]
