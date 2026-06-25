#!/bin/bash
# runtime-smoke.sh — 运行时验证：项目能否启动
# 依赖: bash + git + 包管理器(自动检测)
# 输入: --repo-root <path> --task-dir <path> [--timeout N] [--skip-install]
# 输出: evidence/runtime-smoke.md

set -uo pipefail

REPO_ROOT=""
TASK_DIR=""
TIMEOUT=120
SKIP_INSTALL=false
PORT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo-root) REPO_ROOT="$2"; shift 2 ;;
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --skip-install) SKIP_INSTALL=true; shift ;;
    *) shift ;;
  esac
done

if [ -z "$REPO_ROOT" ] || [ -z "$TASK_DIR" ]; then
  echo '{"error":"missing required args: --repo-root and --task-dir"}' >&2
  exit 1
fi

cd "$REPO_ROOT"
GIT_HEAD=$(git rev-parse HEAD 2>/dev/null | cut -c1-16 || echo "no-git")

# === 1. Resolve: 推导包管理器和命令 ===
resolve() {
  local pm="" install_cmd="" dev_cmd=""
  
  if [ -f pnpm-lock.yaml ]; then pm=pnpm; install_cmd="pnpm install"
  elif [ -f yarn.lock ]; then pm=yarn; install_cmd="yarn"
  elif [ -f package-lock.json ]; then pm=npm; install_cmd="npm ci"
  elif [ -f package.json ]; then pm=npm; install_cmd="npm install"
  fi
  
  if [ -f package.json ]; then
    dev_cmd=$(node -e "
      try {
        const p=require('./package.json');
        const s=p.scripts||{};
        const cmd = s.dev || s.start || s.serve || '';
        console.log(cmd ? '${pm} run '+cmd.replace('${pm} ', '') : '');
      } catch(e) { console.log(''); }
    " 2>/dev/null || echo "")
  fi
  
  if [ -z "$dev_cmd" ] && [ -f Makefile ]; then
    dev_cmd=$(grep -E '^(run|dev|start):' Makefile 2>/dev/null | head -1 | sed 's/:.*//')
    [ -n "$dev_cmd" ] && dev_cmd="make $dev_cmd"
  fi
  
  echo "{\"pm\":\"$pm\",\"install_cmd\":\"$install_cmd\",\"dev_cmd\":\"$dev_cmd\"}"
}

# === 2. Preflight: deps 检查 ===
preflight() {
  local runner="$1"
  if [ -z "$runner" ]; then return 0; fi
  
  # 检查 node_modules 中是否有 runner
  local bin_name="${runner%% *}"  # e.g. "next" from "pnpm run next dev"
  if [ -f "node_modules/.bin/$bin_name" ]; then
    return 0
  fi
  # Check if runner is globally available
  if command -v "$bin_name" &>/dev/null; then
    return 0
  fi
  return 1
}

# === 3. Smoke: 启动 + 探测 ===
smoke() {
  local dev_cmd="$1"
  local start_time=$(date +%s%3N)
  
  # 从 dev_cmd 推导端口：尝试读配置或默认
  local detect_port="$PORT"
  if [ -z "$detect_port" ]; then
    detect_port=3000
    [ -f .umirc.ts ] && detect_port=8000
    [ -f vite.config.ts ] && detect_port=5173
  fi
  
  # 后台启动
  eval "$dev_cmd" > /tmp/runtime-smoke-stdout.log 2> /tmp/runtime-smoke-stderr.log &
  local dev_pid=$!
  
  # 轮询探测
  local elapsed=0 interval=2
  local smoke_pass=false smoke_url=""
  while [ $elapsed -lt $TIMEOUT ]; do
    sleep $interval
    elapsed=$((elapsed + interval))
    
    # 检查进程是否存活
    if ! kill -0 $dev_pid 2>/dev/null; then
      break
    fi
    
    # HTTP 探测
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://localhost:$detect_port" 2>/dev/null || echo "000")
    if [ "$http_code" != "000" ] && [ "$http_code" != "404" ]; then
      smoke_pass=true
      smoke_url="http://localhost:$detect_port"
      break
    fi
    
    # 从 stdout 提取端口
    if [ -z "$smoke_url" ]; then
      local extracted_port
      extracted_port=$(grep -oE 'localhost:[0-9]+' /tmp/runtime-smoke-stdout.log 2>/dev/null | tail -1 | cut -d: -f2)
      if [ -n "$extracted_port" ] && [ "$extracted_port" != "$detect_port" ]; then
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://localhost:$extracted_port" 2>/dev/null || echo "000")
        if [ "$http_code" != "000" ]; then
          smoke_pass=true
          smoke_url="http://localhost:$extracted_port"
          detect_port="$extracted_port"
          break
        fi
      fi
    fi
  done
  
  # 收尾
  local end_time=$(date +%s%3N)
  local duration_ms=$((end_time - start_time))
  
  # 检查错误日志
  local errors=""
  errors=$(grep -iE 'Error:|FATAL|panic:|cannot find module|command not found' /tmp/runtime-smoke-stderr.log 2>/dev/null | head -5)
  
  kill $dev_pid 2>/dev/null
  wait $dev_pid 2>/dev/null
  
  # 判定结果
  if [ "$smoke_pass" = true ] && [ -z "$errors" ]; then
    echo "{\"result\":\"pass\",\"dev_cmd\":\"$dev_cmd\",\"port\":$detect_port,\"smoke_url\":\"$smoke_url\",\"duration_ms\":$duration_ms,\"errors\":[]}"
  elif [ "$smoke_pass" = true ]; then
    echo "{\"result\":\"pass\",\"dev_cmd\":\"$dev_cmd\",\"port\":$detect_port,\"smoke_url\":\"$smoke_url\",\"duration_ms\":$duration_ms,\"errors\":$(echo "$errors" | python3 -c 'import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))' 2>/dev/null || echo '[]')}"
  else
    echo "{\"result\":\"not_pass\",\"dev_cmd\":\"$dev_cmd\",\"port\":$detect_port,\"smoke_url\":\"\",\"duration_ms\":$duration_ms,\"errors\":$(echo "$errors" | python3 -c 'import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))' 2>/dev/null || echo '[]')}"
  fi
}

# === Main ===
RESOLVE_JSON=$(resolve)
INSTALL_CMD=$(echo "$RESOLVE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('install_cmd',''))" 2>/dev/null || echo "")
DEV_CMD=$(echo "$RESOLVE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('dev_cmd',''))" 2>/dev/null || echo "")

# 无法推导 dev 命令 → skipped
if [ -z "$DEV_CMD" ]; then
  cat > "$TASK_DIR/evidence/runtime-smoke.md" << EOF
---
stage: runtime_smoke
result: skipped
reason: "cannot resolve dev command"
git_head: "$GIT_HEAD"
---
No dev/start/serve script found in package.json or Makefile.
EOF
  echo '{"result":"skipped","reason":"cannot resolve dev command"}'
  exit 0
fi

# deps 检查和安装
INSTALL_RUN=""
if [ "$SKIP_INSTALL" != true ] && ! preflight "${DEV_CMD%% *}"; then
  if [ -n "$INSTALL_CMD" ]; then
    echo "Deps not ready. Running: $INSTALL_CMD"
    $INSTALL_CMD 2>&1 | tail -3
    INSTALL_RUN="$INSTALL_CMD"
  fi
fi

# 执行 smoke
SMOKE_JSON=$(smoke "$DEV_CMD")
RESULT=$(echo "$SMOKE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('result','not_pass'))" 2>/dev/null || echo "not_pass")
SMOKE_URL=$(echo "$SMOKE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('smoke_url',''))" 2>/dev/null || echo "")
DURATION=$(echo "$SMOKE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('duration_ms',0))" 2>/dev/null || echo "0")
SMOKE_PORT=$(echo "$SMOKE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('port',0))" 2>/dev/null || echo "0")
ERRORS=$(echo "$SMOKE_JSON" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin).get('errors',[])))" 2>/dev/null || echo "[]")

# 写 evidence
mkdir -p "$TASK_DIR/evidence"
cat > "$TASK_DIR/evidence/runtime-smoke.md" << EOF
---
stage: runtime_smoke
result: $RESULT
git_head: "$GIT_HEAD"
dev_cmd: "$DEV_CMD"
install_cmd: "$INSTALL_RUN"
port: $SMOKE_PORT
smoke_url: "$SMOKE_URL"
duration_ms: $DURATION
errors: $ERRORS
---
EOF

# 清理
rm -f /tmp/runtime-smoke-stdout.log /tmp/runtime-smoke-stderr.log

echo "$SMOKE_JSON"
