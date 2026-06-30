#!/bin/bash
# runtime-smoke.sh — 运行时验证：项目能否启动
# Usage: runtime-smoke.sh --repo-root <path> --task-dir <path> [--timeout N] [--skip-install] [--port N] [--health-path PATH] [--smoke-config PATH]

set -uo pipefail

REPO_ROOT=""
TASK_DIR=""
TIMEOUT=120
SKIP_INSTALL=false
PORT=""
HEALTH_PATH="/"
SMOKE_CONFIG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo-root) REPO_ROOT="$2"; shift 2 ;;
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --health-path) HEALTH_PATH="$2"; shift 2 ;;
    --smoke-config) SMOKE_CONFIG="$2"; shift 2 ;;
    --skip-install) SKIP_INSTALL=true; shift ;;
    *) shift ;;
  esac
done

if [ -z "$REPO_ROOT" ] || [ -z "$TASK_DIR" ]; then
  echo '{"error":"missing required args: --repo-root and --task-dir"}' >&2
  exit 1
fi

now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }

cd "$REPO_ROOT"
GIT_HEAD=$(git rev-parse HEAD 2>/dev/null | cut -c1-16 || echo "no-git")
STDOUT_LOG="/tmp/runtime-smoke-stdout-$$.log"
STDERR_LOG="/tmp/runtime-smoke-stderr-$$.log"

apply_smoke_config() {
  local cfg="$1"
  [ -f "$cfg" ] || return 1
  python3 - "$cfg" << 'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
out = {}
for k in ("port", "health_path", "timeout_sec", "dev_cmd"):
    if cfg.get(k) not in (None, ""):
        out[k] = cfg[k]
print(json.dumps(out))
PY
}

resolve() {
  local pm="" install_cmd="" dev_cmd="" script=""
  if [ -f pnpm-lock.yaml ]; then pm=pnpm; install_cmd="pnpm install"
  elif [ -f yarn.lock ]; then pm=yarn; install_cmd="yarn"
  elif [ -f package-lock.json ]; then pm=npm; install_cmd="npm ci"
  elif [ -f package.json ]; then pm=npm; install_cmd="npm install"
  fi
  if [ -f package.json ]; then
    script=$(node -e "
      try {
        const p=require('./package.json');
        const s=p.scripts||{};
        console.log(s.dev || s.start || s.serve || '');
      } catch(e) { console.log(''); }
    " 2>/dev/null || echo "")
    if [ -n "$script" ]; then
      if echo "$script" | grep -qE '^(npm|pnpm|yarn|npx)\s'; then
        dev_cmd="$script"
      elif [ -n "$pm" ]; then
        dev_cmd="$pm run $script"
      else
        dev_cmd="$script"
      fi
    fi
  fi
  if [ -z "$dev_cmd" ] && [ -f Makefile ]; then
    dev_cmd=$(grep -E '^(run|dev|start):' Makefile 2>/dev/null | head -1 | sed 's/:.*//')
    [ -n "$dev_cmd" ] && dev_cmd="make $dev_cmd"
  fi
  echo "{\"pm\":\"$pm\",\"install_cmd\":\"$install_cmd\",\"dev_cmd\":\"$dev_cmd\"}"
}

preflight() {
  local runner="$1"
  [ -z "$runner" ] && return 0
  local bin_name="${runner%% *}"
  [ -f "node_modules/.bin/$bin_name" ] && return 0
  command -v "$bin_name" &>/dev/null && return 0
  return 1
}

smoke() {
  local dev_cmd="$1"
  local start_time
  start_time=$(now_ms)
  local detect_port="$PORT"
  if [ -z "$detect_port" ]; then
    detect_port=3000
    [ -f vue.config.js ] && detect_port=8080
    [ -f .umirc.ts ] && detect_port=8000
    [ -f vite.config.ts ] && detect_port=5173
  fi
  eval "$dev_cmd" > "$STDOUT_LOG" 2> "$STDERR_LOG" &
  local dev_pid=$!
  local elapsed=0 interval=2
  local smoke_pass=false smoke_url="" proc_dead=false
  while [ "$elapsed" -lt "$TIMEOUT" ]; do
    sleep "$interval"
    elapsed=$((elapsed + interval))
    if ! kill -0 "$dev_pid" 2>/dev/null; then proc_dead=true; break; fi
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://localhost:${detect_port}${HEALTH_PATH}" 2>/dev/null || echo "000")
    if [ "$http_code" != "000" ] && [ "$http_code" != "404" ]; then
      smoke_pass=true
      smoke_url="http://localhost:${detect_port}${HEALTH_PATH}"
      break
    fi
    local extracted_port
    extracted_port=$(grep -oE 'localhost:[0-9]+' "$STDOUT_LOG" 2>/dev/null | tail -1 | cut -d: -f2)
    if [ -n "$extracted_port" ] && [ "$extracted_port" != "$detect_port" ]; then
      http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://localhost:${extracted_port}${HEALTH_PATH}" 2>/dev/null || echo "000")
      if [ "$http_code" != "000" ]; then
        smoke_pass=true
        smoke_url="http://localhost:${extracted_port}${HEALTH_PATH}"
        detect_port="$extracted_port"
        break
      fi
    fi
  done
  local end_time duration_ms
  end_time=$(now_ms)
  duration_ms=$((end_time - start_time))
  kill "$dev_pid" 2>/dev/null
  wait "$dev_pid" 2>/dev/null || true

  python3 - "$dev_cmd" "$detect_port" "$HEALTH_PATH" "$duration_ms" "$smoke_pass" "$smoke_url" "$proc_dead" "$STDERR_LOG" << 'PY'
import json, re, sys
dev_cmd, port, health_path, duration_ms, smoke_pass, smoke_url, proc_dead, stderr_log = sys.argv[1:]
errors = []
try:
    with open(stderr_log) as f:
        for line in f:
            if re.search(r'Error:|FATAL|panic:|cannot find module|command not found', line, re.I):
                errors.append(line.strip())
                if len(errors) >= 5:
                    break
except OSError:
    pass
stderr_tail = ""
try:
    with open(stderr_log) as f:
        stderr_tail = f.read()[-2000:]
except OSError:
    pass
result = "pass" if smoke_pass == "true" else "not_pass"
classification = "none"
if result != "pass":
    joined = " ".join(errors)
    if re.search(r'command not found|ENOENT|cannot find module', joined, re.I):
        classification = "environmental"
    elif proc_dead == "true" and errors:
        classification = "code_issue"
    elif re.search(r'EADDRINUSE|port', joined, re.I):
        classification = "environmental"
    else:
        classification = "runtime_crash"
print(json.dumps({
    "result": result,
    "dev_cmd": dev_cmd,
    "port": int(port or 0),
    "smoke_url": smoke_url if smoke_url != "false" else "",
    "health_path": health_path,
    "duration_ms": int(duration_ms),
    "errors": errors,
    "stderr_tail": stderr_tail,
    "classification": classification,
    "proc_exited_early": proc_dead == "true",
}))
PY
}

CFG_JSON="{}"
for candidate in "$SMOKE_CONFIG" "$TASK_DIR/smoke.json" "$REPO_ROOT/smoke.json"; do
  if [ -n "$candidate" ] && [ -f "$candidate" ]; then
    CFG_JSON=$(apply_smoke_config "$candidate" || echo "{}")
    [ "$CFG_JSON" != "{}" ] && break
  fi
done

if [ "$CFG_JSON" != "{}" ]; then
  [ -z "$PORT" ] && PORT=$(echo "$CFG_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('port',''))")
  HP=$(echo "$CFG_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('health_path',''))")
  [ -n "$HP" ] && HEALTH_PATH="$HP"
  TS=$(echo "$CFG_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('timeout_sec',''))")
  [ -n "$TS" ] && TIMEOUT="$TS"
  CFG_OVERRIDE=$(echo "$CFG_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('dev_cmd',''))")
else
  CFG_OVERRIDE=""
fi

RESOLVE_JSON=$(resolve)
INSTALL_CMD=$(echo "$RESOLVE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('install_cmd',''))" 2>/dev/null || echo "")
DEV_CMD="${CFG_OVERRIDE:-$(echo "$RESOLVE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('dev_cmd',''))" 2>/dev/null || echo "")}"

mkdir -p "$TASK_DIR/evidence"

if [ -z "$DEV_CMD" ]; then
  cat > "$TASK_DIR/evidence/runtime-smoke.md" << EOF
---
stage: runtime_smoke
result: skipped
classification: none
reason: cannot resolve dev command
git_head: "$GIT_HEAD"
---
No dev/start/serve script found in package.json or Makefile.
EOF
  echo '{"result":"skipped","reason":"cannot resolve dev command","classification":"none"}'
  exit 0
fi

INSTALL_RUN=""
if [ "$SKIP_INSTALL" != true ] && ! preflight "${DEV_CMD%% *}"; then
  if [ -n "$INSTALL_CMD" ]; then
    echo "Deps not ready. Running: $INSTALL_CMD" >&2
    $INSTALL_CMD 2>&1 | tail -3
    INSTALL_RUN="$INSTALL_CMD"
  fi
fi

SMOKE_JSON=$(smoke "$DEV_CMD") || SMOKE_JSON='{"result":"not_pass","failure_code":"script_error","classification":"runtime_crash","errors":[],"duration_ms":0,"port":0,"smoke_url":""}'
RESULT=$(echo "$SMOKE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('result','not_pass'))" 2>/dev/null || echo "not_pass")
CLASSIFICATION=$(echo "$SMOKE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('classification','unknown'))" 2>/dev/null || echo "unknown")
FAILURE_CODE=$(echo "$SMOKE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('failure_code',''))" 2>/dev/null || echo "")
SMOKE_URL=$(echo "$SMOKE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('smoke_url',''))" 2>/dev/null || echo "")
DURATION=$(echo "$SMOKE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('duration_ms',0))" 2>/dev/null || echo "0")
SMOKE_PORT=$(echo "$SMOKE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('port',0))" 2>/dev/null || echo "0")
ERRORS=$(echo "$SMOKE_JSON" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin).get('errors',[])))" 2>/dev/null || echo "[]")

python3 - "$TASK_DIR/evidence/runtime-smoke.md" "$GIT_HEAD" "$RESULT" "$CLASSIFICATION" "$DEV_CMD" "$INSTALL_RUN" "$SMOKE_PORT" "$HEALTH_PATH" "$SMOKE_URL" "$DURATION" "$FAILURE_CODE" "$ERRORS" "$SMOKE_JSON" << 'PY'
import json, sys
path, git_head, result, classification, dev_cmd, install_run, port, health_path, smoke_url, duration, failure_code, errors_json, smoke_json = sys.argv[1:]
errors = json.loads(errors_json)
body = json.loads(smoke_json)
stderr_tail = body.get("stderr_tail", "")
with open(path, "w") as f:
    f.write(f"""---
stage: runtime_smoke
result: {result}
classification: {classification}
git_head: "{git_head}"
dev_cmd: "{dev_cmd}"
install_cmd: "{install_run}"
port: {port}
health_path: "{health_path}"
smoke_url: "{smoke_url}"
duration_ms: {duration}
failure_code: "{failure_code}"
errors: {json.dumps(errors)}
---

## stderr_tail

```
{stderr_tail[:1500]}
```
""")
PY

rm -f "$STDOUT_LOG" "$STDERR_LOG"
echo "$SMOKE_JSON"
