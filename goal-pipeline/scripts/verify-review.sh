#!/bin/bash
# verify-review.sh - 确定性 review 检查 (0 模型调用)
# 检查: 修改范围 | 密钥扫描 | 测试通过 | Lint 通过
# 依赖: bash + git

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UVO_CORE="$SCRIPT_DIR/verification_oracle_core.py"

TASK_DIR="${1:-.}"
WRITE_SET="${2:-}"  # comma-separated file list from unit.md
FORMAT="${3:-json}"

GIT_ROOT=$(git -C "$TASK_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$TASK_DIR")

# === 输出 ===
output_json() {
  python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)))" <<< "$1" 2>/dev/null || echo "$1"
}

# === 1. 范围检查 ===
check_scope() {
  local out_of_scope=()
  local modified_files

  if [ "${GOAL_SKIP_SCOPE:-0}" = "1" ]; then
    echo '{"pass":true,"modified_files":[],"out_of_scope":[],"skipped":true}'
    return
  fi
  
  cd "$GIT_ROOT"
  modified_files=$(git -c core.quotepath=false diff --name-only HEAD 2>/dev/null || echo "")
  
  if [ -z "$modified_files" ]; then
    echo '{"pass":true,"modified_files":[],"out_of_scope":[]}'
    return
  fi
  
  if [ -n "$WRITE_SET" ]; then
    IFS=',' read -ra ALLOWED <<< "$WRITE_SET"
    for f in $modified_files; do
      local allowed=false
      # Ignore guazi-flow docs noise in scope checks
      if [[ "$f" == docs/guazi-flow/* ]]; then
        continue
      fi
      for a in "${ALLOWED[@]}"; do
        # Strip whitespace and normalize /** → /
        a=$(echo "$a" | xargs)
        a="${a%/\*\*}"
        a="${a%/\*\*/}"
        a="${a%/}"
        # Prefix match (directory or file prefix)
        if [[ -z "$a" ]]; then
          continue
        fi
        if [[ "$f" == "$a" || "$f" == "$a"/* ]]; then
          allowed=true
          break
        fi
      done
      if [ "$allowed" = false ]; then
        out_of_scope+=("$f")
      fi
    done
  fi
  
  if [ ${#out_of_scope[@]} -gt 0 ]; then
    printf '{"pass":false,"modified_files":%s,"out_of_scope":%s}\n' \
      "$(printf '%s\n' "$modified_files" | python3 -c 'import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))' 2>/dev/null || echo '[]')" \
      "$(printf '%s\n' "${out_of_scope[@]}" | python3 -c 'import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))' 2>/dev/null || echo '[]')"
  else
    printf '{"pass":true,"modified_files":%s,"out_of_scope":[]}\n' \
      "$(printf '%s\n' "$modified_files" | python3 -c 'import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))' 2>/dev/null || echo '[]')"
  fi
}

# === 2. 密钥扫描 ===
check_secrets() {
  local findings=()

  if [ "${GOAL_SKIP_SECRET:-0}" = "1" ]; then
    echo '{"pass":true,"findings":[],"skipped":true}'
    return
  fi
  
  cd "$GIT_ROOT"
  local diff_content
  diff_content=$(git -c core.quotepath=false diff HEAD 2>/dev/null || echo "")
  
  # 常见密钥模式
  local patterns=(
    "API_KEY[=:]\s*['\"]?\w{8,}"
    "api_key[=:]\s*['\"]?\w{8,}"
    "password[=:]\s*['\"][^'\"]{3,}['\"]"
    "token[=:]\s*['\"][^'\"]{8,}['\"]"
    "secret[=:]\s*['\"][^'\"]{8,}['\"]"
    "sk-[a-zA-Z0-9]{20,}"
    "AKIA[0-9A-Z]{16}"
    "ghp_[a-zA-Z0-9]{36}"
  )
  
  for pattern in "${patterns[@]}"; do
    local matches
    matches=$(echo "$diff_content" | grep -i -E "$pattern" | grep -v "^[-]" | grep -v "^#\|^//\|^/\*\|\*" || true)
    if [ -n "$matches" ]; then
      while IFS= read -r line; do
        if [ -n "$line" ]; then
          findings+=("suspect line: ${line:0:80}...")
        fi
      done <<< "$matches"
    fi
  done
  
  if [ ${#findings[@]} -gt 0 ]; then
    printf '{"pass":false,"findings":%s}\n' \
      "$(printf '%s\n' "${findings[@]}" | python3 -c 'import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))' 2>/dev/null || echo '[]')"
  else
    echo '{"pass":true,"findings":[]}'
  fi
}

# === UVO freshness (skip duplicate test/build when implement gate already passed) ===
uvo_attestation_skip_heavy() {
  if [ "${GOAL_SKIP_TEST:-0}" = "1" ] && [ "${GOAL_SKIP_BUILD:-0}" = "1" ]; then
    echo "true"
    return
  fi
  if [ ! -f "$UVO_CORE" ]; then
    echo "false"
    return
  fi
  local uvo_path=""
  for cand in "${GOAL_EVIDENCE_DIR:-}/verification-oracle.json" "$TASK_DIR/evidence/verification-oracle.json"; do
    if [ -f "$cand" ]; then
      uvo_path="$cand"
      break
    fi
  done
  if [ -z "$uvo_path" ]; then
    echo "false"
    return
  fi
  python3 - "$uvo_path" "$GIT_ROOT" "$TASK_DIR" "$UVO_CORE" << 'PYUVO' 2>/dev/null || echo "false"
import importlib.util, os, sys
uvo_path, git_root, task_dir, core_path = sys.argv[1:5]
spec = importlib.util.spec_from_file_location("verification_oracle_core", core_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
fresh = mod.check_freshness(uvo_path, git_root, task_dir)
print("true" if fresh.get("fresh") and (fresh.get("evidence") or {}).get("overall") == "pass" else "false")
PYUVO
}

# === 3. 测试检查 ===
check_tests() {
  cd "$GIT_ROOT"

  if [ "${GOAL_SKIP_TEST:-0}" = "1" ]; then
    echo '{"pass":true,"command":"skipped","output":"GOAL_SKIP_TEST=1"}'
    return
  fi

  if [ "$(uvo_attestation_skip_heavy)" = "true" ]; then
    echo '{"pass":true,"command":"skipped","output":"UVO fresh pass — test attested by verification-oracle.json"}'
    return
  fi
  
  if [ -f "package.json" ]; then
    local has_test pkg_mgr test_cmd
    has_test=$(node -e "try{const p=require('./package.json');console.log(p.scripts&&p.scripts.test?'yes':'no')}catch(e){console.log('no')}" 2>/dev/null || echo "no")
    if [ "$has_test" = "yes" ]; then
      if [ -f "yarn.lock" ] && command -v yarn >/dev/null 2>&1; then
        pkg_mgr="yarn"
        test_cmd="yarn test"
      elif [ -f "pnpm-lock.yaml" ] && command -v pnpm >/dev/null 2>&1; then
        pkg_mgr="pnpm"
        test_cmd="pnpm test"
      else
        pkg_mgr="npm"
        test_cmd="npm test"
      fi
      if [ -n "${GOAL_TEST_PATTERN:-}" ]; then
        export CI="${CI:-true}"
        if [ "$pkg_mgr" = "yarn" ]; then
          test_cmd="CI=true yarn test --testPathPattern=$GOAL_TEST_PATTERN --watchAll=false"
          if CI=true yarn test --testPathPattern="$GOAL_TEST_PATTERN" --watchAll=false >/dev/null 2>&1; then
            TEST_CMD="$test_cmd" python3 -c "import json,os; print(json.dumps({'pass':True,'command':os.environ['TEST_CMD'],'output':'all passing'}))"
          else
            TEST_CMD="$test_cmd" python3 -c "import json,os; print(json.dumps({'pass':False,'command':os.environ['TEST_CMD'],'output':'tests failed'}))"
          fi
        elif [ "$pkg_mgr" = "pnpm" ]; then
          test_cmd="CI=true pnpm test --testPathPattern=$GOAL_TEST_PATTERN --watchAll=false"
          if CI=true pnpm test --testPathPattern="$GOAL_TEST_PATTERN" --watchAll=false >/dev/null 2>&1; then
            TEST_CMD="$test_cmd" python3 -c "import json,os; print(json.dumps({'pass':True,'command':os.environ['TEST_CMD'],'output':'all passing'}))"
          else
            TEST_CMD="$test_cmd" python3 -c "import json,os; print(json.dumps({'pass':False,'command':os.environ['TEST_CMD'],'output':'tests failed'}))"
          fi
        else
          test_cmd="npm test -- --testPathPattern=$GOAL_TEST_PATTERN --watchAll=false"
          if CI=true npm test -- --testPathPattern="$GOAL_TEST_PATTERN" --watchAll=false >/dev/null 2>&1; then
            TEST_CMD="$test_cmd" python3 -c "import json,os; print(json.dumps({'pass':True,'command':os.environ['TEST_CMD'],'output':'all passing'}))"
          else
            TEST_CMD="$test_cmd" python3 -c "import json,os; print(json.dumps({'pass':False,'command':os.environ['TEST_CMD'],'output':'tests failed'}))"
          fi
        fi
      else
        if [ -n "${CI:-}" ]; then
          export CI="${CI:-true}"
        fi
        if [ "$pkg_mgr" = "yarn" ]; then
          if yarn test >/dev/null 2>&1; then
            TEST_CMD="$test_cmd" python3 -c "import json,os; print(json.dumps({'pass':True,'command':os.environ['TEST_CMD'],'output':'all passing'}))"
          else
            TEST_CMD="$test_cmd" python3 -c "import json,os; print(json.dumps({'pass':False,'command':os.environ['TEST_CMD'],'output':'tests failed'}))"
          fi
        elif [ "$pkg_mgr" = "pnpm" ]; then
          if pnpm test >/dev/null 2>&1; then
            TEST_CMD="$test_cmd" python3 -c "import json,os; print(json.dumps({'pass':True,'command':os.environ['TEST_CMD'],'output':'all passing'}))"
          else
            TEST_CMD="$test_cmd" python3 -c "import json,os; print(json.dumps({'pass':False,'command':os.environ['TEST_CMD'],'output':'tests failed'}))"
          fi
        else
          if npm test >/dev/null 2>&1; then
            TEST_CMD="$test_cmd" python3 -c "import json,os; print(json.dumps({'pass':True,'command':os.environ['TEST_CMD'],'output':'all passing'}))"
          else
            TEST_CMD="$test_cmd" python3 -c "import json,os; print(json.dumps({'pass':False,'command':os.environ['TEST_CMD'],'output':'tests failed'}))"
          fi
        fi
      fi
    else
      echo '{"pass":true,"command":"skipped","output":"no test script in package.json"}'
    fi
  elif [ -f "go.mod" ]; then
    if go test ./... 2>/dev/null; then
      echo '{"pass":true,"command":"go test","output":"all passing"}'
    else
      echo '{"pass":false,"command":"go test","output":"tests failed"}'
    fi
  else
    echo '{"pass":true,"command":"not_found","output":"no test runner detected, skipping"}'
  fi
}

# === 4. Lint 检查 ===
check_lint() {
  cd "$GIT_ROOT"

  if [ "${GOAL_SKIP_LINT:-0}" = "1" ]; then
    echo '{"pass":true,"command":"skipped","output":"GOAL_SKIP_LINT=1"}'
    return
  fi
  
  local has_lint=false
  for cfg in .eslintrc.js .eslintrc.cjs .eslintrc.json .eslintrc.yaml .eslintrc.yml .eslintrc; do
    [ -f "$cfg" ] && has_lint=true && break
  done
  grep -q '"eslint"' package.json 2>/dev/null && has_lint=true
  
  if [ "$has_lint" = true ]; then
    local lint_files
    lint_files=$(git -c core.quotepath=false diff --name-only HEAD 2>/dev/null | grep -E '\.(ts|tsx|js|jsx|vue)$' || true)
    if [ -z "$lint_files" ]; then
      echo '{"pass":true,"command":"skipped","output":"no lintable files in diff"}'
    elif npx eslint --quiet $lint_files >/dev/null 2>&1; then
      echo '{"pass":true,"command":"eslint","output":"clean"}'
    else
      local lint_out
      lint_out=$(npx eslint --quiet $lint_files 2>&1 | head -20 || true)
      LINT_OUT="$lint_out" python3 -c "import json,os; print(json.dumps({'pass':False,'command':'eslint','output':os.environ.get('LINT_OUT','')[:500]}))"
    fi
  else
    echo '{"pass":true,"command":"skipped","output":"no eslint config detected"}'
  fi
}

# === 5. Build 检查 (V02 / yarn build:beta) ===
check_build() {
  cd "$GIT_ROOT"
  local build_cmd="${GOAL_BUILD_COMMAND:-}"
  local need_build=false

  # Detect from env, index acceptance matrix, or package.json scripts
  if [ -n "$build_cmd" ]; then
    need_build=true
  elif [ -f "$TASK_DIR/index.md" ] && grep -qE 'yarn[[:space:]]+build:beta|V0[0-9].*build|build.*beta' "$TASK_DIR/index.md" 2>/dev/null; then
    need_build=true
    if grep -q 'yarn build:beta' "$TASK_DIR/index.md" 2>/dev/null; then
      build_cmd="CI= yarn build:beta"
    else
      build_cmd="CI= yarn build"
    fi
  fi

  # Skip when GOAL_SKIP_BUILD=1 (fixtures / CI without node_modules)
  if [ "${GOAL_SKIP_BUILD:-0}" = "1" ]; then
    echo '{"pass":true,"command":"skipped","output":"GOAL_SKIP_BUILD=1"}'
    return
  fi

  if [ "$(uvo_attestation_skip_heavy)" = "true" ]; then
    echo '{"pass":true,"command":"skipped","output":"UVO fresh pass — build attested by verification-oracle.json"}'
    return
  fi

  if [ "$need_build" != "true" ]; then
    echo '{"pass":true,"command":"skipped","output":"no build requirement detected"}'
    return
  fi

  if [ ! -f "package.json" ]; then
    echo '{"pass":true,"command":"skipped","output":"no package.json"}'
    return
  fi

  # Prefer yarn when lockfile present
  local ok=false
  local out=""
  if [ -f "yarn.lock" ] && command -v yarn >/dev/null 2>&1; then
    if [[ "$build_cmd" == CI=\ * ]]; then
      out=$(eval "$build_cmd" 2>&1 | tail -30) && ok=true || ok=false
    else
      out=$(CI= yarn build:beta 2>&1 | tail -30) && ok=true || ok=false
      build_cmd="CI= yarn build:beta"
    fi
  elif command -v npm >/dev/null 2>&1; then
    out=$(CI= npm run build 2>&1 | tail -30) && ok=true || ok=false
    build_cmd="CI= npm run build"
  else
    echo '{"pass":true,"command":"skipped","output":"no yarn/npm"}'
    return
  fi

  if [ "$ok" = true ]; then
    BUILD_CMD="$build_cmd" python3 -c "import json,os; print(json.dumps({'pass':True,'command':os.environ['BUILD_CMD'],'output':'build ok'}))"
  else
    BUILD_CMD="$build_cmd" BUILD_OUT="$out" python3 -c "import json,os; print(json.dumps({'pass':False,'command':os.environ['BUILD_CMD'],'output':os.environ.get('BUILD_OUT','')[:500]}))"
  fi
}

# === Main ===
main() {
  # Load verification hints from nearby plan.json if present
  local plan_json=""
  for cand in "$TASK_DIR/../handoff/plan.json" "$TASK_DIR/handoff/plan.json"; do
    [[ -f "$cand" ]] && plan_json="$cand" && break
  done
  # Also try goal-state via env
  if [[ -z "$plan_json" && -n "${HANDOFF_DIR:-}" && -f "${HANDOFF_DIR}/plan.json" ]]; then
    plan_json="${HANDOFF_DIR}/plan.json"
  fi
  if [[ -n "$plan_json" ]]; then
    eval "$(python3 - "$plan_json" << 'PYLOAD' || true
import json, sys, os
plan = json.load(open(sys.argv[1], encoding="utf-8"))
v = plan.get("verification") or {}
if v.get("test_pattern") and not os.environ.get("GOAL_TEST_PATTERN"):
    print("export GOAL_TEST_PATTERN=%s" % json.dumps(v["test_pattern"]))
if v.get("build_command") and not os.environ.get("GOAL_BUILD_COMMAND"):
    print("export GOAL_BUILD_COMMAND=%s" % json.dumps(v["build_command"]))
PYLOAD
)"
  fi

  local scope_result secret_result test_result lint_result build_result
  scope_result=$(check_scope)
  secret_result=$(check_secrets)
  test_result=$(check_tests)
  lint_result=$(check_lint)
  build_result=$(check_build)
  
  local scope_pass secret_pass test_pass lint_pass build_pass
  scope_pass=$(echo "$scope_result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pass',False))" 2>/dev/null || echo "false")
  secret_pass=$(echo "$secret_result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pass',False))" 2>/dev/null || echo "false")
  test_pass=$(echo "$test_result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pass',False))" 2>/dev/null || echo "false")
  lint_pass=$(echo "$lint_result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pass',False))" 2>/dev/null || echo "false")
  build_pass=$(echo "$build_result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pass',False))" 2>/dev/null || echo "false")
  
  local overall="pass"
  if [ "$scope_pass" != "True" ] || [ "$secret_pass" != "True" ] || [ "$test_pass" != "True" ] || [ "$lint_pass" != "True" ] || [ "$build_pass" != "True" ]; then
    overall="not_pass"
  fi
  
  if [ "$FORMAT" = "json" ]; then
    export VR_SCOPE="$scope_result" VR_SECRET="$secret_result" VR_TEST="$test_result" VR_LINT="$lint_result" VR_BUILD="$build_result" VR_OVERALL="$overall"
    python3 << 'PYJSON'
import json, os, sys

def load(name):
    raw = os.environ.get(name, "{}")
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"pass": False, "output": raw[:500], "parse_error": True}

checks = {
    "scope": load("VR_SCOPE"),
    "secret": load("VR_SECRET"),
    "test": load("VR_TEST"),
    "lint": load("VR_LINT"),
    "build": load("VR_BUILD"),
}
overall = os.environ.get("VR_OVERALL", "not_pass")
print(json.dumps({"overall": overall, "checks": checks}, ensure_ascii=False))
PYJSON
  else
    echo "=== Review Checks ==="
    echo "Scope:  $([ "$scope_pass" = "True" ] && echo '✅' || echo '❌') (files outside write_set: $(echo "$scope_result" | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d.get('out_of_scope',[])))" 2>/dev/null || echo '?'))"
    echo "Secret: $([ "$secret_pass" = "True" ] && echo '✅' || echo '❌') (findings: $(echo "$secret_result" | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d.get('findings',[])))" 2>/dev/null || echo '?'))"
    echo "Tests:  $([ "$test_pass" = "True" ] && echo '✅' || echo '❌')"
    echo "Lint:   $([ "$lint_pass" = "True" ] && echo '✅' || echo '❌')"
    echo "Build:  $([ "$build_pass" = "True" ] && echo '✅' || echo '❌')"
    echo "Overall: $([ "$overall" = "pass" ] && echo '✅ PASS' || echo '❌ NOT PASS')"
  fi
}

main "$@"
