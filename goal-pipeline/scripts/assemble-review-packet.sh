#!/bin/bash
# assemble-review-packet.sh — Build ReviewPacket for goal-pipeline independent review
# Usage: assemble-review-packet.sh --task-dir <path> [--state-dir <goal-state>] [--max-diff-bytes 80000]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR=""
STATE_DIR=""
STATE_FILE=""
PROJECT_ROOT=""
MAX_DIFF_BYTES=80000
MAX_PSEUDOCODE_CHARS=4000

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --state-dir) STATE_DIR="$2"; shift 2 ;;
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --max-diff-bytes) MAX_DIFF_BYTES="$2"; shift 2 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$TASK_DIR" ]] || { echo "Usage: $0 --task-dir <path>" >&2; exit 2; }
[[ "$TASK_DIR" != /* ]] && TASK_DIR="$(pwd)/$TASK_DIR"
TASK_DIR="$(cd "$TASK_DIR" && pwd)"

RESOLVER="$SCRIPT_DIR/resolve-artifact-paths.py"
_RESOLVE_ARGS=(--task-dir "$TASK_DIR" --format shell --ensure-state)
[[ -n "$STATE_FILE" ]] && _RESOLVE_ARGS+=(--state-file "$STATE_FILE")
[[ -n "$PROJECT_ROOT" ]] && _RESOLVE_ARGS+=(--project-root "$PROJECT_ROOT")
eval "$(python3 "$RESOLVER" "${_RESOLVE_ARGS[@]}")"

INDEX="$REPO_TASK_DIR/index.md"
HANDOFF_PLAN="$HANDOFF_DIR/plan.json"
HANDOFF_IMPL="$HANDOFF_DIR/implement.json"
EVIDENCE="$REPO_EVIDENCE_DIR"
OUT="$HANDOFF_DIR/review-packet.json"
GIT_ROOT=$(git -C "$REPO_TASK_DIR" rev-parse --show-toplevel 2>/dev/null || echo "")
VERIFY_SCRIPT="$SCRIPT_DIR/verify-review.sh"

mkdir -p "$HANDOFF_DIR"

export VERIFY_SCRIPT TASK_DIR INDEX HANDOFF_PLAN HANDOFF_IMPL EVIDENCE OUT MAX_DIFF_BYTES MAX_PSEUDOCODE_CHARS GIT_ROOT STATE_DIR REPO_TASK_DIR HANDOFF_DIR GOAL_EVIDENCE_DIR

python3 << 'PY'
import json, re, os, sys, subprocess, hashlib
from datetime import datetime, timezone

task_dir = os.environ['TASK_DIR']
index_path = os.environ['INDEX']
plan_path = os.environ['HANDOFF_PLAN']
impl_path = os.environ['HANDOFF_IMPL']
evidence_dir = os.environ['EVIDENCE']
out_path = os.environ['OUT']
max_diff = int(os.environ['MAX_DIFF_BYTES'])
max_pseudo = int(os.environ['MAX_PSEUDOCODE_CHARS'])
git_root = os.environ.get('GIT_ROOT', '')
state_dir = os.environ.get('STATE_DIR', '')
verify_script = os.environ.get('VERIFY_SCRIPT', '')

truncated = {}
errors = []

def load_json(p, default=None):
    if os.path.isfile(p):
        return json.load(open(p, encoding='utf-8'))
    return default if default is not None else {}

def sha16(data):
    if isinstance(data, str):
        data = data.encode('utf-8')
    return hashlib.sha256(data).hexdigest()[:16]

def path_allowed(path, allowed):
    for w in allowed:
        w = (w or '').strip().rstrip('/')
        if not w:
            continue
        if path == w or path.startswith(w + '/'):
            return True
    return False

def extract_section(text, heading):
    m = re.search(rf'{re.escape(heading)}\s*\n(.*?)(?=\n## |\Z)', text, re.DOTALL)
    return m.group(1).strip() if m else ''

def redact_secrets(text):
    patterns = [
        (r'(api[_-]?key\s*[=:]\s*)["\']?[\w-]{8,}', r'\1[REDACTED]'),
        (r'(password\s*[=:]\s*)["\'][^"\']+["\']', r'\1[REDACTED]'),
        (r'sk-[a-zA-Z0-9]{20,}', '[REDACTED]'),
        (r'ghp_[a-zA-Z0-9]{36}', '[REDACTED]'),
    ]
    for pat, repl in patterns:
        text = re.sub(pat, repl, text, flags=re.IGNORECASE)
    return text

plan = load_json(plan_path, {})
impl = load_json(impl_path, {})
write_set = plan.get('write_set', [])

if not os.path.isfile(index_path):
    errors.append('index.md missing')
    text = ''
else:
    text = open(index_path, encoding='utf-8').read()

pseudo = extract_section(text, '## 完整伪代码')
if len(pseudo) > max_pseudo:
    pseudo = pseudo[:max_pseudo] + '\n\n...[truncated]...'
    truncated['contract.pseudocode_summary'] = f'exceeded {max_pseudo} chars'

contract = {
    'goal': extract_section(text, '## 目标') or extract_section(text, '## 核心事实')[:2000],
    'scope': extract_section(text, '## 范围')[:2000],
    'design': extract_section(text, '## 设计与接口')[:3000],
    'acceptance_matrix': extract_section(text, '## 验收与验证矩阵')[:4000],
    'pseudocode_summary': pseudo,
}

diff_text = ''
if git_root:
    try:
        diff_text = subprocess.check_output(['git', '-C', git_root, '-c', 'core.quotepath=false', 'diff', 'HEAD'], text=True, stderr=subprocess.DEVNULL)
        untracked = subprocess.check_output(['git', '-C', git_root, '-c', 'core.quotepath=false', 'ls-files', '--others', '--exclude-standard'], text=True, stderr=subprocess.DEVNULL).splitlines()
        for f in untracked:
            if write_set and not path_allowed(f, write_set):
                continue
            fp = os.path.join(git_root, f)
            if os.path.isfile(fp):
                try:
                    content = open(fp, encoding='utf-8', errors='replace').read()
                    diff_text += f'\n--- new file: {f} ---\n{content}\n'
                except Exception:
                    pass
    except Exception:
        pass

if write_set and diff_text:
    lines = diff_text.splitlines(keepends=True)
    filtered = []
    include = False
    current_path = ''
    for line in lines:
        if line.startswith('diff --git '):
            parts = line.split()
            current_path = parts[-1].lstrip('b/') if len(parts) >= 4 else ''
            include = path_allowed(current_path, write_set) if current_path else False
        elif line.startswith('--- new file:'):
            m = re.search(r'--- new file:\s+(\S+)', line)
            current_path = m.group(1) if m else ''
            include = path_allowed(current_path, write_set) if current_path else False
        if include:
            filtered.append(line)
    diff_text = ''.join(filtered)

changed_files = list(impl.get('changed_files') or [])
if git_root and not changed_files:
    try:
        names = subprocess.check_output(
            ['git', '-C', git_root, '-c', 'core.quotepath=false', 'diff', '--name-only', 'HEAD'],
            text=True, stderr=subprocess.DEVNULL,
        ).splitlines()
        unt = subprocess.check_output(
            ['git', '-C', git_root, '-c', 'core.quotepath=false', 'ls-files', '--others', '--exclude-standard'],
            text=True, stderr=subprocess.DEVNULL,
        ).splitlines()
        changed_files = [n.strip() for n in names + unt if n.strip()]
    except Exception:
        pass
if write_set and changed_files:
    changed_files = [f for f in changed_files if path_allowed(f, write_set)]

diff_text = redact_secrets(diff_text)
if len(diff_text.encode('utf-8')) > max_diff:
    diff_text = diff_text[:max_diff] + '\n...[diff truncated]...'
    truncated['diff'] = f'exceeded {max_diff} bytes'

constraints = {'allowed_files': write_set, 'stop_conditions': [], 'agents_summary': ''}
if state_dir and os.path.isfile(os.path.join(state_dir, 'state.json')):
    st = load_json(os.path.join(state_dir, 'state.json'))
    constraints['allowed_files'] = st.get('allowed_files', write_set)
    constraints['stop_conditions'] = st.get('stop_conditions', [])

if git_root:
    agents_md = os.path.join(git_root, 'AGENTS.md')
    if os.path.isfile(agents_md):
        constraints['agents_summary'] = open(agents_md, encoding='utf-8').read()[:1500]

checklist = plan.get('acceptance_matrix_ids', []) or re.findall(r'\b(?:C|V|AC|TC)\d+\b', text)

deterministic = {}
uvo_path = os.path.join(os.environ.get('GOAL_EVIDENCE_DIR', evidence_dir), 'verification-oracle.json')
if os.path.isfile(uvo_path):
    try:
        uvo = json.load(open(uvo_path, encoding='utf-8'))
        deterministic = {
            'overall': uvo.get('overall', 'not_pass'),
            'checks': {
                'scope': next((s for s in uvo.get('steps', []) if s.get('id') == 'scope'), {}),
                'secret': next((s for s in uvo.get('steps', []) if s.get('id') == 'secret'), {}),
                'test': {'pass': uvo.get('overall') == 'pass'},
                'lint': next((s for s in uvo.get('steps', []) if s.get('id') == 'lint'), {}),
                'build': next((s for s in uvo.get('steps', []) if s.get('id') == 'build'), {}),
            },
            'provenance': 'verification-oracle.json',
            'oracle_mode': uvo.get('oracle_mode'),
            'git_head': uvo.get('git_head'),
        }
    except Exception as e:
        deterministic = {'overall': 'not_pass', 'error': str(e)}
else:
    deterministic = {'overall': 'not_pass', 'error': 'verification-oracle.json missing — run gate --post implement'}

reference_impl_diff = ''
ref_branch = plan.get('reference_branch') or plan.get('reference_impl_branch') or ''
ref_paths = plan.get('reference_impl_paths') or []
if ref_branch and git_root:
    try:
        ref_diff_args = ['git', '-C', git_root, 'diff', ref_branch, '--'] + (ref_paths if ref_paths else [])
        reference_impl_diff = subprocess.check_output(ref_diff_args, text=True, stderr=subprocess.DEVNULL)
        if len(reference_impl_diff.encode('utf-8')) > max_diff:
            reference_impl_diff = reference_impl_diff[:max_diff] + '\n...[reference diff truncated]...'
            truncated['reference_impl_diff'] = f'exceeded {max_diff} bytes'
    except Exception as e:
        reference_impl_diff = f'(reference diff unavailable: {e})'

issues_gf = []
review_md = os.path.join(evidence_dir, 'review.md')
if os.path.isfile(review_md):
    rt = open(review_md, encoding='utf-8').read()
    if '## 发现项' in rt:
        block = extract_section(rt, '## 发现项')
        for line in block.splitlines():
            if line.strip().startswith('|') and '---' not in line and 'ID' not in line.upper()[:10]:
                issues_gf.append({'raw': line.strip()[:500]})

smoke = {}
smoke_md = os.path.join(evidence_dir, 'runtime-smoke.md')
if os.path.isfile(smoke_md):
    st = open(smoke_md, encoding='utf-8').read()
    smoke = {'classification': 'unknown', 'excerpt': st[:1000]}
    for cls in ['environmental', 'code_issue', 'runtime_crash', 'pass']:
        if cls in st.lower():
            smoke['classification'] = cls
            break

git_head = impl.get('git_head', plan.get('git_head', 'unknown'))
candidate_diff_hash = impl.get('candidate_diff_hash', sha16(diff_text))
review_subject_hash = sha16(diff_text + git_head)

hashes = {
    'candidate_diff_hash': candidate_diff_hash,
    'review_subject_hash': review_subject_hash,
    'git_head': git_head,
    'index_schema_hash': plan.get('index_schema_hash', ''),
}

if not os.path.isfile(plan_path):
    errors.append('handoff/plan.json missing')
if not os.path.isfile(impl_path):
    errors.append('handoff/implement.json missing')


# guazi-flow rubric excerpt from index + SKILL summary
gf_skill_path = os.path.join(git_root, '.agents', 'skills', 'guazi-flow-review', 'SKILL.md') if git_root else ''
if not os.path.isfile(gf_skill_path):
    for cand in [os.path.expanduser('~/.agents/skills/guazi-flow-review/SKILL.md'),
                 os.path.join(os.path.dirname(verify_script or ''), '..', '..', 'guazi-flow-review', 'SKILL.md')]:
        if os.path.isfile(cand):
            gf_skill_path = cand
            break
gf_skill_excerpt = ''
if gf_skill_path and os.path.isfile(gf_skill_path):
    gf_skill_excerpt = open(gf_skill_path, encoding='utf-8').read()[:2500]
guazi_flow_rubric = {
    'acceptance_matrix_excerpt': contract.get('acceptance_matrix', '')[:2000],
    'pseudocode_excerpt': contract.get('pseudocode_summary', '')[:2000],
    'skill_summary': gf_skill_excerpt[:2500],
    'rubric_hash': sha16((contract.get('acceptance_matrix', '') + gf_skill_excerpt)[:4000]),
}
goal_checklist = [
    {'id': 'goal_achieved', 'priority': 'P0', 'question': '候选 diff 是否达成任务契约验收标准？'},
    {'id': 'scope_compliant', 'priority': 'P0', 'question': '修改是否在 Allowed Files 白名单内？'},
    {'id': 'evidence_sufficient', 'priority': 'P1', 'question': '验证命令是否运行且结论有 diff 支撑？'},
    {'id': 'side_effects', 'priority': 'P1', 'question': '是否新增依赖/配置/权限？'},
    {'id': 'completeness', 'priority': 'P1', 'question': '是否有未验证路径标记完成？'},
    {'id': 'security', 'priority': 'P0', 'question': '是否泄漏 secret/token？'},
]

packet = {
    'schema_version': 1,
    'assembled_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'task_dir': task_dir,
    'contract': contract,
    'diff': diff_text,
    'reference_impl_diff': reference_impl_diff,
    'reference_branch': ref_branch,
    'constraints': constraints,
    'verification_checklist': checklist,
    'deterministic_checks': deterministic,
    'changed_files': changed_files,
    'issues_gf': issues_gf[:50],
    'guazi_flow_rubric': guazi_flow_rubric,
    'goal_checklist': goal_checklist,
    'smoke_diagnostic': smoke,
    'hashes': hashes,
    'truncated': truncated,
    'integrity': {
        'plan_handoff_present': os.path.isfile(plan_path),
        'implement_handoff_present': os.path.isfile(impl_path),
        'errors': errors,
        'ok': len(errors) == 0,
    },
}

with open(out_path, 'w', encoding='utf-8') as f:
    json.dump(packet, f, indent=2, ensure_ascii=False)

if not packet['integrity']['ok']:
    print(json.dumps({'ok': False, 'errors': errors}), file=sys.stderr)
    sys.exit(1)

print(out_path)
PY
