# gate-lib/quality.sh — stage body for gate-guazi-flow-stage.sh (sourced in case)
# Relies on parent functions/vars: fail/pass/INDEX/HANDOFF_DIR/PHASE/etc.
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
    # Always pass state context — avoid cross-branch / wrong-handoff discovery (B1 incident).
    [[ -n "$STATE_FILE" ]] && QG_ARGS+=(--state-file "$STATE_FILE")
    [[ -n "$PROJECT_ROOT" ]] && QG_ARGS+=(--project-root "$PROJECT_ROOT")
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
      TIMING_SYNC="$SCRIPT_DIR/sync_timing_substeps.py"
      if [[ -f "$TIMING_SYNC" ]]; then
        SYNC_ARGS=(--task-dir "$TASK_DIR" --source smoke)
        [[ -n "$STATE_FILE" ]] && SYNC_ARGS+=(--state-file "$STATE_FILE")
        [[ -n "$PROJECT_ROOT" ]] && SYNC_ARGS+=(--project-root "$PROJECT_ROOT")
        python3 "$TIMING_SYNC" "${SYNC_ARGS[@]}" >/dev/null 2>&1 || true
      fi
      update_state_gate "quality"
      sync_index_current_stage "$(stage_to_index_current quality)"
      assert_pipeline_chain
    fi
    pass "quality gate"
