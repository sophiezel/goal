#!/usr/bin/env bash
# test-kernel-review-cli-parity.sh — shell review chain vs kernel.review.cli run (#23)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${GUAZI_SCRIPTS:-${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts}"
CLI="${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/kernel/review/cli.py"
FIX="$DIR/review-unified-good"
REC="$SCRIPTS/record-pipeline-timing.py"
SYNC="$SCRIPTS/sync_timing_substeps.py"

bootstrap_task() {
  local root="$1"
  mkdir -p "$root/repo/docs/guazi-flow/fixture-task" "$root/repo/src"
  cp -R "$FIX/." "$root/repo/docs/guazi-flow/fixture-task/"
  echo 'export const x=1' >"$root/repo/src/a.ts"
  (
    cd "$root/repo"
    git init -q
    git config user.email fixture@test
    git config user.name fixture
    git add .
    git commit -qm init
  )
  echo 'export const x=2' >"$root/repo/src/a.ts"
  cat >"$root/repo/docs/guazi-flow/fixture-task/evidence/verification-oracle.json" <<'JSON'
{"overall":"pass","steps":[{"id":"unit","duration_ms":50}]}
JSON
  echo "$root/repo/docs/guazi-flow/fixture-task"
}

norm_json() {
  python3 - "$1" <<'PY'
import json, sys
path = sys.argv[1]
d = json.load(open(path, encoding="utf-8"))
if path.endswith("review-fix-input.json"):
    prov = dict(d.get("provenance") or {})
    prov.pop("review_run_id", None)
    prov.pop("packet_hash", None)
    keys = ("merged_result", "action", "classification", "blocker_count", "issues")
    out = {k: d[k] for k in keys if k in d}
    if prov:
        out["provenance"] = prov
    print(json.dumps(out, sort_keys=True, ensure_ascii=False))
else:
    print(json.dumps(d, sort_keys=True, ensure_ascii=False))
PY
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

TASK_SHELL=$(bootstrap_task "$TMP/shell")
TASK_CLI=$(bootstrap_task "$TMP/cli")
PROJ_SHELL="$TMP/shell/repo"
PROJ_CLI="$TMP/cli/repo"

run_parity() {
  GOAL_ARTIFACT_MODE=repo_full GOAL_REVIEW_PROVIDER=mock-unified GOAL_REVIEW_MODE=unified "$@"
}

echo "=== shell path: assemble + run-independent-review + merge-review-issues ==="
run_parity bash "$SCRIPTS/assemble-review-packet.sh" --task-dir "$TASK_SHELL" --project-root "$PROJ_SHELL" >/dev/null
run_parity bash "$SCRIPTS/run-independent-review.sh" \
  --task-dir "$TASK_SHELL" --project-root "$PROJ_SHELL" --provider mock-unified --mode unified >/dev/null
run_parity bash "$SCRIPTS/merge-review-issues.sh" --task-dir "$TASK_SHELL" --project-root "$PROJ_SHELL" \
  --unified-json "$TASK_SHELL/evidence/review-unified.json" >/dev/null

echo "=== CLI path: kernel.review.cli run (assemble + invoke + merge + timing sync) ==="
run_parity python3 "$REC" --task-dir "$TASK_CLI" --project-root "$PROJ_CLI" --stage review --event start >/dev/null
run_parity python3 "$CLI" run --task-dir "$TASK_CLI" --project-root "$PROJ_CLI" >/dev/null

FIX_SHELL="$TASK_SHELL/evidence/review-fix-input.json"
FIX_CLI="$TASK_CLI/evidence/review-fix-input.json"
MERGE_SHELL="$TASK_SHELL/handoff/merge-result.json"
MERGE_CLI="$TASK_CLI/handoff/merge-result.json"
[[ -f "$FIX_SHELL" && -f "$FIX_CLI" && -f "$MERGE_SHELL" && -f "$MERGE_CLI" ]] || {
  echo "FAIL missing parity artifacts"
  exit 1
}

NS=$(norm_json "$FIX_SHELL")
NC=$(norm_json "$FIX_CLI")
[[ "$NS" == "$NC" ]] || {
  echo "FAIL review-fix-input parity"
  echo "shell: $NS"
  echo "cli:   $NC"
  exit 1
}
MS=$(norm_json "$MERGE_SHELL")
MC=$(norm_json "$MERGE_CLI")
[[ "$MS" == "$MC" ]] || {
  echo "FAIL merge-result.json parity"
  echo "shell: $MS"
  echo "cli:   $MC"
  exit 1
}

TIMING="$TASK_CLI/evidence/pipeline-timing.json"
[[ -f "$TIMING" ]] || { echo "FAIL pipeline-timing.json missing after CLI run"; exit 1; }
python3 - "$TIMING" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
ms = d.get("stages", {}).get("review", {}).get("substeps", {}).get("attempt", {}).get("duration_ms", 0)
assert ms > 0, f"review attempt substep not synced: {d.get('stages', {}).get('review', {})}"
print(f"timing_review_attempt_ms={ms}")
PY

# Chain still calls sync_timing_substeps after CLI — guard regression (same env as review chain)
SYNC_OUT=$(run_parity python3 "$SYNC" --task-dir "$TASK_SHELL" --project-root "$PROJ_SHELL" --source review)
echo "$SYNC_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('marks_recorded',0)>=1, d"
[[ -f "$TASK_SHELL/evidence/pipeline-timing.json" ]] || {
  echo "FAIL shell-side timing sync after merge (chain parity)"
  exit 1
}

echo "test-kernel-review-cli-parity passed"
