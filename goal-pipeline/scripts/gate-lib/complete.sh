# gate-lib/complete.sh — stage body for gate-guazi-flow-stage.sh (sourced in case)
# Relies on parent functions/vars: fail/pass/INDEX/HANDOFF_DIR/PHASE/etc.
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
      QPC="$SCRIPT_DIR/quality_plane_check.py"
      if [[ -f "$QPC" ]]; then
        QPC_ARGS=(--task-dir "$REPO_TASK_DIR" --mode complete)
        [[ -n "$STATE_FILE" ]] && QPC_ARGS+=(--state-file "$STATE_FILE")
        [[ -n "$PROJECT_ROOT" ]] && QPC_ARGS+=(--project-root "$PROJECT_ROOT")
        if ! python3 "$QPC" "${QPC_ARGS[@]}" >/dev/null 2>&1; then
          python3 "$QPC" "${QPC_ARGS[@]}" --format text >&2 || true
          fail "quality_plane_check failed — forged/degraded/illegal UVO skip blocked"
        fi
      fi
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
