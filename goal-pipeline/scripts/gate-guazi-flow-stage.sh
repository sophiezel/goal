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
  # Quality plane is mandatory on every complete path (not only kernel complete).
  QPC="$SCRIPT_DIR/quality_plane_check.py"
  if [[ -f "$QPC" && -n "$TASK_DIR" ]]; then
    QPC_ARGS=(--task-dir "$TASK_DIR" --state-file "$STATE_FILE" --mode complete)
    [[ -n "$PROJECT_ROOT" ]] && QPC_ARGS+=(--project-root "$PROJECT_ROOT")
    if ! python3 "$QPC" "${QPC_ARGS[@]}" >/dev/null 2>&1; then
      python3 "$QPC" "${QPC_ARGS[@]}" --format text >&2 || true
      echo "gate assert-complete: quality_plane_check failed" >&2
      exit 1
    fi
  fi
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
      python3 - "$STATE_FILE" "$SCRIPT_DIR" << 'PYDONE'
import json, sys
from datetime import datetime, timezone
path = sys.argv[1]
sys.path.insert(0, sys.argv[2])
from atomic_json import write_state_atomic
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
    write_state_atomic(path, state)
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
  python3 - "$STATE_FILE" "$code" "$SCRIPT_DIR" << 'PYBLOCK'
import json, sys
from datetime import datetime, timezone
path, code = sys.argv[1], sys.argv[2]
sys.path.insert(0, sys.argv[3])
from atomic_json import write_state_atomic
with open(path, encoding="utf-8") as f:
    state = json.load(f)
state["status"] = "blocked"
state["failure_code"] = code
state["blocked_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
write_state_atomic(path, state)
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
    echo "noop_fix: DO NOT rerun the same gate command. Apply a substantive fix first." >&2
    echo "noop_fix: recommended_fix_command — read $fix_path next_steps; change subject then re-gate" >&2
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
  local _rules_path="$SCHEMA_DIR/plan-index-rules.json"
  local _plan_json="$HANDOFF_DIR/plan.json"
  if [[ -f "$SCRIPT_DIR/resolve_plan_index_rules.py" ]]; then
    _rules_path=$(python3 "$SCRIPT_DIR/resolve_plan_index_rules.py" --index "$INDEX" --plan-json "$_plan_json" --format path 2>/dev/null || echo "$SCHEMA_DIR/plan-index-rules.json")
  fi
  python3 - "$INDEX" "$_rules_path" "$_plan_json" << 'PY'
import json, os, re, sys
index_path, rules_path, plan_json_path = sys.argv[1], sys.argv[2], sys.argv[3]
rules = json.load(open(rules_path))
text = open(index_path, encoding='utf-8').read()
errors = []

# plan_profile (from rules file or frontmatter)
plan_profile = rules.get('plan_profile', 'full')

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
# Do NOT pull bullets from "不做项/排除/exclusions" subsections — they contaminate path_allowed.
write_set = []
ws_matches = list(re.finditer(
    r'^##\s*(?:范围与写集|write[_\s-]?set|写集)\s*\n(.*?)(?=\n## |\Z)',
    text, re.IGNORECASE | re.DOTALL | re.MULTILINE
))
ws_sec = ws_matches[-1] if ws_matches else None
_excl = re.compile(r'(排除|除外|不做|exclude|exclusion|out of scope|非写集)', re.I)
if ws_sec:
    block = ws_sec.group(1)
    # Truncate at first exclusions / 不做 subsection inside the write_set section
    cut = re.search(r'^###?\s*(?:不做|排除|除外|exclusions?|out of scope).*$', block, re.I | re.M)
    if cut:
        block = block[: cut.start()]
    for line in block.splitlines():
        if _excl.search(line) and not re.search(r'`[^`]+`', line):
            continue
        for m in re.findall(r'`([^`]+)`', line):
            write_set.append(m.strip())
        m2 = re.match(r'[-*]\s+(.+)', line.strip())
        if m2:
            val = m2.group(1).strip().strip('`')
            if val and not val.startswith('|') and not _excl.search(val):
                write_set.append(val)
# Drop prose / exclusion contamination; keep path-like entries only
def _looks_like_path(p: str) -> bool:
    p = (p or "").strip().strip("`")
    if not p or _excl.search(p):
        return False
    if any(x in p for x in ("排除", "除外", "不做", "：", "。")):
        return False
    return ("/" in p) or p.endswith((".ts", ".tsx", ".js", ".jsx", ".scss", ".css", ".json", ".md")) or p.startswith(("src", "docs", "e2e", "config"))

write_set = list(dict.fromkeys([w for w in write_set if _looks_like_path(w)]))
if not write_set:
    for pat in [r'write_set:\s*\[([^\]]+)\]']:
        wm = re.search(pat, text, re.IGNORECASE)
        if wm:
            write_set = [x.strip().strip('"\'') for x in wm.group(1).split(',') if x.strip() and _looks_like_path(x)]

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
    "plan_profile": plan_profile,
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

# Auto-stage untracked files under write_set (no commit) so code_subject_hash / AM-01 see them.
stage_write_set_untracked() {
  local write_set_json="$1"
  [[ -n "$GIT_ROOT" && -d "$GIT_ROOT/.git" ]] || return 0
  [[ -n "$write_set_json" && "$write_set_json" != "[]" ]] || return 0
  python3 - "$GIT_ROOT" "$write_set_json" << 'PY'
import json, os, subprocess, sys
root, ws_json = sys.argv[1], sys.argv[2]
try:
    write_set = json.loads(ws_json)
except json.JSONDecodeError:
    sys.exit(0)
if not write_set:
    sys.exit(0)

def allowed(path, write_set):
    for raw in write_set:
        w = (raw or "").strip().rstrip("/")
        if w.endswith("/**"):
            w = w[:-3].rstrip("/")
        if not w:
            continue
        if path == w or path.startswith(w + "/"):
            return True
    return False

try:
    untracked = subprocess.check_output(
        ["git", "-C", root, "-c", "core.quotepath=false", "ls-files", "--others", "--exclude-standard"],
        text=True, stderr=subprocess.DEVNULL,
    ).splitlines()
except (OSError, subprocess.CalledProcessError):
    sys.exit(0)
to_add = [f for f in untracked if f.strip() and allowed(f.strip(), write_set)]
if not to_add:
    sys.exit(0)
# Cap batch size; never commit — only git add
subprocess.run(["git", "-C", root, "add", "--"] + to_add[:200], check=False,
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print(f"stage_write_set_untracked: staged {min(len(to_add), 200)} file(s)", file=sys.stderr)
PY
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


record_stage_timing() {
  local stage="$1"
  local event="${2:-end}"
  local substep="${3:-}"
  local duration_ms="${4:-}"
  local timing_py="$SCRIPT_DIR/record-pipeline-timing.py"
  [[ -f "$timing_py" && -n "$TASK_DIR" ]] || return 0
  local targs=(--task-dir "$TASK_DIR" --stage "$stage" --event "$event")
  [[ -n "$substep" ]] && targs+=(--substep "$substep")
  [[ -n "$duration_ms" ]] && targs+=(--duration-ms "$duration_ms")
  [[ -n "$STATE_FILE" ]] && targs+=(--state-file "$STATE_FILE")
  [[ -n "$PROJECT_ROOT" ]] && targs+=(--project-root "$PROJECT_ROOT")
  python3 "$timing_py" "${targs[@]}" >/dev/null 2>&1 || true
}

update_state_gate() {
  local stage="$1"
  local handoff_file="$HANDOFF_DIR/${stage}.json"
  record_stage_timing "$stage" "end"
  [[ -n "$STATE_FILE" && -f "$STATE_FILE" && -f "$handoff_file" ]] || return 0
  python3 - "$STATE_FILE" "$stage" "$handoff_file" "$SCRIPT_DIR" << 'PYSTATE'
import json, sys, hashlib
from datetime import datetime, timezone
state_path, stage, handoff_path = sys.argv[1:4]
sys.path.insert(0, sys.argv[4])
from atomic_json import write_state_atomic
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
write_state_atomic(state_path, state)
PYSTATE
}


# Fail-closed: plan gate not passed ⇒ forbid write_set / src diffs (see assert-plan-before-code.sh).
run_plan_before_code_guard() {
  local require_plan="${1:-0}"
  local assert_sh="$SCRIPT_DIR/assert-plan-before-code.sh"
  [[ -f "$assert_sh" ]] || return 0
  local td="${REPO_TASK_DIR:-$TASK_DIR}"
  [[ -n "$td" && -d "$td" ]] || fail "plan_code_order: task-dir required for assert-plan-before-code"
  local assert_args=(--task-dir "$td" --mode json)
  [[ -n "$PROJECT_ROOT" ]] && assert_args+=(--project-root "$PROJECT_ROOT")
  [[ -n "$STATE_FILE" && -f "$STATE_FILE" ]] && assert_args+=(--state-file "$STATE_FILE")
  [[ "$require_plan" == "1" ]] && assert_args+=(--require-plan-passed)
  local assert_out assert_rc=0
  assert_out=$(bash "$assert_sh" "${assert_args[@]}" 2>&1) || assert_rc=$?
  if [[ "$assert_rc" -eq 2 ]]; then
    local detail
    detail=$(printf '%s' "$assert_out" | python3 -c "
import json,sys
raw=sys.stdin.read()
try:
  d=json.loads(raw)
  print(d.get('message') or d.get('failure_code') or 'plan_code_order')
except Exception:
  print((raw or 'plan_code_order: src dirty before plan gate')[:500])
")
    write_state_blocked "plan_code_order" 2>/dev/null || true
    fail "plan_code_order: $detail — stash/reset guarded diffs, then complete gate --post plan before writing code"
  fi
  return 0
}

# Pair with update_state_gate → end. Optional substips: record_stage_timing STAGE mark|end SUBSTEP MS
record_stage_timing "$STAGE" "start"

case "$STAGE" in
  plan)
    # shellcheck source=gate-lib/plan.sh
    source "$SCRIPT_DIR/gate-lib/plan.sh"
    ;;
  implement)
    # shellcheck source=gate-lib/implement.sh
    source "$SCRIPT_DIR/gate-lib/implement.sh"
    ;;
  quality)
    # shellcheck source=gate-lib/quality.sh
    source "$SCRIPT_DIR/gate-lib/quality.sh"
    ;;
  smoke)
    # shellcheck source=gate-lib/smoke.sh
    source "$SCRIPT_DIR/gate-lib/smoke.sh"
    ;;
  review)
    # shellcheck source=gate-lib/review.sh
    source "$SCRIPT_DIR/gate-lib/review.sh"
    ;;
  complete)
    # shellcheck source=gate-lib/complete.sh
    source "$SCRIPT_DIR/gate-lib/complete.sh"
    ;;
esac
