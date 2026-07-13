#!/bin/bash
# gate-guazi-flow-stage.sh — Hard gate for guazi-flow-goal stages
# Usage: gate-guazi-flow-stage.sh --task-dir <path> --stage plan|implement|quality|smoke|review|complete [--pre|--post] [--mode guazi|degraded]
# Exit 0 = pass, 1 = fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GATE_SCRIPT_DIR="$SCRIPT_DIR"
SCHEMA_DIR="${SCRIPT_DIR}/../references/guazi-flow-artifact-schema"
GATE_VERSION=1

TASK_DIR=""
STAGE=""
PHASE="post"
MODE="guazi"
STATE_FILE=""
ASSERT_COMPLETE=false
PROJECT_ROOT=""

usage() {
  echo "Usage: $0 --task-dir <path> --stage plan|implement|quality|smoke|review|complete [--pre|--post] [--mode guazi|degraded]" >&2
  echo "       $0 --assert-complete --state-file <path> [--task-dir <path>] [--project-root <path>]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --stage) STAGE="$2"; shift 2 ;;
    --pre) PHASE="pre"; shift ;;
    --post) PHASE="post"; shift ;;
    --mode) MODE="$2"; shift 2 ;;
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --assert-complete) ASSERT_COMPLETE=true; shift ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done


# === Assert-complete mode (Stop Hook / pipeline guard) ===
if [[ "$ASSERT_COMPLETE" == "true" ]]; then
  [[ -n "$STATE_FILE" ]] || { echo "gate assert-complete: --state-file required" >&2; exit 2; }
  ADVANCE="$SCRIPT_DIR/goal-advance-stage.sh"
  [[ -x "$ADVANCE" ]] || ADVANCE="${GOAL_STATE_HOME:-$HOME/.goal-state}/scripts/goal-advance-stage.sh"
  [[ -x "$ADVANCE" ]] || { echo "gate assert-complete: goal-advance-stage.sh not found" >&2; exit 2; }
  ARGS=(--state-file "$STATE_FILE" --format json)
  [[ -n "$TASK_DIR" ]] && ARGS+=(--task-dir "$TASK_DIR")
  [[ -n "$PROJECT_ROOT" ]] && ARGS+=(--project-root "$PROJECT_ROOT")
  OUT=$("$ADVANCE" "${ARGS[@]}" 2>/dev/null) || RC=$?
  RC=${RC:-0}
  NEXT=$(echo "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('next_stage','unknown'))" 2>/dev/null || echo "unknown")
  if [[ "$NEXT" == "done" ]]; then
    if [[ -n "$STATE_FILE" && -f "$STATE_FILE" ]]; then
      python3 - "$STATE_FILE" << 'PYDONE'
import json, sys
from datetime import datetime, timezone
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    state = json.load(f)
if state.get("status") != "complete":
    state["status"] = "complete"
    state["current_stage"] = "complete"
    state["updated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    pipe = state.setdefault("pipeline", {})
    for stage in ("plan", "implement", "quality", "review", "complete"):
        entry = pipe.setdefault(stage, {})
        entry["status"] = "passed"
        entry["evidence_fresh"] = True
    with open(path, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2, ensure_ascii=False)
        f.write("\n")
PYDONE
    fi
    echo "gate assert-complete: pipeline complete"
    exit 0
  fi
  echo "gate assert-complete: pipeline incomplete — next_stage=$NEXT" >&2
  echo "$OUT"
  exit 2
fi

[[ -n "$TASK_DIR" && -n "$STAGE" ]] || usage
case "$STAGE" in plan|implement|quality|smoke|review|complete) ;; *) echo "Invalid stage: $STAGE" >&2; exit 2 ;; esac

# Resolve paths
if [[ "$TASK_DIR" != /* ]]; then
  TASK_DIR="$(pwd)/$TASK_DIR"
fi
TASK_DIR="$(cd "$TASK_DIR" 2>/dev/null && pwd)" || { echo "gate: task dir not found: $TASK_DIR" >&2; exit 1; }

RESOLVER="$SCRIPT_DIR/resolve-artifact-paths.py"
_RESOLVE_ARGS=(--task-dir "$TASK_DIR" --format shell --ensure-state)
[[ -n "$STATE_FILE" ]] && _RESOLVE_ARGS+=(--state-file "$STATE_FILE")
[[ -n "$PROJECT_ROOT" ]] && _RESOLVE_ARGS+=(--project-root "$PROJECT_ROOT")
eval "$(python3 "$RESOLVER" "${_RESOLVE_ARGS[@]}")"

INDEX="$REPO_TASK_DIR/index.md"
# HANDOFF_DIR, REPO_EVIDENCE_DIR, GOAL_EVIDENCE_DIR from resolver
EVIDENCE_DIR="$REPO_EVIDENCE_DIR"
GIT_ROOT=$(git -C "$REPO_TASK_DIR" rev-parse --show-toplevel 2>/dev/null || git -C "$(dirname "$REPO_TASK_DIR")" rev-parse --show-toplevel 2>/dev/null || echo "")

FORMAT_ISSUES="$SCRIPT_DIR/format-gate-issues.sh"

fail() { echo "gate FAIL [$STAGE/$PHASE]: $*" >&2; exit 1; }
purge_split_repo_tier_r() {
  [[ "${ARTIFACT_MODE:-}" == "split" ]] || return 0
  local _purge_args=(--task-dir "$REPO_TASK_DIR" --purge-repo-tier-r)
  [[ -n "$STATE_FILE" ]] && _purge_args+=(--state-file "$STATE_FILE")
  [[ -n "$PROJECT_ROOT" ]] && _purge_args+=(--project-root "$PROJECT_ROOT")
  python3 "$RESOLVER" "${_purge_args[@]}" >/dev/null 2>&1 || true
}
pass() {
  [[ "$PHASE" == "post" ]] && purge_split_repo_tier_r
  echo "gate PASS [$STAGE/$PHASE]: $*"
  exit 0
}

write_state_blocked() {
  local code="$1"
  [[ -n "$STATE_FILE" && -f "$STATE_FILE" ]] || return 0
  python3 - "$STATE_FILE" "$code" << 'PYBLOCK'
import json, sys
from datetime import datetime, timezone
path, code = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    state = json.load(f)
state["status"] = "blocked"
state["failure_code"] = code
state["blocked_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
with open(path, "w", encoding="utf-8") as f:
    json.dump(state, f, indent=2, ensure_ascii=False)
PYBLOCK
}

check_noop_ratchet() {
  local stage="$1"
  local subject_hash="$2"
  local fix_path="$GOAL_EVIDENCE_DIR/${stage}-gate-fix-input.json"
  [[ -f "$fix_path" ]] || return 0
  local prev
  prev=$(python3 -c "import json; print(json.load(open('$fix_path')).get('subject_hash',''))" 2>/dev/null || echo "")
  if [[ -n "$prev" && "$prev" == "$subject_hash" ]]; then
    write_state_blocked "noop_fix"
    local noop_issues='[{"id":"G000","severity":"blocker","summary":"subject_hash 未变化，修复无效（noop_fix）","root_cause":"implement_error"}]'
    fix_path=$(write_gate_fix_input "$stage" "$subject_hash" "blocked_noop_fix" "$noop_issues")
    local label
    label=$(echo "$stage" | tr '[:lower:]' '[:upper:]')
    if [[ -x "$FORMAT_ISSUES" ]]; then
      "$FORMAT_ISSUES" --stage-label "$label" --fix-input "$fix_path" >&2
    fi
    echo "gate FAIL [$stage/$PHASE]: blocked(noop_fix) — subject_hash unchanged" >&2
    exit 1
  fi
  return 0
}

write_gate_fix_input() {
  local stage="$1"
  local subject_hash="$2"
  local action="$3"
  local issues_json="$4"
  mkdir -p "$GOAL_EVIDENCE_DIR"
  local out="$GOAL_EVIDENCE_DIR/${stage}-gate-fix-input.json"
  GATE_ISSUES_JSON="$issues_json" python3 - "$out" "$stage" "$subject_hash" "$action" << 'PYWFI'
import json, os, sys
out, stage, subject_hash, action = sys.argv[1:5]
issues = json.loads(os.environ.get("GATE_ISSUES_JSON", "[]"))
next_steps = {
    "plan": ["修 index.md 必填章节与 write_set 后重跑 gate --post plan"],
    "implement": ["在 write_set 范围内修改代码后重跑 gate --post implement"],
    "smoke": ["修复 runtime-smoke 问题后重跑 gate --post smoke"],
    "review": ["读 evidence/review-fix-input.json 修复后重跑 review 链"],
}.get(stage, [f"修产物后重跑 gate --post {stage}"])
payload = {
    "schema_version": 1,
    "stage": stage,
    "action": action,
    "issues": issues,
    "next_steps": next_steps,
    "subject_hash": subject_hash,
    "gate_script": "gate-guazi-flow-stage.sh",
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2, ensure_ascii=False)
print(out)
PYWFI
}

gate_fail_with_issues() {
  local stage="$1"
  local subject_hash="$2"
  local action="$3"
  local issues_json="$4"
  local msg="${5:-gate validation failed}"
  check_noop_ratchet "$stage" "$subject_hash" || exit 1
  local fix_path
  fix_path=$(write_gate_fix_input "$stage" "$subject_hash" "$action" "$issues_json")
  local label
  label=$(echo "$stage" | tr '[:lower:]' '[:upper:]')
  if [[ -x "$FORMAT_ISSUES" && -f "$fix_path" ]]; then
    "$FORMAT_ISSUES" --stage-label "$label" --fix-input "$fix_path" >&2
  fi
  echo "gate FAIL [$stage/$PHASE]: $msg" >&2
  exit 1
}

errors_to_issues_json() {
  python3 - << 'PYETI'
import json, os, re
errors = json.loads(os.environ.get("GATE_ERRORS_JSON", "[]"))
issues = []
for i, e in enumerate(errors, 1):
    iid = f"G{i:03d}"
    root = "plan_gap"
    if "write_set" in e.lower():
        root = "plan_gap"
    m = re.search(r"missing section: (## .+)", e)
    summary = m.group(1) if m else e
    if m:
        summary = f"缺少必填章节: {m.group(1)}"
    issues.append({
        "id": iid,
        "severity": "blocker",
        "summary": summary,
        "root_cause": root,
        "criterion_ref": "unified-doc-contract §章节顺序",
    })
print(json.dumps(issues, ensure_ascii=False))
PYETI
}

show_review_issue_board() {
  local fix_path="$GOAL_EVIDENCE_DIR/review-fix-input.json"
  [[ -f "$fix_path" && -x "$FORMAT_ISSUES" ]] || return 0
  "$FORMAT_ISSUES" --stage-label "REVIEW" --fix-input "$fix_path" >&2
}

git_head_short() {
  if [[ -n "$GIT_ROOT" ]]; then
    git -C "$GIT_ROOT" rev-parse --short=16 HEAD 2>/dev/null || echo "unknown"
  else
    echo "unknown"
  fi
}

content_hash() {
  local f="$1"
  if [[ -f "$f" ]]; then
    shasum -a 256 "$f" 2>/dev/null | cut -c1-16 || sha256sum "$f" 2>/dev/null | cut -c1-16 || echo "unknown"
  else
    echo "missing"
  fi
}

# Contract-only fingerprint (excludes ## 执行记录). Prefer over content_hash for plan freshness.
INDEX_HASH_PY="$SCRIPT_DIR/index_contract_hash.py"
index_contract_hash() {
  local f="$1"
  if [[ -f "$INDEX_HASH_PY" && -f "$f" ]]; then
    python3 "$INDEX_HASH_PY" "$f" 2>/dev/null || content_hash "$f"
  else
    content_hash "$f"
  fi
}

index_execution_tail_hash() {
  local f="$1"
  if [[ -f "$INDEX_HASH_PY" && -f "$f" ]]; then
    python3 "$INDEX_HASH_PY" --json "$f" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('index_execution_tail_hash',''))" 2>/dev/null || echo ""
  else
    echo ""
  fi
}

normalize_write_set_json() {
  local ws_json="$1"
  if [[ -f "$INDEX_HASH_PY" ]]; then
    python3 - "$INDEX_HASH_PY" "$ws_json" << 'PYNORM' 2>/dev/null || echo "$ws_json"
import json, sys
sys.path.insert(0, "")
helper = sys.argv[1]
ws = json.loads(sys.argv[2])
import importlib.util
spec = importlib.util.spec_from_file_location("index_contract_hash", helper)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(json.dumps(mod.normalize_write_set(ws), ensure_ascii=False))
PYNORM
  else
    echo "$ws_json"
  fi
}

diff_hash() {
  if [[ -n "$GIT_ROOT" ]]; then
    python3 - "$GIT_ROOT" << 'PYDH' 2>/dev/null || echo "unknown"
import importlib.util, os, sys
gate_script = os.environ.get('GATE_SCRIPT_DIR', '')
if gate_script:
    path = os.path.join(gate_script, 'verification_oracle_core.py')
    if os.path.isfile(path):
        spec = importlib.util.spec_from_file_location('uvo', path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        print(mod.diff_hash(sys.argv[1]))
        sys.exit(0)
import hashlib, subprocess
repo = sys.argv[1]
diff = subprocess.check_output(['git', '-C', repo, '-c', 'core.quotepath=false', 'diff', 'HEAD'], text=True, stderr=subprocess.DEVNULL)
un = subprocess.check_output(['git', '-C', repo, '-c', 'core.quotepath=false', 'ls-files', '--others', '--exclude-standard'], text=True, stderr=subprocess.DEVNULL).splitlines()
for f in un:
    fp = os.path.join(repo, f)
    if os.path.isfile(fp):
        try:
            diff += f"\n--- new file: {f} ---\n{open(fp, encoding='utf-8', errors='replace').read()}\n"
        except OSError:
            pass
print(hashlib.sha256(diff.encode()).hexdigest()[:16])
PYDH
  else
    echo "unknown"
  fi
}

code_subject_hash() {
  if [[ -n "$GIT_ROOT" ]]; then
    local ws_json ref_branch
    ws_json=$(python3 -c "import json; print(json.dumps(json.load(open('$HANDOFF_DIR/plan.json')).get('write_set',[])))" 2>/dev/null || echo '[]')
    ref_branch=$(python3 -c "import json; p=json.load(open('$HANDOFF_DIR/plan.json')); print(p.get('reference_branch') or p.get('reference_impl_branch') or '')" 2>/dev/null || echo "")
    python3 - "$GIT_ROOT" "$ws_json" "$ref_branch" << 'PYCS' 2>/dev/null || echo "unknown"
import importlib.util, json, os, sys
gate_script = os.environ.get('GATE_SCRIPT_DIR', '')
path = os.path.join(gate_script, 'verification_oracle_core.py')
spec = importlib.util.spec_from_file_location('uvo', path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
ws = json.loads(sys.argv[2])
print(mod.code_subject_hash(sys.argv[1], ws, sys.argv[3]))
PYCS
  else
    echo "unknown"
  fi
}

iso_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

read_handoff() {
  local stage="$1"
  local f="$HANDOFF_DIR/${stage}.json"
  [[ -f "$f" ]] || return 1
  cat "$f"
}

handoff_fresh() {
  local stage="$1"
  local expected_hash="${2:-}"
  local hf="$HANDOFF_DIR/${stage}.json"
  [[ -f "$hf" ]] || return 1
  if [[ -n "$expected_hash" ]]; then
    local stored
    stored=$(python3 -c "import json,sys; d=json.load(open('$hf')); print(d.get('index_schema_hash', d.get('candidate_diff_hash', d.get('review_subject_hash',''))))" 2>/dev/null || echo "")
    [[ "$stored" == "$expected_hash" ]] || return 1
  fi
  return 0
}

# Python helpers for markdown parsing
py_check_index() {
  python3 - "$INDEX" "$SCHEMA_DIR/plan-index-rules.json" << 'PY'
import json, re, sys
index_path, rules_path = sys.argv[1], sys.argv[2]
rules = json.load(open(rules_path))
text = open(index_path, encoding='utf-8').read()
errors = []

# frontmatter
fm = {}
m = re.match(r'^---\s*\n(.*?)\n---', text, re.DOTALL)
if not m:
    errors.append("missing YAML frontmatter")
else:
    for line in m.group(1).splitlines():
        if ':' in line:
            k, v = line.split(':', 1)
            fm[k.strip()] = v.strip().strip('"').strip("'")
    for k in rules['frontmatter_required']:
        if k not in fm and k not in {x.replace('current_stage','flow.current_stage') for x in fm}:
            # also check nested flow.current_stage style in body
            if k == 'current_stage' and 'flow.current_stage' not in text and 'current_stage' not in fm:
                errors.append(f"frontmatter missing: {k}")
            elif k != 'current_stage' and k not in fm:
                errors.append(f"frontmatter missing: {k}")

for sec in rules['sections_required']:
    if sec not in text:
        errors.append(f"missing section: {sec}")

# pseudocode section size
pm = re.search(r'## 完整伪代码\s*\n(.*?)(?=\n## |\Z)', text, re.DOTALL)
if pm:
    body = pm.group(1)
    if len(body.strip()) < rules.get('pseudocode_min_chars', 200):
        errors.append(f"pseudocode too short: {len(body.strip())} chars")
    blocks = len(re.findall(r'```', body)) // 2
    if blocks < rules.get('pseudocode_min_code_blocks', 1):
        errors.append(f"pseudocode needs >= {rules['pseudocode_min_code_blocks']} code block(s)")
else:
    errors.append("pseudocode section not found")

# execution record skill for plan post
skill = rules['execution_record_skill'].get('plan', 'guazi-flow-plan')
if skill not in text:
    errors.append(f"execution record missing skill marker: {skill}")

# extract write_set from markdown tables or bullet lists (section header at line start only)
write_set = []
ws_matches = list(re.finditer(
    r'^##\s*(?:范围与写集|write[_\s-]?set|写集)\s*\n(.*?)(?=\n## |\Z)',
    text, re.IGNORECASE | re.DOTALL | re.MULTILINE
))
ws_sec = ws_matches[-1] if ws_matches else None
if ws_sec:
    block = ws_sec.group(1)
    for line in block.splitlines():
        for m in re.findall(r'`([^`]+)`', line):
            write_set.append(m.strip())
        m2 = re.match(r'[-*]\s+(.+)', line.strip())
        if m2:
            val = m2.group(1).strip().strip('`')
            if val and not val.startswith('|'):
                write_set.append(val)
write_set = list(dict.fromkeys(write_set))
if not write_set:
    for pat in [r'write_set:\s*\[([^\]]+)\]']:
        wm = re.search(pat, text, re.IGNORECASE)
        if wm:
            write_set = [x.strip().strip('"\'') for x in wm.group(1).split(',') if x.strip()]

# acceptance matrix ids
matrix_ids = re.findall(r'\b(?:C|V|AC|TC)\d+\b', text)
matrix_ids = sorted(set(matrix_ids))

print(json.dumps({
    "ok": len(errors) == 0,
    "errors": errors,
    "frontmatter": fm,
    "write_set": write_set,
    "acceptance_matrix_ids": matrix_ids,
    "profile": fm.get('profile', ''),
    "profile_detail": fm.get('profile_detail', ''),
}))
PY
}


read_gf_issues_count() {
  local unified_json="$GOAL_EVIDENCE_DIR/review-unified.json"
  if [[ -f "$unified_json" ]]; then
    python3 - "$unified_json" << 'PYGF'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
issues = d.get("issues", [])
print(sum(1 for i in issues if i.get("channel") == "guazi-flow-review"))
PYGF
    return
  fi
  python3 - "$EVIDENCE_DIR/review.md" << 'PYGF2'
import re, sys, os
p = sys.argv[1]
if not os.path.isfile(p):
    print(0); sys.exit(0)
t = open(p, encoding="utf-8").read()
m = re.match(r"^---\s*\n(.*?)\n---", t, re.DOTALL)
if m:
    for line in m.group(1).splitlines():
        if line.strip().startswith("issues_gf_count:"):
            try:
                print(int(line.split(":",1)[1].strip())); sys.exit(0)
            except ValueError:
                pass
print(0)
PYGF2
}

py_check_review() {
  python3 - "$REPO_EVIDENCE_DIR/review.md" "$SCHEMA_DIR/review-evidence-rules.json" "$GOAL_EVIDENCE_DIR/review-unified.json" << 'PY'
import json, re, sys, os
review_path, rules_path, unified_json = sys.argv[1], sys.argv[2], sys.argv[3]
errors = []
if not os.path.isfile(review_path):
    print(json.dumps({"ok": False, "errors": ["evidence/review.md missing"]}))
    sys.exit(0)
text = open(review_path, encoding='utf-8').read()
rules = json.load(open(rules_path))
fm = {}
m = re.match(r'^---\s*\n(.*?)\n---', text, re.DOTALL)
if not m:
    errors.append("review.md missing YAML frontmatter")
else:
    for line in m.group(1).splitlines():
        if ':' in line:
            k, v = line.split(':', 1)
            fm[k.strip()] = v.strip().strip('"').strip("'")
    for k in rules['frontmatter_required']:
        if k not in fm:
            errors.append(f"review frontmatter missing: {k}")

for sec in rules.get('sections_required', []):
    if sec not in text:
        errors.append(f"review missing section: {sec}")

has_goal = '## Goal Pipeline Review' in text or os.path.isfile(unified_json)
if not has_goal:
    errors.append("missing goal-pipeline review annex (## Goal Pipeline Review or review-unified.json)")

result = fm.get('result', 'unknown')
print(json.dumps({
    "ok": len(errors) == 0,
    "errors": errors,
    "frontmatter": fm,
    "result": result,
    "review_subject_hash": fm.get('review_subject_hash', ''),
    "has_goal_annex": has_goal,
}))
PY
}

py_write_handoff() {
  local stage="$1"
  local payload="$2"
  python3 - "$HANDOFF_DIR" "$stage" "$payload" << 'PY'
import json, sys, os
from datetime import datetime, timezone
handoff_dir, stage, payload_path = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(handoff_dir, exist_ok=True)
payload = json.load(open(payload_path))
payload.setdefault('gate', {})
payload['gate'] = {
    'script': 'gate-guazi-flow-stage.sh',
    'version': 1,
    'passed_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'post_exit_code': 0,
}
out = os.path.join(handoff_dir, f'{stage}.json')
with open(out, 'w', encoding='utf-8') as f:
    json.dump(payload, f, indent=2, ensure_ascii=False)
print(out)
PY
}

get_changed_files() {
  if [[ -n "$GIT_ROOT" ]]; then
    git -C "$GIT_ROOT" diff --name-only HEAD 2>/dev/null
    git -C "$GIT_ROOT" ls-files --others --exclude-standard 2>/dev/null
  fi
}

check_write_set_subset() {
  local write_set_json="$1"
  python3 - "$write_set_json" << 'PY'
import json, sys, subprocess, os
write_set = json.loads(sys.argv[1])
if not write_set:
    print(json.dumps({"ok": True, "out_of_scope": []}))
    sys.exit(0)
try:
    modified = subprocess.check_output(['git', '-c', 'core.quotepath=false', 'diff', '--name-only', 'HEAD'], text=True).splitlines()
    untracked = subprocess.check_output(['git', '-c', 'core.quotepath=false', 'ls-files', '--others', '--exclude-standard'], text=True).splitlines()
    all_files = [f for f in modified + untracked if f.strip()]
except Exception:
    all_files = []
out = []
for f in all_files:
    if f.startswith('docs/guazi-flow/'):
        continue
    def _allowed(f, w):
        w = w.rstrip('/')
        if w.endswith('/**'):
            w = w[:-3]
        return f == w or f.startswith(w + '/')
    allowed = any(_allowed(f, w) for w in write_set)
    if not allowed:
        out.append(f)
print(json.dumps({"ok": len(out) == 0, "out_of_scope": out, "changed_files": all_files}))
PY
}

# === Degraded mode: skip guazi-specific checks ===
if [[ "$MODE" == "degraded" ]]; then
  pass "degraded mode — guazi handoff not required"
fi

mkdir -p "$HANDOFF_DIR" "$REPO_EVIDENCE_DIR" "$GOAL_EVIDENCE_DIR"


assert_pipeline_chain() {
  local exclude_stage="${1:-}"
  local validator="$SCRIPT_DIR/validate-pipeline-chain.sh"
  [[ -x "$validator" ]] || fail "validate-pipeline-chain.sh missing"
  local args=(--task-dir "$TASK_DIR")
  [[ -n "$STATE_FILE" ]] && args+=(--state-file "$STATE_FILE")
  [[ -n "$exclude_stage" ]] && args+=(--exclude-stage "$exclude_stage")
  if ! "$validator" "${args[@]}" >/dev/null 2>&1; then
    "$validator" "${args[@]}" 2>&1 | head -20 >&2 || true
    fail "pipeline chain invalid — fix before gate --post $STAGE"
  fi
}


sync_index_current_stage() {
  local next_stage="$1"
  [[ -f "$INDEX" ]] || return 0
  python3 - "$INDEX" "$next_stage" << 'PYSYNC'
import re, sys
path, new_stage = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
if not text.startswith("---"):
    sys.exit(0)
m = re.match(r"^(---\s*\n)(.*?)(\n---\s*\n)(.*)$", text, re.DOTALL)
if not m:
    sys.exit(0)
pre, fm, mid, body = m.groups()
lines = fm.splitlines()
out = []
in_flow = False
cs_done = False
for line in lines:
    if line.strip() == "flow:":
        in_flow = True
        out.append(line)
        continue
    if in_flow and line.startswith("  ") and line.strip().startswith("current_stage:"):
        out.append(f"  current_stage: {new_stage}")
        cs_done = True
        continue
    if not in_flow and line.strip().startswith("current_stage:"):
        out.append(f"current_stage: {new_stage}")
        cs_done = True
        continue
    if in_flow and line and not line.startswith("  ") and line.strip():
        in_flow = False
    out.append(line)
if not cs_done:
    if any(l.strip() == "flow:" for l in lines):
        idx = next(i for i, l in enumerate(out) if l.strip() == "flow:")
        out.insert(idx + 1, f"  current_stage: {new_stage}")
    else:
        out.insert(0, f"current_stage: {new_stage}")
open(path, "w", encoding="utf-8").write(pre + "\n".join(out) + mid + body)
PYSYNC
}

resolve_quality_tier() {
  if [[ -n "$STATE_FILE" && -f "$STATE_FILE" ]]; then
    python3 - "$STATE_FILE" << 'PYTIER'
import json, sys
state = json.load(open(sys.argv[1]))
tier = (state.get("quality_policy") or {}).get("tier") or "standard"
print(tier)
PYTIER
    return
  fi
  echo "standard"
}

pq_issues_to_gate_json() {
  python3 - "$1" << 'PYISS'
import json, sys
data = json.load(open(sys.argv[1]))
out = []
for i in data.get("issues", []):
    sev = "blocker" if i.get("severity") == "block" else "warning"
    out.append({"id": i.get("id", "PQ"), "severity": sev, "summary": i.get("message", ""), "root_cause": "plan_quality"})
print(json.dumps(out, ensure_ascii=False))
PYISS
}

stage_to_index_current() {
  case "$1" in
    plan) echo "implement" ;;
    implement) echo "quality" ;;
    quality) echo "review" ;;
    smoke) echo "review" ;;
    review) echo "complete" ;;
    complete) echo "complete" ;;
    *) echo "$1" ;;
  esac
}


update_state_gate() {
  local stage="$1"
  local handoff_file="$HANDOFF_DIR/${stage}.json"
  [[ -n "$STATE_FILE" && -f "$STATE_FILE" && -f "$handoff_file" ]] || return 0
  python3 - "$STATE_FILE" "$stage" "$handoff_file" << 'PYSTATE'
import json, sys, hashlib
from datetime import datetime, timezone
state_path, stage, handoff_path = sys.argv[1:4]
with open(state_path, encoding='utf-8') as f:
    state = json.load(f)
handoff_hash = hashlib.sha256(open(handoff_path, 'rb').read()).hexdigest()[:16]
passed_at = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
stages = state.setdefault('guazi_flow_stages', {})
entry = stages.setdefault(stage, {})
entry['used'] = True
entry['skill'] = entry.get('skill', f'guazi-flow-{stage}')
entry['gate'] = {
    'script': 'gate-guazi-flow-stage.sh',
    'version': 1,
    'passed_at': passed_at,
    'handoff_hash': handoff_hash,
    'post_exit_code': 0,
}
gates = state.setdefault('gates', {})
gates.setdefault(stage, {})['post'] = {'exit_code': 0, 'passed_at': passed_at}
_next = {'plan': 'implement', 'implement': 'quality', 'quality': 'review', 'smoke': 'review', 'review': 'complete', 'complete': 'complete'}
state['current_stage'] = _next.get(stage, stage)
with open(state_path, 'w', encoding='utf-8') as f:
    json.dump(state, f, indent=2, ensure_ascii=False)
PYSTATE
}


case "$STAGE" in
  plan)
    if [[ "$PHASE" == "pre" ]]; then
      pass "plan pre — no prior handoff required"
    fi
    [[ -f "$INDEX" ]] || fail "index.md not found"
    RESULT=$(py_check_index)
    OK=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['ok'])")
    if [[ "$OK" != "True" ]]; then
      ERRS=$(echo "$RESULT" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['errors']))")
      IH=$(content_hash "$INDEX")
      export GATE_ERRORS_JSON="$ERRS"
      ISSUES=$(errors_to_issues_json)
      gate_fail_with_issues "plan" "$IH" "fix_and_rerun" "$ISSUES" "plan index schema validation failed"
    fi
    if [[ "$PHASE" == "post" ]]; then
      IH_PRE=$(index_contract_hash "$INDEX")
      if [[ -n "$STATE_FILE" && -f "$STATE_FILE" && -f "$SCRIPT_DIR/quality_policy_tier.py" ]]; then
        python3 "$SCRIPT_DIR/quality_policy_tier.py" \
          --task-dir "$TASK_DIR" \
          --state-file "$STATE_FILE" \
          --persist \
          --json >/dev/null 2>&1 || true
      fi
      TIER=$(resolve_quality_tier)
      PQ_JSON=$(mktemp)
      if ! python3 "$SCRIPT_DIR/plan-quality-gate.py" --task-dir "$TASK_DIR" --tier "$TIER" --json > "$PQ_JSON" 2>/dev/null; then
        PQ_ISSUES=$(pq_issues_to_gate_json "$PQ_JSON")
        gate_fail_with_issues "plan" "$IH_PRE" "fix_and_rerun" "$PQ_ISSUES" "plan-quality-gate failed (PQ firewall)"
      fi
      rm -f "$PQ_JSON"
      WS=$(echo "$RESULT" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['write_set']))")
      WS=$(normalize_write_set_json "$WS")
      AM=$(echo "$RESULT" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['acceptance_matrix_ids']))")
      PROF=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('profile',''))")
      PD=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('profile_detail',''))")
      IH=$(index_contract_hash "$INDEX")
      EH=$(index_execution_tail_hash "$INDEX")
      # Keep legacy index_schema_hash = contract hash for older consumers
      GH=$(git_head_short)
      VERIF="{}"
      if [[ -f "$INDEX_HASH_PY" ]]; then
        VERIF=$(python3 - "$INDEX" "$INDEX_HASH_PY" << 'PYVER'
import json, sys, importlib.util
index_path, helper = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("index_contract_hash", helper)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
text = open(index_path, encoding="utf-8").read()
print(json.dumps(mod.extract_verification_hints(text), ensure_ascii=False))
PYVER
) || VERIF="{}"
      fi
      TMP=$(mktemp)
      cat > "$TMP" << JSON
{
  "stage": "plan",
  "schema_version": 1,
  "skill_expected": "guazi-flow-plan",
  "skill_executed": true,
  "task_dir": "$TASK_DIR",
  "profile": "$PROF",
  "profile_detail": "$PD",
  "write_set": $WS,
  "write_set_normalized": true,
  "acceptance_matrix_ids": $AM,
  "index_contract_hash": "$IH",
  "index_execution_tail_hash": "$EH",
  "index_schema_hash": "$IH",
  "verification": $VERIF,
  "git_head": "$GH",
  "artifact_paths": ["index.md"],
  "warnings": []
}
JSON
      py_write_handoff plan "$TMP" >/dev/null
      rm -f "$TMP"
      update_state_gate "plan"
      sync_index_current_stage "$(stage_to_index_current plan)"
      assert_pipeline_chain
    fi
    pass "plan gate"
    ;;

  implement)
    [[ -f "$HANDOFF_DIR/plan.json" ]] || fail "plan handoff missing — run gate --post plan first"
    [[ -f "$INDEX" ]] || fail "index.md not found"
    grep -q 'guazi-flow-implement' "$INDEX" || fail "index execution record missing guazi-flow-implement"
    PLAN_WS=$(python3 -c "import json; print(json.dumps(json.load(open('$HANDOFF_DIR/plan.json')).get('write_set',[])))" 2>/dev/null || echo '[]')
    if [[ "$PLAN_WS" != "[]" && -n "$GIT_ROOT" ]]; then
      cd "$GIT_ROOT"
      SUB=$(check_write_set_subset "$PLAN_WS")
      SUBOK=$(echo "$SUB" | python3 -c "import json,sys; print(json.load(sys.stdin)['ok'])")
      if [[ "$SUBOK" != "True" ]]; then
        echo "$SUB" | python3 -c "import json,sys; print('out of scope:', json.load(sys.stdin)['out_of_scope'])" >&2
        fail "changed files not subset of write_set"
      fi
    fi
    if [[ "$PHASE" == "post" ]]; then
      TIER=$(resolve_quality_tier)
      REPO_FOR_UVO="${GIT_ROOT:-$PROJECT_ROOT}"
      export GOAL_HANDOFF_DIR="$HANDOFF_DIR"
      export GOAL_EVIDENCE_DIR="$GOAL_EVIDENCE_DIR"
      UVO="$SCRIPT_DIR/verification-oracle.sh"
      [[ -x "$UVO" ]] || fail "verification-oracle.sh not found"
      UVO_ARGS=(--task-dir "$TASK_DIR" --repo-root "$REPO_FOR_UVO" --tier "$TIER")
      [[ -n "$STATE_FILE" ]] && UVO_ARGS+=(--state-file "$STATE_FILE")
      [[ -n "$PROJECT_ROOT" ]] && UVO_ARGS+=(--project-root "$PROJECT_ROOT")
      if ! "$UVO" "${UVO_ARGS[@]}" >/dev/null 2>&1; then
        DH_PRE=$(diff_hash)
        UVO_OUT=$("$UVO" "${UVO_ARGS[@]}" 2>/dev/null || echo '{"overall":"not_pass"}')
        UVO_ISSUES=$(python3 - "$UVO_OUT" << 'PYUVO'
import json, sys
try:
    data = json.loads(sys.argv[1])
except json.JSONDecodeError:
    data = {"overall": "not_pass"}
out = [{"id": "UVO-01", "severity": "block", "message": f"verification-oracle {data.get('overall','not_pass')}", "root_cause": "implement_qc"}]
for s in data.get("steps", []):
    if s.get("ok") is False or s.get("pass") is False:
        out.append({"id": f"UVO-{s.get('id','step')}", "severity": "block", "message": str(s.get("output_tail", s.get("output", "failed")))[:200], "root_cause": "implement_qc"})
print(json.dumps(out, ensure_ascii=False))
PYUVO
)
        gate_fail_with_issues "implement" "$DH_PRE" "fix_and_rerun" "$UVO_ISSUES" "verification-oracle failed (UVO)"
      fi
      RATCHET="$SCRIPT_DIR/acceptance-matrix-ratchet.py"
      if [[ -f "$RATCHET" ]]; then
        RAT_ARGS=(--task-dir "$TASK_DIR" --repo-root "$REPO_FOR_UVO" --evidence-dir "$GOAL_EVIDENCE_DIR" --json)
        if ! python3 "$RATCHET" "${RAT_ARGS[@]}" >/dev/null 2>&1; then
          gate_fail_with_issues "implement" "$(code_subject_hash)" "fix_and_rerun" '[{"id":"AM-01","severity":"blocker","summary":"acceptance-matrix-ratchet failed","root_cause":"implement_error"}]' "acceptance-matrix-ratchet not_pass"
        fi
      fi
      # IQ thin wrapper: structural checks only (UVO evidence already written)
      IQ_JSON=$(mktemp)
      if ! python3 "$SCRIPT_DIR/implement-qc-gate.py" --task-dir "$TASK_DIR" --repo-root "$REPO_FOR_UVO" --tier "$TIER" --skip-test-lint --json > "$IQ_JSON" 2>/dev/null; then
        DH_PRE=$(diff_hash)
        IQ_ISSUES=$(python3 - "$IQ_JSON" << 'PYIQ'
import json, sys
data = json.load(open(sys.argv[1]))
out = []
for i in data.get("issues", []):
    sev = "blocker" if i.get("severity") == "block" else "warning"
    out.append({"id": i.get("id", "IQ"), "severity": sev, "summary": i.get("message", ""), "root_cause": "implement_qc"})
print(json.dumps(out, ensure_ascii=False))
PYIQ
)
        rm -f "$IQ_JSON"
        gate_fail_with_issues "implement" "$DH_PRE" "fix_and_rerun" "$IQ_ISSUES" "implement-qc-gate structural check failed"
      fi
      rm -f "$IQ_JSON"
      PLAN_WS_LEN=$(python3 -c "import json; print(len(json.load(open('$HANDOFF_DIR/plan.json')).get('write_set',[])))" 2>/dev/null || echo 0)
      if [[ "$PLAN_WS_LEN" == "0" ]]; then
        DH=$(diff_hash)
        ISSUES='[{"id":"G001","severity":"blocker","summary":"write_set 为空 — 在 index.md ## 范围与写集 或 ## 写集 中声明路径","root_cause":"plan_gap","criterion_ref":"unified-doc-contract §write_set"}]'
        gate_fail_with_issues "implement" "$DH" "fix_and_rerun" "$ISSUES" "plan write_set empty — update index.md before implement post"
      fi
      CHANGED=$(check_write_set_subset "$PLAN_WS")
      CF=$(echo "$CHANGED" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin).get('changed_files',[])))")
      DH=$(code_subject_hash)
      ART_HASH=$(python3 - "$GIT_ROOT" "$REPO_TASK_DIR" << 'PYAH' 2>/dev/null || echo "unknown"
import importlib.util, os, sys
gate_script = os.environ.get('GATE_SCRIPT_DIR', '')
path = os.path.join(gate_script, 'verification_oracle_core.py')
spec = importlib.util.spec_from_file_location('uvo', path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(mod.artifact_diff_hash(sys.argv[1], sys.argv[2]))
PYAH
)
      GH=$(git_head_short)
      UVO_GH=$(python3 -c "import json; print(json.load(open('$GOAL_EVIDENCE_DIR/verification-oracle.json')).get('git_head',''))" 2>/dev/null || echo "")
      UVO_DH=$(python3 -c "import json; print(json.load(open('$GOAL_EVIDENCE_DIR/verification-oracle.json')).get('code_subject_hash', json.load(open('$GOAL_EVIDENCE_DIR/verification-oracle.json')).get('candidate_diff_hash','')))" 2>/dev/null || echo "")
      TMP=$(mktemp)
      cat > "$TMP" << JSON
{
  "stage": "implement",
  "schema_version": 1,
  "skill_expected": "guazi-flow-implement",
  "skill_executed": true,
  "write_set": $PLAN_WS,
  "changed_files": $CF,
  "git_head": "$GH",
  "candidate_diff_hash": "$DH",
  "code_subject_hash": "$DH",
  "artifact_hash": "$ART_HASH",
  "uvo_git_head": "$UVO_GH",
  "uvo_diff_hash": "$UVO_DH",
  "artifact_paths": ["index.md", "evidence/verification-oracle.json"]
}
JSON
      py_write_handoff implement "$TMP" >/dev/null
      rm -f "$TMP"
      update_state_gate "implement"
      sync_index_current_stage "$(stage_to_index_current implement)"
      assert_pipeline_chain
    fi
    pass "implement gate"
    ;;


  quality)
    if [[ "$PHASE" == "pre" ]]; then
      [[ -f "$HANDOFF_DIR/implement.json" ]] || fail "implement handoff missing — run implement gate --post first"
      pass "quality pre"
    fi
    SMOKE_MD="$GOAL_EVIDENCE_DIR/runtime-smoke.md"
    REPO_FOR_QG="${GIT_ROOT:-$PROJECT_ROOT}"
    TIER=$(resolve_quality_tier)
    SMOKE_REQUIRED=$(python3 - "$TASK_DIR" "$REPO_FOR_QG" "$TIER" "$SCRIPT_DIR" << 'PYSR'
import importlib.util, os, sys
_, task_dir, repo, tier, gs = sys.argv
path = os.path.join(gs, "verification_oracle_core.py")
spec = importlib.util.spec_from_file_location("uvo", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
plan = mod.load_plan_handoff(task_dir)
ws = mod._write_set_from_plan(plan, task_dir)
changed = mod.git_changed_files(repo)
print("yes" if mod.smoke_required(changed, ws, tier) else "no")
PYSR
)
    if [[ "$SMOKE_REQUIRED" == "yes" && ! -f "$SMOKE_MD" ]]; then
      fail "evidence/runtime-smoke.md missing — pattern requires smoke (App.tsx/routes/config-overrides/package.json)"
    fi
    if [[ "$SMOKE_REQUIRED" == "no" && ! -f "$SMOKE_MD" ]]; then
      mkdir -p "$GOAL_EVIDENCE_DIR"
      cat > "$SMOKE_MD" << SMYAML
---
result: skipped
classification: build_sufficient
reason: smoke_not_required_by_pattern
dev_cmd: ""
duration_ms: 0
---
# runtime-smoke skipped

UVO build passed; changed files did not match smoke-required patterns.
SMYAML
    fi
    QG_ARGS=(--task-dir "$TASK_DIR" --repo-root "$REPO_FOR_QG" --tier "$TIER" --skip-iq)
    [[ "$SMOKE_REQUIRED" == "no" ]] && QG_ARGS+=(--skip-smoke)
    if [[ "$PHASE" == "post" ]]; then
      assert_pipeline_chain quality
    fi
    if ! bash "$SCRIPT_DIR/quality-gate.sh" "${QG_ARGS[@]}"; then
      QH=$(content_hash "$SMOKE_MD")
      ISSUES='[{"id":"QG-01","severity":"blocker","summary":"quality-gate.sh failed","root_cause":"quality_gate"}]'
      gate_fail_with_issues "quality" "$QH" "fix_and_rerun" "$ISSUES" "quality gate failed"
    fi
    if [[ "$PHASE" == "post" ]]; then
      GH=$(git_head_short)
      SMOKE_RESULT="unknown"
      if [[ -f "$SMOKE_MD" ]]; then
        SMOKE_RESULT=$(python3 - "$SMOKE_MD" << 'PYSR2'
import re, sys
t = open(sys.argv[1]).read()
m = re.match(r"^---\s*\n(.*?)\n---", t, re.DOTALL)
if m:
    for line in m.group(1).splitlines():
        if line.strip().startswith("result:"):
            print(line.split(":",1)[1].strip().strip(chr(34))); break
else:
    print("unknown")
PYSR2
)
      fi
      TMP=$(mktemp)
      cat > "$TMP" << JSON
{
  "stage": "quality",
  "schema_version": 1,
  "skill_expected": "goal-quality",
  "skill_executed": true,
  "tier": "$TIER",
  "smoke_result": "$SMOKE_RESULT",
  "git_head": "$GH",
  "artifact_paths": ["evidence/runtime-smoke.md"],
  "runtime_artifact_paths": ["evidence/runtime-smoke.md"]
}
JSON
      py_write_handoff quality "$TMP" >/dev/null
      rm -f "$TMP"
      update_state_gate "quality"
      sync_index_current_stage "$(stage_to_index_current quality)"
      assert_pipeline_chain
    fi
    pass "quality gate"
    ;;


  smoke)
    if [[ "$PHASE" == "pre" ]]; then
      [[ -f "$HANDOFF_DIR/implement.json" ]] || fail "implement handoff missing — run implement gate --post first"
    fi
    SMOKE_MD="$GOAL_EVIDENCE_DIR/runtime-smoke.md"
    [[ -f "$SMOKE_MD" ]] || fail "evidence/runtime-smoke.md missing — run runtime-smoke.sh"
    SRESULT=$(python3 - "$SMOKE_MD" << 'PYSMOKE'
import re, sys
t = open(sys.argv[1]).read()
m = re.match(r"^---\s*\n(.*?)\n---", t, re.DOTALL)
fm = {}
if m:
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            fm[k.strip()] = v.strip().strip(chr(34))
print(fm.get("result", "unknown"))
PYSMOKE
)
    if [[ "$SRESULT" == "unknown" ]]; then
      fail "runtime-smoke.md missing valid result frontmatter"
    fi
    if [[ "$SRESULT" == "not_pass" ]]; then
      CLS=$(python3 - "$SMOKE_MD" << 'PYCLS'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"classification:\s*(\S+)", t)
print(m.group(1) if m else "")
PYCLS
)
      [[ -n "$CLS" && "$CLS" != "none" ]] || fail "smoke not_pass requires classification field"
    fi
    if [[ "$PHASE" == "post" ]]; then
      GH=$(git_head_short)
      SMOKE_META=$(python3 - "$SMOKE_MD" << 'PYMETA'
import re, sys, json
t = open(sys.argv[1]).read()
def grab(key, default=""):
    m = re.search(rf"^{key}:\\s*(.+)$", t, re.M)
    return m.group(1).strip().strip('"') if m else default
print(json.dumps({
    "dev_cmd": grab("dev_cmd"),
    "classification": grab("classification", "none"),
    "duration_ms": int(grab("duration_ms", "0") or 0),
}))
PYMETA
)
      DEV_CMD=$(echo "$SMOKE_META" | python3 -c "import json,sys; print(json.load(sys.stdin).get('dev_cmd',''))")
      CLASSIFICATION=$(echo "$SMOKE_META" | python3 -c "import json,sys; print(json.load(sys.stdin).get('classification','none'))")
      DURATION=$(echo "$SMOKE_META" | python3 -c "import json,sys; print(json.load(sys.stdin).get('duration_ms',0))")
      TMP=$(mktemp)
      cat > "$TMP" << JSON
{
  "stage": "smoke",
  "schema_version": 1,
  "result": "$SRESULT",
  "classification": "$CLASSIFICATION",
  "dev_cmd": "$DEV_CMD",
  "duration_ms": $DURATION,
  "git_head": "$GH",
  "artifact_paths": [],
  "runtime_artifact_paths": ["evidence/runtime-smoke.md"]
}
JSON
      py_write_handoff smoke "$TMP" >/dev/null
      rm -f "$TMP"
      update_state_gate "smoke"
      sync_index_current_stage "$(stage_to_index_current smoke)"
    fi
    pass "smoke gate"
    ;;

  review)
    if [[ "$PHASE" == "pre" ]]; then
      [[ -f "$HANDOFF_DIR/implement.json" ]] || fail "implement handoff missing"
      [[ -f "$HANDOFF_DIR/plan.json" ]] || fail "plan handoff missing"
      FRESH=$(python3 - "$INDEX" "$HANDOFF_DIR/plan.json" "$INDEX_HASH_PY" << 'PYFRESH'
import json, sys, importlib.util, os
index_path, plan_path, helper = sys.argv[1], sys.argv[2], sys.argv[3]
plan = json.load(open(plan_path, encoding="utf-8"))
if os.path.isfile(helper):
    spec = importlib.util.spec_from_file_location("index_contract_hash", helper)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    print(json.dumps(mod.compare_plan_freshness(index_path, plan), ensure_ascii=False))
else:
    print(json.dumps({"contract_changed": False, "fresh": True, "execution_changed": False}))
PYFRESH
) || FRESH='{"contract_changed":false,"fresh":true}'
      CONTRACT_CHANGED=$(echo "$FRESH" | python3 -c "import json,sys; print(json.load(sys.stdin).get('contract_changed', False))" 2>/dev/null || echo "False")
      if [[ "$CONTRACT_CHANGED" == "True" ]]; then
        REFRESH="$SCRIPT_DIR/refresh-handoffs-after-index.sh"
        MSG="plan handoff stale — index_contract_hash mismatch (contract changed; mini-replan required)"
        if [[ -x "$REFRESH" ]]; then
          MSG="$MSG — run: $REFRESH --task-dir '$REPO_TASK_DIR' --state-file '${STATE_FILE:-}' --project-root '${PROJECT_ROOT:-}'"
        fi
        fail "$MSG"
      fi
      # Auto-assemble review packet if missing (P0-D)
      if [[ ! -f "$HANDOFF_DIR/review-packet.json" ]]; then
        ASSEMBLE="$SCRIPT_DIR/assemble-review-packet.sh"
        if [[ -x "$ASSEMBLE" ]]; then
          echo "gate WARN [review/pre]: review-packet.json missing — auto-assembling" >&2
          ASSEMBLE_ARGS=(--task-dir "$REPO_TASK_DIR")
          [[ -n "$STATE_FILE" ]] && ASSEMBLE_ARGS+=(--state-file "$STATE_FILE")
          [[ -n "$PROJECT_ROOT" ]] && ASSEMBLE_ARGS+=(--project-root "$PROJECT_ROOT")
          "$ASSEMBLE" "${ASSEMBLE_ARGS[@]}" >/dev/null || fail "auto assemble-review-packet failed"
        else
          fail "review-packet.json missing — run assemble-review-packet.sh"
        fi
      fi
      VERIFY_REV="$SCRIPT_DIR/verify-review.sh"
      [[ -x "$VERIFY_REV" ]] || fail "verify-review.sh not found"
      UVO="$SCRIPT_DIR/verification-oracle.sh"
      REPO_FOR_REV="${GIT_ROOT:-$PROJECT_ROOT}"
      [[ -n "$REPO_FOR_REV" ]] || REPO_FOR_REV="$(pwd)"
      export GOAL_HANDOFF_DIR="$HANDOFF_DIR"
      export GOAL_EVIDENCE_DIR="$GOAL_EVIDENCE_DIR"
      UVO_CHECK_ARGS=(--task-dir "$TASK_DIR" --repo-root "$REPO_FOR_REV" --check-freshness)
      [[ -n "$STATE_FILE" ]] && UVO_CHECK_ARGS+=(--state-file "$STATE_FILE")
      [[ -n "$PROJECT_ROOT" ]] && UVO_CHECK_ARGS+=(--project-root "$PROJECT_ROOT")
      if ! "$UVO" "${UVO_CHECK_ARGS[@]}" >/dev/null 2>&1; then
        fail "verification-oracle evidence missing or stale — rerun gate --post implement"
      fi
      WS=$(python3 -c "import json; print(','.join(json.load(open('$HANDOFF_DIR/plan.json')).get('write_set',[])))" 2>/dev/null || echo "")
      export GOAL_SKIP_TEST=1 GOAL_SKIP_BUILD=1 GOAL_SKIP_LINT=1
      VOUT=$("$VERIFY_REV" "$TASK_DIR" "$WS" json 2>/dev/null || echo '{"overall":"not_pass"}')
      unset GOAL_SKIP_TEST GOAL_SKIP_BUILD GOAL_SKIP_LINT
      VOK=$(echo "$VOUT" | python3 -c "import json,sys; d=json.load(sys.stdin); c=d.get('checks',d); print('pass' if c.get('scope',{}).get('pass') and c.get('secret',{}).get('pass') else 'not_pass')" 2>/dev/null || echo "not_pass")
      [[ "$VOK" == "pass" ]] || fail "review-pre scope/secret check not pass"
      PREFLIGHT="$SCRIPT_DIR/review_packet_preflight.py"
      if [[ -f "$PREFLIGHT" ]]; then
        PF_ARGS=(--packet "$HANDOFF_DIR/review-packet.json" --uvo "$GOAL_EVIDENCE_DIR/verification-oracle.json")
        if ! python3 "$PREFLIGHT" "${PF_ARGS[@]}" >/dev/null 2>&1; then
          python3 "$PREFLIGHT" "${PF_ARGS[@]}" --json 2>&1 | head -20 >&2 || true
          fail "review-packet preflight failed (PKT-01/02/03)"
        fi
      fi
      pass "review gate"
    fi
    if [[ "$PHASE" == "post" ]]; then
      RRESULT=$(py_check_review)
      ROK=$(echo "$RRESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['ok'])")
      if [[ "$ROK" != "True" ]]; then
        echo "$RRESULT" | python3 -c "import json,sys; [print('  -',e) for e in json.load(sys.stdin)['errors']]" >&2
        show_review_issue_board
        fail "review evidence validation failed"
      fi
      RESULT_VAL=$(echo "$RRESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('result','unknown'))")
      RSH=$(echo "$RRESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('review_subject_hash',''))")
      GH=$(git_head_short)
      # stale check: src implementation diff changed since implement (evidence writes ignored)
      CUR_CSH=$(code_subject_hash)
      IMP_CSH=$(python3 -c "import json; d=json.load(open('$HANDOFF_DIR/implement.json')); print(d.get('code_subject_hash') or d.get('candidate_diff_hash',''))" 2>/dev/null || echo "")
      if [[ -n "$IMP_CSH" && "$IMP_CSH" != "$CUR_CSH" && "$IMP_CSH" != "unknown" && "$CUR_CSH" != "unknown" ]]; then
        fail "review stale — code_subject_hash changed since implement handoff"
      fi
      GOAL_COUNT=0
      if [[ -f "$GOAL_EVIDENCE_DIR/review-unified.json" ]]; then
        GOAL_COUNT=$(python3 - "$GOAL_EVIDENCE_DIR/review-unified.json" << 'PYGC'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
issues = d.get("issues", [])
print(sum(1 for i in issues if i.get("channel", "goal") != "guazi-flow-review"))
PYGC
)
      fi
      GF_COUNT=$(read_gf_issues_count)
      GF_ATTESTED=$(python3 -c "import json; d=json.load(open('$GOAL_EVIDENCE_DIR/review-fix-input.json')); print(str(d.get('provenance',{}).get('gf_skill_attested',False)).lower())" 2>/dev/null || echo "false")
      RUN_ID=$(python3 -c "import json; print(json.load(open('$GOAL_EVIDENCE_DIR/review-run.json')).get('run_id',''))" 2>/dev/null || echo "")
      TMP=$(mktemp)
      cat > "$TMP" << JSON
{
  "stage": "review",
  "schema_version": 1,
  "result": "$RESULT_VAL",
  "review_subject_hash": "$RSH",
  "git_head": "$GH",
  "issues_gf_count": $GF_COUNT,
  "issues_goal_count": $GOAL_COUNT,
  "gf_execution_mode": "independent_unified_review",
  "gf_skill_attested": $GF_ATTESTED,
  "review_run_id": "$RUN_ID",
  "root_cause_summary": {},
  "artifact_paths": ["evidence/review.md"],
  "runtime_artifact_paths": ["evidence/review-unified.json", "evidence/review-fix-input.json", "evidence/review-run.json"]
}
JSON
      py_write_handoff review "$TMP" >/dev/null
      rm -f "$TMP"
      assert_pipeline_chain
      [[ -f "$GOAL_EVIDENCE_DIR/review-run.json" ]] || fail "review-run.json missing — run run-independent-review.sh"
      RUN_DOWNGRADE=$(python3 - << 'PY' "$GOAL_EVIDENCE_DIR/review-run.json"
import json, sys
run = json.load(open(sys.argv[1], encoding="utf-8"))
guard = run.get("channel_guard") or {}
if not guard:
    print("skip")
elif guard.get("has_candidates") and run.get("provider") == "deterministic":
    print("blocked")
else:
    print("ok")
PY
)
      if [[ "$RUN_DOWNGRADE" == "blocked" ]]; then
        fail "review provider downgrade blocked — review-run.json provider=deterministic but channel_guard.has_candidates=true; rerun goal-run-review-chain.sh"
      fi
      RUN_HASH=$(python3 -c "import json; print(json.load(open('$GOAL_EVIDENCE_DIR/review-run.json')).get('packet_hash',''))" 2>/dev/null || echo "")
      PKT_HASH=$(shasum -a 256 "$HANDOFF_DIR/review-packet.json" 2>/dev/null | cut -c1-16 || sha256sum "$HANDOFF_DIR/review-packet.json" 2>/dev/null | cut -c1-16 || echo "")
      if [[ -n "$RUN_HASH" && -n "$PKT_HASH" && "$RUN_HASH" != "$PKT_HASH" ]]; then
        fail "review-run packet_hash does not match review-packet.json"
      fi
      UNIFIED_RES=$(python3 -c "import json; print(json.load(open('$GOAL_EVIDENCE_DIR/review-unified.json')).get('result',''))" 2>/dev/null || echo "")
      if [[ "$UNIFIED_RES" == "review_undetermined" ]]; then
        fail "review separation_confidence low — use cursor-task/claude-native provider"
      fi
      MERGED=$(python3 - "$REPO_EVIDENCE_DIR/review.md" << 'PYMG'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"merged_result:\s*(\S+)", t)
print(m.group(1) if m else "")
PYMG
)
      if [[ -n "$MERGED" && "$MERGED" != "pass" ]]; then
        show_review_issue_board
        CUR_DH=$(diff_hash)
        check_noop_ratchet "review" "$CUR_DH" || exit 1
        fail "merged_result is not pass: $MERGED"
      fi
      CLEN=$(python3 -c "import json; d=json.load(open('$GOAL_EVIDENCE_DIR/review-unified.json')); print(len(d.get('checklist_goal',[])))" 2>/dev/null || echo 0)
      [[ -f "$GOAL_EVIDENCE_DIR/review-fix-input.json" ]] || fail "review-fix-input.json missing — run merge-review-issues.sh"
      python3 - "$GOAL_EVIDENCE_DIR/review-fix-input.json" << 'PYSCHEMA' || fail "review-fix-input.json schema invalid"
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
required = ["schema_version", "round", "merged_result", "action", "issues", "next_steps", "provenance"]
for k in required:
    if k not in d:
        raise SystemExit(f"missing field: {k}")
actions = {"proceed_complete", "fix_and_rerun_review", "mini_replan", "blocked_user_decision"}
if d["action"] not in actions:
    raise SystemExit(f"invalid action: {d['action']}")
if d["merged_result"] not in ("pass", "not_pass"):
    raise SystemExit("invalid merged_result")
if d["merged_result"] == "pass" and d["action"] != "proceed_complete":
    raise SystemExit("pass requires proceed_complete")
if d["merged_result"] == "not_pass" and d["action"] == "proceed_complete":
    raise SystemExit("not_pass cannot proceed_complete")
PYSCHEMA

      FIX_ACTION=$(python3 -c "import json; print(json.load(open('$GOAL_EVIDENCE_DIR/review-fix-input.json')).get('action',''))" 2>/dev/null || echo "")
      FIX_MERGED=$(python3 -c "import json; print(json.load(open('$GOAL_EVIDENCE_DIR/review-fix-input.json')).get('merged_result',''))" 2>/dev/null || echo "")
      if [[ "$FIX_MERGED" != "$MERGED" && -n "$MERGED" && -n "$FIX_MERGED" ]]; then
        fail "review-fix-input merged_result mismatch with review.md"
      fi
      if [[ "$RESULT_VAL" == "pass" && "$FIX_ACTION" != "proceed_complete" ]]; then
        fail "review pass requires review-fix-input action=proceed_complete"
      fi
      if [[ "$RESULT_VAL" == "pass" && "$CLEN" -lt 1 ]]; then
        fail "review pass requires non-empty checklist_goal in review-unified.json"
      fi
      if [[ "$RESULT_VAL" != "pass" ]]; then
        show_review_issue_board
        CUR_DH=$(diff_hash)
        check_noop_ratchet "review" "$CUR_DH" || exit 1
        fail "review result is not pass: $RESULT_VAL"
      fi
      update_state_gate "review"
      sync_index_current_stage "$(stage_to_index_current review)"
    fi
    pass "review gate"
    ;;

  complete)
    if [[ "$PHASE" == "pre" ]]; then
      [[ -f "$HANDOFF_DIR/review.json" ]] || fail "review handoff missing"
      RRES=$(python3 -c "import json; print(json.load(open('$HANDOFF_DIR/review.json')).get('result',''))" 2>/dev/null || echo "")
      [[ "$RRES" == "pass" ]] || fail "review handoff result not pass"
    fi
    [[ -f "$INDEX" ]] || fail "index.md not found"
    grep -q 'guazi-flow-complete' "$INDEX" || fail "execution record missing guazi-flow-complete"
    grep -qE 'current_stage:\s*complete|flow\.current_stage.*complete' "$INDEX" || fail "index current_stage not complete"
    # review still fresh
    if [[ -f "$EVIDENCE_DIR/review.md" ]]; then
      RRESULT=$(py_check_review)
      ROK=$(echo "$RRESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['ok'])")
      RES=$(echo "$RRESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('result',''))")
      [[ "$ROK" == "True" && "$RES" == "pass" ]] || fail "evidence/review.md not pass+fresh"
    else
      fail "evidence/review.md missing for complete"
    fi
    if [[ "$PHASE" == "post" ]]; then
      assert_pipeline_chain
      TMP=$(mktemp)
      cat > "$TMP" << JSON
{
  "stage": "complete",
  "schema_version": 1,
  "skill_expected": "guazi-flow-complete",
  "skill_executed": true,
  "completed_actions": ["guazi-flow-complete"],
  "residual_risks": [],
  "artifact_paths": ["index.md", "evidence/review.md"]
}
JSON
      py_write_handoff complete "$TMP" >/dev/null
      rm -f "$TMP"
      update_state_gate "complete"
      sync_index_current_stage "$(stage_to_index_current complete)"
    fi
    pass "complete gate"
    ;;
esac
