#!/bin/bash
# gate-guazi-flow-stage.sh — Hard gate for guazi-flow-goal stages
# Usage: gate-guazi-flow-stage.sh --task-dir <path> --stage plan|implement|smoke|review|complete [--pre|--post] [--mode guazi|degraded]
# Exit 0 = pass, 1 = fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
  echo "Usage: $0 --task-dir <path> --stage plan|implement|smoke|review|complete [--pre|--post] [--mode guazi|degraded]" >&2
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
    echo "gate assert-complete: pipeline complete"
    exit 0
  fi
  echo "gate assert-complete: pipeline incomplete — next_stage=$NEXT" >&2
  echo "$OUT"
  exit 2
fi

[[ -n "$TASK_DIR" && -n "$STAGE" ]] || usage
case "$STAGE" in plan|implement|smoke|review|complete) ;; *) echo "Invalid stage: $STAGE" >&2; exit 2 ;; esac

# Resolve paths
if [[ "$TASK_DIR" != /* ]]; then
  TASK_DIR="$(pwd)/$TASK_DIR"
fi
TASK_DIR="$(cd "$TASK_DIR" 2>/dev/null && pwd)" || { echo "gate: task dir not found: $TASK_DIR" >&2; exit 1; }

INDEX="$TASK_DIR/index.md"
HANDOFF_DIR="$TASK_DIR/handoff"
EVIDENCE_DIR="$TASK_DIR/evidence"
GIT_ROOT=$(git -C "$TASK_DIR" rev-parse --show-toplevel 2>/dev/null || git -C "$(dirname "$TASK_DIR")" rev-parse --show-toplevel 2>/dev/null || echo "")

fail() { echo "gate FAIL [$STAGE/$PHASE]: $*" >&2; exit 1; }
pass() { echo "gate PASS [$STAGE/$PHASE]: $*"; exit 0; }

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

diff_hash() {
  if [[ -n "$GIT_ROOT" ]]; then
    git -C "$GIT_ROOT" diff HEAD 2>/dev/null | shasum -a 256 2>/dev/null | cut -c1-16 || echo "unknown"
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

# extract write_set from markdown tables or bullet lists
write_set = []
ws_sec = re.search(r'##\s*(?:write[_\s-]?set|写集)[^\n]*\n(.*?)(?=\n## |\Z)', text, re.IGNORECASE | re.DOTALL)
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
  local gf_json="$EVIDENCE_DIR/review-gf.json"
  if [[ -f "$gf_json" ]]; then
    python3 -c "import json; d=json.load(open('$gf_json')); print(len(d.get('issues',[])))" 2>/dev/null || echo 0
    return
  fi
  python3 - "$EVIDENCE_DIR/review.md" << 'PYGF'
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
PYGF
}

py_check_review() {
  python3 - "$EVIDENCE_DIR/review.md" "$SCHEMA_DIR/review-evidence-rules.json" "$EVIDENCE_DIR/review-goal.json" << 'PY'
import json, re, sys, os
review_path, rules_path, goal_json = sys.argv[1], sys.argv[2], sys.argv[3]
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

has_goal = '## Goal Pipeline Review' in text or os.path.isfile(goal_json)
if not has_goal:
    errors.append("missing goal-pipeline review annex (## Goal Pipeline Review or review-goal.json)")

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
    modified = subprocess.check_output(['git', 'diff', '--name-only', 'HEAD'], text=True).splitlines()
    untracked = subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard'], text=True).splitlines()
    all_files = [f for f in modified + untracked if f.strip()]
except Exception:
    all_files = []
out = []
for f in all_files:
    allowed = any(f == w or f.startswith(w.rstrip('/') + '/') or f.startswith(w) for w in write_set)
    if not allowed:
        out.append(f)
print(json.dumps({"ok": len(out) == 0, "out_of_scope": out, "changed_files": all_files}))
PY
}

# === Degraded mode: skip guazi-specific checks ===
if [[ "$MODE" == "degraded" ]]; then
  pass "degraded mode — guazi handoff not required"
fi

mkdir -p "$HANDOFF_DIR"


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
}
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
      echo "$RESULT" | python3 -c "import json,sys; [print('  -',e) for e in json.load(sys.stdin)['errors']]" >&2
      fail "plan index schema validation failed"
    fi
    if [[ "$PHASE" == "post" ]]; then
      WS=$(echo "$RESULT" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['write_set']))")
      AM=$(echo "$RESULT" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['acceptance_matrix_ids']))")
      PROF=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('profile',''))")
      PD=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('profile_detail',''))")
      IH=$(content_hash "$INDEX")
      GH=$(git_head_short)
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
  "acceptance_matrix_ids": $AM,
  "index_schema_hash": "$IH",
  "git_head": "$GH",
  "artifact_paths": ["index.md"],
  "warnings": []
}
JSON
      py_write_handoff plan "$TMP" >/dev/null
      rm -f "$TMP"
      update_state_gate "plan"
    fi
    pass "plan gate"
    ;;

  implement)
    if [[ "$PHASE" == "pre" ]]; then
      [[ -f "$HANDOFF_DIR/plan.json" ]] || fail "plan handoff missing — run plan gate --post first"
    fi
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
      CHANGED=$(check_write_set_subset "$PLAN_WS")
      CF=$(echo "$CHANGED" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin).get('changed_files',[])))")
      DH=$(diff_hash)
      GH=$(git_head_short)
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
  "artifact_paths": ["index.md"]
}
JSON
      py_write_handoff implement "$TMP" >/dev/null
      rm -f "$TMP"
      update_state_gate "implement"
    fi
    pass "implement gate"
    ;;


  smoke)
    if [[ "$PHASE" == "pre" ]]; then
      [[ -f "$HANDOFF_DIR/implement.json" ]] || fail "implement handoff missing — run implement gate --post first"
    fi
    SMOKE_MD="$EVIDENCE_DIR/runtime-smoke.md"
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
  "artifact_paths": ["evidence/runtime-smoke.md"]
}
JSON
      py_write_handoff smoke "$TMP" >/dev/null
      rm -f "$TMP"
      update_state_gate "smoke"
    fi
    pass "smoke gate"
    ;;

  review)
    if [[ "$PHASE" == "pre" ]]; then
      [[ -f "$HANDOFF_DIR/implement.json" ]] || fail "implement handoff missing"
      IH=$(content_hash "$INDEX")
      STORED=$(python3 -c "import json; d=json.load(open('$HANDOFF_DIR/plan.json')); print(d.get('index_schema_hash',''))" 2>/dev/null || echo "")
      if [[ -n "$STORED" && "$STORED" != "$IH" ]]; then
        fail "plan handoff stale — index_schema_hash mismatch (mini-replan required?)"
      fi
      [[ -f "$HANDOFF_DIR/review-packet.json" ]] || fail "review-packet.json missing — run assemble-review-packet.sh"
      VERIFY_REV="$SCRIPT_DIR/verify-review.sh"
      [[ -x "$VERIFY_REV" ]] || fail "verify-review.sh not found"
      WS=$(python3 -c "import json; print(','.join(json.load(open('$HANDOFF_DIR/plan.json')).get('write_set',[])))" 2>/dev/null || echo "")
      VOUT=$("$VERIFY_REV" "$TASK_DIR" "$WS" json 2>/dev/null || echo '{"overall":"not_pass"}')
      VOK=$(echo "$VOUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('overall','not_pass'))" 2>/dev/null || echo "not_pass")
      [[ "$VOK" == "pass" ]] || fail "verify-review pre-check not pass"
    fi
    RRESULT=$(py_check_review)
    ROK=$(echo "$RRESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['ok'])")
    if [[ "$ROK" != "True" ]]; then
      echo "$RRESULT" | python3 -c "import json,sys; [print('  -',e) for e in json.load(sys.stdin)['errors']]" >&2
      fail "review evidence validation failed"
    fi
    if [[ "$PHASE" == "post" ]]; then
      RESULT_VAL=$(echo "$RRESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('result','unknown'))")
      RSH=$(echo "$RRESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('review_subject_hash',''))")
      GH=$(git_head_short)
      # stale check: implement diff changed since review
      CUR_DH=$(diff_hash)
      IMP_DH=$(python3 -c "import json; print(json.load(open('$HANDOFF_DIR/implement.json')).get('candidate_diff_hash',''))" 2>/dev/null || echo "")
      if [[ -n "$IMP_DH" && "$IMP_DH" != "$CUR_DH" ]]; then
        fail "review stale — candidate_diff_hash changed since implement handoff"
      fi
      GOAL_COUNT=0
      if [[ -f "$EVIDENCE_DIR/review-goal.json" ]]; then
        GOAL_COUNT=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/review-goal.json')); print(len(d.get('issues', d.get('issues_goal', []))))" 2>/dev/null || echo 0)
      fi
      GF_COUNT=$(read_gf_issues_count)
      GF_ATTESTED=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/review-fix-input.json')); print(str(d.get('provenance',{}).get('gf_skill_attested',False)).lower())" 2>/dev/null || echo "false")
      RUN_ID=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/review-run.json')).get('run_id',''))" 2>/dev/null || echo "")
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
  "gf_execution_mode": "independent_dual_channel",
  "gf_skill_attested": $GF_ATTESTED,
  "review_run_id": "$RUN_ID",
  "root_cause_summary": {},
  "artifact_paths": ["evidence/review.md", "evidence/review-goal.json", "evidence/review-fix-input.json"]
}
JSON
      py_write_handoff review "$TMP" >/dev/null
      rm -f "$TMP"
      [[ -f "$EVIDENCE_DIR/review-run.json" ]] || fail "review-run.json missing — run run-independent-review.sh"
      RUN_HASH=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/review-run.json')).get('packet_hash',''))" 2>/dev/null || echo "")
      PKT_HASH=$(shasum -a 256 "$HANDOFF_DIR/review-packet.json" 2>/dev/null | cut -c1-16 || sha256sum "$HANDOFF_DIR/review-packet.json" 2>/dev/null | cut -c1-16 || echo "")
      if [[ -n "$RUN_HASH" && -n "$PKT_HASH" && "$RUN_HASH" != "$PKT_HASH" ]]; then
        fail "review-run packet_hash does not match review-packet.json"
      fi
      GOAL_RES=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/review-goal.json')).get('result',''))" 2>/dev/null || echo "")
      if [[ "$GOAL_RES" == "review_undetermined" ]]; then
        fail "review separation_confidence low — use cursor-task/claude-native provider"
      fi
      MERGED=$(python3 - "$EVIDENCE_DIR/review.md" << 'PYMG'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"merged_result:\s*(\S+)", t)
print(m.group(1) if m else "")
PYMG
)
      if [[ -n "$MERGED" && "$MERGED" != "pass" ]]; then
        fail "merged_result is not pass: $MERGED"
      fi
      CLEN=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/review-goal.json')); print(len(d.get('checklist',[])))" 2>/dev/null || echo 0)
      [[ -f "$EVIDENCE_DIR/review-fix-input.json" ]] || fail "review-fix-input.json missing — run merge-review-issues.sh"
      FIX_ACTION=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/review-fix-input.json')).get('action',''))" 2>/dev/null || echo "")
      FIX_MERGED=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/review-fix-input.json')).get('merged_result',''))" 2>/dev/null || echo "")
      if [[ "$FIX_MERGED" != "$MERGED" && -n "$MERGED" && -n "$FIX_MERGED" ]]; then
        fail "review-fix-input merged_result mismatch with review.md"
      fi
      if [[ "$RESULT_VAL" == "pass" && "$FIX_ACTION" != "proceed_complete" ]]; then
        fail "review pass requires review-fix-input action=proceed_complete"
      fi
      if [[ "$RESULT_VAL" == "pass" && "$CLEN" -lt 1 ]]; then
        fail "review pass requires non-empty checklist in review-goal.json"
      fi
      if [[ "$RESULT_VAL" != "pass" ]]; then
        fail "review result is not pass: $RESULT_VAL"
      fi
      update_state_gate "review"
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
    fi
    pass "complete gate"
    ;;
esac
