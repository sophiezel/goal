#!/bin/bash
# verify-review.sh - 确定性 review 检查 (0 模型调用)
# 检查: 修改范围 | 密钥扫描 | 测试通过 | Lint 通过
# 依赖: bash + git

set -euo pipefail

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
  
  cd "$GIT_ROOT"
  modified_files=$(git diff --name-only HEAD 2>/dev/null || echo "")
  
  if [ -z "$modified_files" ]; then
    echo '{"pass":true,"modified_files":[],"out_of_scope":[]}'
    return
  fi
  
  if [ -n "$WRITE_SET" ]; then
    IFS=',' read -ra ALLOWED <<< "$WRITE_SET"
    for f in $modified_files; do
      local allowed=false
      for a in "${ALLOWED[@]}"; do
        # Strip whitespace
        a=$(echo "$a" | xargs)
        # Prefix match only (directory or file prefix)
        if [[ "$f" == "$a"* ]]; then
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
  
  cd "$GIT_ROOT"
  local diff_content
  diff_content=$(git diff HEAD 2>/dev/null || echo "")
  
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

# === 3. 测试检查 ===
check_tests() {
  cd "$GIT_ROOT"
  
  if [ -f "package.json" ]; then
    local has_test
    has_test=$(node -e "try{const p=require('./package.json');console.log(p.scripts&&p.scripts.test?'yes':'no')}catch(e){console.log('no')}" 2>/dev/null || echo "no")
    if [ "$has_test" = "yes" ]; then
      if npm test >/dev/null 2>&1; then
        echo '{"pass":true,"command":"npm test","output":"all passing"}'
      else
        echo '{"pass":false,"command":"npm test","output":"tests failed"}'
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
  
  local has_lint=false
  for cfg in .eslintrc.js .eslintrc.cjs .eslintrc.json .eslintrc.yaml .eslintrc.yml .eslintrc; do
    [ -f "$cfg" ] && has_lint=true && break
  done
  grep -q '"eslint"' package.json 2>/dev/null && has_lint=true
  
  if [ "$has_lint" = true ]; then
    if npx eslint --quiet $(git diff --name-only HEAD 2>/dev/null | grep -E '\.(ts|tsx|js|jsx)$' | tr '\n' ' ') 2>/dev/null; then
      echo '{"pass":true,"command":"eslint","output":"clean"}'
    else
      echo '{"pass":false,"command":"eslint","output":"lint errors found"}'
    fi
  else
    echo '{"pass":true,"command":"skipped","output":"no eslint config detected"}'
  fi
}

# === Main ===
main() {
  local scope_result secret_result test_result lint_result
  scope_result=$(check_scope)
  secret_result=$(check_secrets)
  test_result=$(check_tests)
  lint_result=$(check_lint)
  
  local scope_pass secret_pass test_pass lint_pass
  scope_pass=$(echo "$scope_result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pass',False))" 2>/dev/null || echo "false")
  secret_pass=$(echo "$secret_result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pass',False))" 2>/dev/null || echo "false")
  test_pass=$(echo "$test_result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pass',False))" 2>/dev/null || echo "false")
  lint_pass=$(echo "$lint_result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pass',False))" 2>/dev/null || echo "false")
  
  local overall="pass"
  if [ "$scope_pass" != "True" ] || [ "$secret_pass" != "True" ] || [ "$test_pass" != "True" ] || [ "$lint_pass" != "True" ]; then
    overall="not_pass"
  fi
  
  if [ "$FORMAT" = "json" ]; then
    cat <<EOF
{
  "overall": "$overall",
  "checks": {
    "scope": $scope_result,
    "secret": $secret_result,
    "test": $test_result,
    "lint": $lint_result
  }
}
EOF
  else
    echo "=== Review Checks ==="
    echo "Scope:  $([ "$scope_pass" = "True" ] && echo '✅' || echo '❌') (files outside write_set: $(echo "$scope_result" | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d.get('out_of_scope',[])))" 2>/dev/null || echo '?'))"
    echo "Secret: $([ "$secret_pass" = "True" ] && echo '✅' || echo '❌') (findings: $(echo "$secret_result" | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d.get('findings',[])))" 2>/dev/null || echo '?'))"
    echo "Tests:  $([ "$test_pass" = "True" ] && echo '✅' || echo '❌')"
    echo "Lint:   $([ "$lint_pass" = "True" ] && echo '✅' || echo '❌')"
    echo "Overall: $([ "$overall" = "pass" ] && echo '✅ PASS' || echo '❌ NOT PASS')"
  fi
}

main "$@"
