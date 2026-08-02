# gate-lib/complete.sh — stage body for guazi-gate-stage.sh (sourced in case)
# Relies on parent functions/vars: fail/pass/INDEX/HANDOFF_DIR/PHASE/etc.
    if [[ "$PHASE" == "pre" ]]; then
      [[ -f "$HANDOFF_DIR/review.json" ]] || fail "review handoff missing"
      RRES=$(python3 -c "import json; print(json.load(open('$HANDOFF_DIR/review.json')).get('result',''))" 2>/dev/null || echo "")
      WAIVER="${EVIDENCE_DIR}/goal-review-waiver.json"
      if [[ "$RRES" != "pass" ]]; then
        if [[ -f "$WAIVER" ]]; then
          echo "complete pre: goal-review-waiver.json present — proceeding with documented waiver" >&2
        elif [[ -n "${GOAL_REVIEW_WAIVER:-}" ]]; then
          echo "complete pre: GOAL_REVIEW_WAIVER set — proceeding with env waiver" >&2
        else
          fail "review handoff result not pass (set evidence/goal-review-waiver.json or GOAL_REVIEW_WAIVER to document exception)"
        fi
      fi
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
      WDQ="$SCRIPT_DIR/../write-delivery-quality.sh"
      [[ -x "$WDQ" ]] || WDQ="$SCRIPT_DIR/write-delivery-quality.sh"
      if [[ -x "$WDQ" ]]; then
        WDQ_ARGS=(--task-dir "${REPO_TASK_DIR:-$TASK_DIR}" --output "$HANDOFF_DIR/delivery-quality.json")
        [[ -n "$STATE_FILE" ]] && WDQ_ARGS+=(--state-file "$STATE_FILE")
        [[ -n "$PROJECT_ROOT" ]] && WDQ_ARGS+=(--project-root "$PROJECT_ROOT")
        "$WDQ" "${WDQ_ARGS[@]}" >/dev/null || fail "delivery-quality.json write failed"
        W1BK="$SCRIPT_DIR/w1_leakage_bookkeeping.py"
        if [[ -f "$W1BK" ]]; then
          python3 "$W1BK" \
            --handoff-dir "$HANDOFF_DIR" \
            --goal-evidence-dir "$GOAL_EVIDENCE_DIR" \
            --delivery-quality "$HANDOFF_DIR/delivery-quality.json" >/dev/null 2>&1 || true
        fi
        KERNEL_ROOT="$SCRIPT_DIR/.."
        if [[ -d "$KERNEL_ROOT/kernel/metrics" ]]; then
          ADR_RC=0
          ADR_OUT=$(PYTHONPATH="$KERNEL_ROOT" python3 "$KERNEL_ROOT/kernel/metrics/delivery_report.py" \
            --output "$HANDOFF_DIR/delivery-quality.json" --adr-check \
            ${STATE_FILE:+--state-file "$STATE_FILE"} 2>&1) || ADR_RC=$?
          if [[ "$ADR_RC" -eq 0 && -n "$ADR_OUT" ]]; then
            echo "complete: WARN delivery incomplete_metrics — $ADR_OUT" >&2
          elif [[ "$ADR_RC" -ne 0 ]]; then
            fail "delivery-quality ADR-0004: $ADR_OUT"
          fi
        fi
      fi
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
