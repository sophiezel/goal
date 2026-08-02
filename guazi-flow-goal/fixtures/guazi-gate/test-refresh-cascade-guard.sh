#!/usr/bin/env bash
# forced --cascade plan with only execution_changed → demoted to implement
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="${GUAZI_SCRIPTS:-${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts}"
REFRESH="$S/refresh-handoffs-after-index.sh"
HASH_PY="$S/index_contract_hash.py"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
TASK="$repo/docs/guazi-flow/t"
mkdir -p "$TASK/handoff" "$TASK/evidence"
cd "$repo"
git init -q
git config user.email "t@e.com"
git config user.name "t"
echo x > README.md && git add . && git commit -qm i

python3 - "$TASK" "$HASH_PY" <<'PY'
from pathlib import Path
import json, importlib.util, sys
task = Path(sys.argv[1])
hash_py = sys.argv[2]
spec = importlib.util.spec_from_file_location("ich", hash_py)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
idx = task / "index.md"
idx.write_text("""# t

## 核心事实
c1

## 完整伪代码
p1

## 验收矩阵
a1

## 执行记录
- old
""", encoding="utf-8")
ch = mod.index_contract_hash(str(idx))
eh = mod.index_execution_tail_hash(str(idx))
(task / "handoff" / "plan.json").write_text(json.dumps({
    "write_set": ["src/x.js"],
    "index_contract_hash": ch,
    "index_execution_tail_hash": eh,
    "gate": {"passed_at": "2026-07-14T00:00:00Z", "post_exit_code": 0},
}), encoding="utf-8")
# mutate execution only
idx.write_text("""# t

## 核心事实
c1

## 完整伪代码
p1

## 验收矩阵
a1

## 执行记录
- new line only
""", encoding="utf-8")
fresh = mod.compare_plan_freshness(str(idx), json.loads((task / "handoff" / "plan.json").read_text()))
assert fresh["contract_changed"] is False, fresh
assert fresh["execution_changed"] is True, fresh
print("fixture_ok", fresh)
PY

export GUAZI_STATE_HOME="$tmp/gs"
export GOAL_STATE_HOME="$tmp/gs"
mkdir -p "$GUAZI_STATE_HOME/scripts"
cat > "$GUAZI_STATE_HOME/scripts/guazi-gate-stage.sh" <<'SH'
#!/bin/bash
echo "stub-gate $*" >&2
exit 0
SH
cat > "$GUAZI_STATE_HOME/scripts/assemble-review-packet.sh" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$GUAZI_STATE_HOME/scripts"/*.sh

PID=$(python3 -c "import hashlib; from pathlib import Path; print(hashlib.sha256(str(Path('$repo').resolve()).encode()).hexdigest()[:12])")
STATE="$tmp/state.json"
python3 -c "
import json
from pathlib import Path
Path('$STATE').write_text(json.dumps({
  'project_id': '$PID',
  'guazi_flow_task': 'docs/guazi-flow/t',
}), encoding='utf-8')
"

OUT=$(bash "$REFRESH" --task-dir "$TASK" --project-root "$repo" --state-file "$STATE" \
  --cascade plan --format json 2>"$tmp/err")
echo "$OUT"
grep -q "REJECT cascade=plan\|demote to implement" "$tmp/err" || {
  echo "FAIL missing demote log"; cat "$tmp/err"; exit 1
}
CASCADE=$(echo "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('cascade'))")
[[ "$CASCADE" == "implement" ]] || { echo "FAIL cascade=$CASCADE"; cat "$tmp/err"; exit 1; }
echo "OK cascade demoted to implement"
echo "OK refresh-cascade-guard"
