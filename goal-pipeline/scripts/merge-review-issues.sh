#!/bin/bash
# merge-review-issues.sh — Merge issues_gf + issues_goal into evidence/review.md annex
# Usage: merge-review-issues.sh --task-dir <path> --goal-json <review-goal.json> [--root-cause-json <file>]

set -euo pipefail

TASK_DIR=""
GOAL_JSON=""
ROOT_CAUSE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-dir) TASK_DIR="$2"; shift 2 ;;
    --goal-json) GOAL_JSON="$2"; shift 2 ;;
    --root-cause-json) ROOT_CAUSE="$2"; shift 2 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$TASK_DIR" && -n "$GOAL_JSON" ]] || { echo "Usage: $0 --task-dir <path> --goal-json <file>" >&2; exit 2; }
[[ "$TASK_DIR" != /* ]] && TASK_DIR="$(pwd)/$TASK_DIR"
REVIEW="$TASK_DIR/evidence/review.md"

python3 - "$TASK_DIR" "$GOAL_JSON" "$ROOT_CAUSE" "$REVIEW" << 'PY'
import json, re, sys, os
from datetime import datetime, timezone

task_dir, goal_json, root_cause_path, review_path = sys.argv[1:5]
goal = json.load(open(goal_json, encoding='utf-8'))
issues_goal = goal.get('issues', goal.get('issues_goal', []))
result_goal = goal.get('result', 'not_pass' if issues_goal else 'pass')

root_cause = {}
if root_cause_path and os.path.isfile(root_cause_path):
    root_cause = json.load(open(root_cause_path, encoding='utf-8'))

# Parse gf result from review.md frontmatter
gf_result = 'unknown'
gf_issues = 0
text = open(review_path, encoding='utf-8').read() if os.path.isfile(review_path) else ''
fm = {}
m = re.match(r'^---\s*\n(.*?)\n---', text, re.DOTALL)
if m:
    for line in m.group(1).splitlines():
        if ':' in line:
            k, v = line.split(':', 1)
            fm[k.strip()] = v.strip().strip('"')
    gf_result = fm.get('result', 'unknown')

merged_result = 'pass' if gf_result == 'pass' and result_goal == 'pass' and not issues_goal else 'not_pass'

annex = f"""
## Goal Pipeline Review

_merged at {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}_

**goal_result**: {result_goal}
**merged_result**: {merged_result}

### issues_goal

| ID | Severity | Summary | Root cause |
|----|----------|---------|------------|
"""
for i, issue in enumerate(issues_goal, 1):
    iid = issue.get('id', f'G{i:02d}')
    sev = issue.get('severity', 'medium')
    summ = issue.get('summary', issue.get('message', str(issue)))[:200]
    rc = issue.get('root_cause', '')
    annex += f"| {iid} | {sev} | {summ} | {rc} |\n"

if root_cause:
    annex += f"\n### root_cause_summary\n\n```json\n{json.dumps(root_cause, indent=2, ensure_ascii=False)}\n```\n"

# Replace or append annex
if '## Goal Pipeline Review' in text:
    text = re.sub(r'\n## Goal Pipeline Review.*', annex, text, flags=re.DOTALL)
else:
    text = text.rstrip() + annex

# Update frontmatter merged result if present
if m and 'merged_result' not in fm:
    new_fm = m.group(1).rstrip() + f"\nmerged_result: {merged_result}\n"
    text = '---\n' + new_fm + '---' + text[m.end():]

os.makedirs(os.path.dirname(review_path), exist_ok=True)
with open(review_path, 'w', encoding='utf-8') as f:
    f.write(text)

out = os.path.join(task_dir, 'handoff', 'merge-result.json')
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, 'w', encoding='utf-8') as f:
    json.dump({
        'merged_result': merged_result,
        'gf_result': gf_result,
        'goal_result': result_goal,
        'issues_goal_count': len(issues_goal),
        'root_cause_summary': root_cause,
    }, f, indent=2, ensure_ascii=False)

print(json.dumps({'merged_result': merged_result, 'path': review_path}))
PY
