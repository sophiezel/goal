# gate-lib/implement.sh — stage body for gate-guazi-flow-stage.sh (sourced in case)
# Relies on parent functions/vars: fail/pass/INDEX/HANDOFF_DIR/PHASE/etc.
    if [[ "$PHASE" == "pre" ]]; then
      # CI needs: semantics — no fresh plan gate ⇒ refuse implement entry.
      run_plan_before_code_guard 1
      # P4 W1.5: write_set pre BLOCK — refuse implement entry if plan write_set is empty
      # (moved from post so code is never written without a declared scope)
      [[ -f "$HANDOFF_DIR/plan.json" ]] || fail "plan handoff missing — run gate --post plan first"
      PRE_WS_LEN=$(python3 -c "import json; print(len(json.load(open('$HANDOFF_DIR/plan.json')).get('write_set',[])))" 2>/dev/null || echo 0)
      if [[ "$PRE_WS_LEN" == "0" ]]; then
        fail "write_set empty at implement-pre — declare paths in index.md ## 范围与写集 before coding (P4 W1.5 pre-BLOCK)"
      fi
      if [[ -f "$SCRIPT_DIR/contract_parser.py" && -f "$HANDOFF_DIR/plan.json" ]]; then
        API_STALE=$(python3 "$SCRIPT_DIR/contract_parser.py" --api-mapping-stale "$INDEX" "$HANDOFF_DIR/plan.json" 2>/dev/null || echo "false")
        if [[ "$API_STALE" == "true" ]]; then
          fail "API mapping table changed since plan post — refresh handoff (gate --post plan) or mini-replan"
        fi
      fi
      pass "implement pre — plan gate passed; write_set non-empty; code changes now allowed within write_set"
    fi
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
      IMPL_TASK_DIR="${REPO_TASK_DIR:-$TASK_DIR}"
      export GOAL_HANDOFF_DIR="$HANDOFF_DIR"
      export GOAL_EVIDENCE_DIR="$GOAL_EVIDENCE_DIR"
      # Pack A: stage write_set untracked (no commit) before hash / UVO / AM ratchet
      stage_write_set_untracked "$PLAN_WS" || true
      UVO="$SCRIPT_DIR/verification-oracle.sh"
      [[ -x "$UVO" ]] || fail "verification-oracle.sh not found"
      UVO_ARGS=(--task-dir "$IMPL_TASK_DIR" --repo-root "$REPO_FOR_UVO" --tier "$TIER")
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
        RAT_ARGS=(--task-dir "$IMPL_TASK_DIR" --repo-root "$REPO_FOR_UVO" --evidence-dir "$GOAL_EVIDENCE_DIR" --json)
        if ! python3 "$RATCHET" "${RAT_ARGS[@]}" >/dev/null 2>&1; then
          gate_fail_with_issues "implement" "$(code_subject_hash)" "fix_and_rerun" '[{"id":"AM-01","severity":"blocker","summary":"acceptance-matrix-ratchet failed","root_cause":"implement_error"}]' "acceptance-matrix-ratchet not_pass"
        fi
      fi
      # IQ thin wrapper: structural checks only (UVO evidence already written)
      IQ_JSON=$(mktemp)
      if ! python3 "$SCRIPT_DIR/implement-qc-gate.py" --task-dir "$IMPL_TASK_DIR" --repo-root "$REPO_FOR_UVO" --tier "$TIER" --skip-test-lint --json > "$IQ_JSON" 2>/dev/null; then
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
      CC="$SCRIPT_DIR/contract-conformance-check.py"
      if [[ -f "$CC" ]]; then
        CC_JSON=$(mktemp)
        CC_EVIDENCE="${GOAL_EVIDENCE_DIR}/contract-conformance.json"
        if ! python3 "$CC" --task-dir "$IMPL_TASK_DIR" --repo-root "$REPO_FOR_UVO" --handoff-dir "$HANDOFF_DIR" --json --evidence "$CC_EVIDENCE" > "$CC_JSON" 2>/dev/null; then
          DH_PRE=$(diff_hash)
          CC_ISSUES=$(python3 - "$CC_JSON" << 'PYCC'
import json, sys
data = json.load(open(sys.argv[1]))
out = []
for i in data.get("issues", []):
    out.append({
        "id": i.get("id", "IQ-10"),
        "severity": "blocker",
        "summary": i.get("message", ""),
        "root_cause": i.get("root_cause", "contract_drift"),
    })
if not out:
    out = [{"id": "IQ-10", "severity": "blocker", "summary": "contract-conformance-check failed", "root_cause": "contract_drift"}]
print(json.dumps(out, ensure_ascii=False))
PYCC
)
          rm -f "$CC_JSON"
          gate_fail_with_issues "implement" "$DH_PRE" "fix_and_rerun" "$CC_ISSUES" "contract-conformance-check failed (IQ-10)"
        fi
        rm -f "$CC_JSON"
      fi
      UX_SCAN="$SCRIPT_DIR/ux_scan_v1.py"
      if [[ -f "$UX_SCAN" ]]; then
        UX_ARGS=(--task-dir "$IMPL_TASK_DIR" --repo-root "$REPO_FOR_UVO")
        [[ -n "$STATE_FILE" ]] && UX_ARGS+=(--state-file "$STATE_FILE")
        [[ -n "$PROJECT_ROOT" ]] && UX_ARGS+=(--project-root "$PROJECT_ROOT")
        python3 "$UX_SCAN" "${UX_ARGS[@]}" >/dev/null 2>&1 || true
      fi
      TIMING_SYNC="$SCRIPT_DIR/sync_timing_substeps.py"
      if [[ -f "$TIMING_SYNC" && -f "$GOAL_EVIDENCE_DIR/verification-oracle.json" ]]; then
        SYNC_ARGS=(--task-dir "$IMPL_TASK_DIR" --source uvo)
        [[ -n "$STATE_FILE" ]] && SYNC_ARGS+=(--state-file "$STATE_FILE")
        [[ -n "$PROJECT_ROOT" ]] && SYNC_ARGS+=(--project-root "$PROJECT_ROOT")
        python3 "$TIMING_SYNC" "${SYNC_ARGS[@]}" >/dev/null 2>&1 || true
      fi
      INT_MANIFEST="$HANDOFF_DIR/integration-manifest.json"
      INT_CHECK="$SCRIPT_DIR/integration-contract-check.sh"
      if [[ -f "$INT_MANIFEST" && -f "$INT_CHECK" ]]; then
        if ! bash "$INT_CHECK" "$INT_MANIFEST"; then
          DH_PRE=$(diff_hash)
          gate_fail_with_issues "implement" "$DH_PRE" "fix_and_rerun" \
            '[{"id":"IQ-11","severity":"blocker","summary":"integration-contract-check failed (see manifest cross_app)","root_cause":"integration_gap"}]' \
            "integration-contract-check failed"
        fi
        mkdir -p "$GOAL_EVIDENCE_DIR"
        cat > "$GOAL_EVIDENCE_DIR/integration-barrier.json" << 'JSON'
{"schema_version":1,"passed":true,"manifest":"handoff/integration-manifest.json"}
JSON
      fi
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
