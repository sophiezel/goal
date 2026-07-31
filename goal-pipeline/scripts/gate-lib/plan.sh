# gate-lib/plan.sh — stage body for gate-guazi-flow-stage.sh (sourced in case)
# Relies on parent functions/vars: fail/pass/INDEX/HANDOFF_DIR/PHASE/etc.
    if [[ "$PHASE" == "pre" ]]; then
      # Hard ACL: do not allow code-first while still in plan (must run before pass exits).
      run_plan_before_code_guard 0
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
      PP=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('plan_profile','full'))")
      IH=$(index_contract_hash "$INDEX")
      EH=$(index_execution_tail_hash "$INDEX")
      API_MAP_HASH=$(python3 "$SCRIPT_DIR/contract_parser.py" --api-mapping-hash "$INDEX" 2>/dev/null || echo "")
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
  "plan_profile": "$PP",
  "write_set": $WS,
  "write_set_normalized": true,
  "acceptance_matrix_ids": $AM,
  "index_contract_hash": "$IH",
  "index_execution_tail_hash": "$EH",
  "api_mapping_table_hash": "$API_MAP_HASH",
  "index_schema_hash": "$IH",
  "verification": $VERIF,
  "git_head": "$GH",
  "artifact_paths": ["index.md"],
  "warnings": []
}
JSON
      py_write_handoff plan "$TMP" >/dev/null
      rm -f "$TMP"
      ARGUS="$SCRIPT_DIR/argus-enrich-plan.sh"
      if [[ -x "$ARGUS" ]]; then
        if ! bash "$ARGUS" --task-dir "$TASK_DIR" --handoff-dir "$HANDOFF_DIR"; then
          fail "argus-enrich-plan failed — rule manifest required at plan post"
        fi
      elif [[ -f "$SCRIPT_DIR/argus_enrich_plan.py" ]]; then
        if ! python3 "$SCRIPT_DIR/argus_enrich_plan.py" --task-dir "$TASK_DIR" --handoff-dir "$HANDOFF_DIR"; then
          fail "argus_enrich_plan.py failed"
        fi
      else
        fail "argus_enrich_plan.py missing — L10 manifest required at plan post"
      fi
      [[ -f "$HANDOFF_DIR/argus-scenario-manifest.json" ]] || fail "handoff/argus-scenario-manifest.json missing after plan post"
      if [[ -f "$SCRIPT_DIR/argus_plan_post_policy.py" && -f "$HANDOFF_DIR/plan.json" ]]; then
        ARGUS_CHK=$(python3 "$SCRIPT_DIR/argus_plan_post_policy.py" \
          --check-plan-post \
          --plan-json "$HANDOFF_DIR/plan.json" \
          --manifest-json "$HANDOFF_DIR/argus-scenario-manifest.json" \
          --quality-tier "$TIER" 2>/dev/null || echo '{"ok":false}')
        PARTIAL_WARN=$(echo "$ARGUS_CHK" | python3 -c "import json,sys; d=json.load(sys.stdin); print(';'.join(d.get('pq_warn') or []))" 2>/dev/null || echo "")
        if [[ -n "$PARTIAL_WARN" ]]; then
          python3 - "$HANDOFF_DIR/plan.json" "$PARTIAL_WARN" << 'PYWARN'
import json, sys
plan_path, msg = sys.argv[1], sys.argv[2]
with open(plan_path, encoding="utf-8") as f:
    plan = json.load(f)
warnings = list(plan.get("warnings") or [])
if msg and msg not in warnings:
    warnings.append(msg)
plan["warnings"] = warnings
with open(plan_path, "w", encoding="utf-8") as f:
    json.dump(plan, f, indent=2, ensure_ascii=False)
    f.write("\n")
PYWARN
        fi
      fi
      # Stamp task_tier (XS/S/M/L/XL) for SLO + parallel strategy
      if [[ -f "$SCRIPT_DIR/task_tier.py" ]]; then
        TT_JSON=$(python3 "$SCRIPT_DIR/task_tier.py" \
          --task-dir "$TASK_DIR" \
          --plan-json "$HANDOFF_DIR/plan.json" \
          --state-file "${STATE_FILE:-}" \
          --stamp-state \
          --format json 2>/dev/null || echo "")
        if [[ -n "$TT_JSON" ]]; then
          python3 - "$HANDOFF_DIR/plan.json" "$TT_JSON" << 'PYTT'
import json, sys
plan_path, raw = sys.argv[1], sys.argv[2]
try:
    doc = json.loads(raw)
except json.JSONDecodeError:
    sys.exit(0)
with open(plan_path, encoding="utf-8") as f:
    plan = json.load(f)
plan["task_tier"] = doc.get("task_tier")
plan["task_tier_meta"] = {
    "score": doc.get("score"),
    "signals": doc.get("signals"),
    "slo": doc.get("slo"),
    "parallel": doc.get("parallel"),
}
with open(plan_path, "w", encoding="utf-8") as f:
    json.dump(plan, f, indent=2, ensure_ascii=False)
    f.write("\n")
PYTT
        fi
      fi
      if [[ -f "$SCRIPT_DIR/review_track.py" && -f "$HANDOFF_DIR/plan.json" ]]; then
        RT_JSON=$(python3 "$SCRIPT_DIR/review_track.py" \
          --state-file "${STATE_FILE:-}" \
          --plan-json "$HANDOFF_DIR/plan.json" \
          --auto-resolve-xs-s \
          --format json 2>/dev/null || echo "")
        if [[ -n "$RT_JSON" ]]; then
          python3 - "$HANDOFF_DIR/plan.json" "$RT_JSON" << 'PYRT'
import json, sys
plan_path, raw = sys.argv[1], sys.argv[2]
try:
    doc = json.loads(raw)
except json.JSONDecodeError:
    sys.exit(0)
with open(plan_path, encoding="utf-8") as f:
    plan = json.load(f)
plan["review_policy"] = {
    "track": doc.get("track", "dual"),
    "resolved_at": doc.get("reason", ""),
    "task_tier": doc.get("task_tier", plan.get("task_tier", "")),
}
with open(plan_path, "w", encoding="utf-8") as f:
    json.dump(plan, f, indent=2, ensure_ascii=False)
    f.write("\n")
PYRT
        fi
        if [[ -n "$STATE_FILE" && -f "$STATE_FILE" ]]; then
          python3 "$SCRIPT_DIR/review_track.py" \
            --state-file "$STATE_FILE" \
            --plan-json "$HANDOFF_DIR/plan.json" \
            --auto-resolve-xs-s \
            --persist >/dev/null 2>&1 || true
        fi
      fi
      update_state_gate "plan"
      sync_index_current_stage "$(stage_to_index_current plan)"
      assert_pipeline_chain
    fi
    pass "plan gate"
