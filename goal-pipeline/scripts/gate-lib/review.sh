# gate-lib/review.sh — stage body for gate-guazi-flow-stage.sh (sourced in case)
# Relies on parent functions/vars: fail/pass/INDEX/HANDOFF_DIR/PHASE/etc.
    if [[ "$PHASE" == "pre" ]]; then
      [[ -f "$HANDOFF_DIR/implement.json" ]] || fail "implement handoff missing"
      [[ -f "$HANDOFF_DIR/plan.json" ]] || fail "plan handoff missing"
      FRESH=$(python3 - "$INDEX" "$HANDOFF_DIR/plan.json" "$INDEX_HASH_PY" << 'PYFRESH'
import json, sys, importlib.util, os
index_path, plan_path, helper = sys.argv[1], sys.argv[2], sys.argv[3]
plan = json.load(open(plan_path, encoding="utf-8"))
if os.path.isfile(helper):
    spec = importlib.util.spec_from_file_location("index_contract_hash", helper)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    print(json.dumps(mod.compare_plan_freshness(index_path, plan), ensure_ascii=False))
else:
    print(json.dumps({"contract_changed": False, "fresh": True, "execution_changed": False}))
PYFRESH
) || FRESH='{"contract_changed":false,"fresh":true}'
      CONTRACT_CHANGED=$(echo "$FRESH" | python3 -c "import json,sys; print(json.load(sys.stdin).get('contract_changed', False))" 2>/dev/null || echo "False")
      if [[ "$CONTRACT_CHANGED" == "True" ]]; then
        REFRESH="$SCRIPT_DIR/refresh-handoffs-after-index.sh"
        MSG="plan handoff stale — index_contract_hash mismatch (contract changed; mini-replan required)"
        if [[ -x "$REFRESH" ]]; then
          MSG="$MSG — run: $REFRESH --task-dir '$REPO_TASK_DIR' --state-file '${STATE_FILE:-}' --project-root '${PROJECT_ROOT:-}'"
        fi
        fail "$MSG"
      fi
      # Auto-assemble review packet if missing (P0-D)
      if [[ ! -f "$HANDOFF_DIR/review-packet.json" ]]; then
        ASSEMBLE="$SCRIPT_DIR/assemble-review-packet.sh"
        if [[ -x "$ASSEMBLE" ]]; then
          echo "gate WARN [review/pre]: review-packet.json missing — auto-assembling" >&2
          ASSEMBLE_ARGS=(--task-dir "$REPO_TASK_DIR")
          [[ -n "$STATE_FILE" ]] && ASSEMBLE_ARGS+=(--state-file "$STATE_FILE")
          [[ -n "$PROJECT_ROOT" ]] && ASSEMBLE_ARGS+=(--project-root "$PROJECT_ROOT")
          "$ASSEMBLE" "${ASSEMBLE_ARGS[@]}" >/dev/null || fail "auto assemble-review-packet failed"
        else
          fail "review-packet.json missing — run assemble-review-packet.sh"
        fi
      fi
      VERIFY_REV="$SCRIPT_DIR/verify-review.sh"
      [[ -x "$VERIFY_REV" ]] || fail "verify-review.sh not found"
      UVO="$SCRIPT_DIR/verification-oracle.sh"
      REPO_FOR_REV="${GIT_ROOT:-$PROJECT_ROOT}"
      [[ -n "$REPO_FOR_REV" ]] || REPO_FOR_REV="$(pwd)"
      export GOAL_HANDOFF_DIR="$HANDOFF_DIR"
      export GOAL_EVIDENCE_DIR="$GOAL_EVIDENCE_DIR"
      UVO_CHECK_ARGS=(--task-dir "$TASK_DIR" --repo-root "$REPO_FOR_REV" --check-freshness)
      [[ -n "$STATE_FILE" ]] && UVO_CHECK_ARGS+=(--state-file "$STATE_FILE")
      [[ -n "$PROJECT_ROOT" ]] && UVO_CHECK_ARGS+=(--project-root "$PROJECT_ROOT")
      if ! "$UVO" "${UVO_CHECK_ARGS[@]}" >/dev/null 2>&1; then
        fail "verification-oracle evidence missing or stale — rerun gate --post implement"
      fi
      WS=$(python3 -c "import json; print(','.join(json.load(open('$HANDOFF_DIR/plan.json')).get('write_set',[])))" 2>/dev/null || echo "")
      export GOAL_SKIP_TEST=1 GOAL_SKIP_BUILD=1 GOAL_SKIP_LINT=1
      VOUT=$("$VERIFY_REV" "$TASK_DIR" "$WS" json 2>/dev/null || echo '{"overall":"not_pass"}')
      unset GOAL_SKIP_TEST GOAL_SKIP_BUILD GOAL_SKIP_LINT
      VOK=$(echo "$VOUT" | python3 -c "import json,sys; d=json.load(sys.stdin); c=d.get('checks',d); print('pass' if c.get('scope',{}).get('pass') and c.get('secret',{}).get('pass') else 'not_pass')" 2>/dev/null || echo "not_pass")
      [[ "$VOK" == "pass" ]] || fail "review-pre scope/secret check not pass"
      PREFLIGHT="$SCRIPT_DIR/review_packet_preflight.py"
      if [[ -f "$PREFLIGHT" ]]; then
        PF_ARGS=(--packet "$HANDOFF_DIR/review-packet.json" --uvo "$GOAL_EVIDENCE_DIR/verification-oracle.json")
        if ! python3 "$PREFLIGHT" "${PF_ARGS[@]}" >/dev/null 2>&1; then
          python3 "$PREFLIGHT" "${PF_ARGS[@]}" --json 2>&1 | head -20 >&2 || true
          fail "review-packet preflight failed (PKT-01/02/03)"
        fi
      fi
      pass "review gate"
    fi
    if [[ "$PHASE" == "post" ]]; then
      RRESULT=$(py_check_review)
      ROK=$(echo "$RRESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['ok'])")
      if [[ "$ROK" != "True" ]]; then
        echo "$RRESULT" | python3 -c "import json,sys; [print('  -',e) for e in json.load(sys.stdin)['errors']]" >&2
        show_review_issue_board
        fail "review evidence validation failed"
      fi
      RESULT_VAL=$(echo "$RRESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('result','unknown'))")
      RSH=$(echo "$RRESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('review_subject_hash',''))")
      GH=$(git_head_short)
      # stale check: src implementation diff changed since implement (evidence writes ignored)
      CUR_CSH=$(code_subject_hash)
      IMP_CSH=$(python3 -c "import json; d=json.load(open('$HANDOFF_DIR/implement.json')); print(d.get('code_subject_hash') or d.get('candidate_diff_hash',''))" 2>/dev/null || echo "")
      if [[ -n "$IMP_CSH" && "$IMP_CSH" != "$CUR_CSH" && "$IMP_CSH" != "unknown" && "$CUR_CSH" != "unknown" ]]; then
        fail "review stale — code_subject_hash changed since implement handoff"
      fi
      GOAL_COUNT=0
      if [[ -f "$GOAL_EVIDENCE_DIR/review-unified.json" ]]; then
        GOAL_COUNT=$(python3 - "$GOAL_EVIDENCE_DIR/review-unified.json" << 'PYGC'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
issues = d.get("issues", [])
print(sum(1 for i in issues if i.get("channel", "goal") != "guazi-flow-review"))
PYGC
)
      fi
      GF_COUNT=$(read_gf_issues_count)
      GF_ATTESTED=$(python3 -c "import json; d=json.load(open('$GOAL_EVIDENCE_DIR/review-fix-input.json')); print(str(d.get('provenance',{}).get('gf_skill_attested',False)).lower())" 2>/dev/null || echo "false")
      RUN_ID=$(python3 -c "import json; print(json.load(open('$GOAL_EVIDENCE_DIR/review-run.json')).get('run_id',''))" 2>/dev/null || echo "")
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
  "gf_execution_mode": "independent_unified_review",
  "gf_skill_attested": $GF_ATTESTED,
  "review_run_id": "$RUN_ID",
  "root_cause_summary": {},
  "artifact_paths": ["evidence/review.md"],
  "runtime_artifact_paths": ["evidence/review-unified.json", "evidence/review-fix-input.json", "evidence/review-run.json"]
}
JSON
      py_write_handoff review "$TMP" >/dev/null
      rm -f "$TMP"
      assert_pipeline_chain
      [[ -f "$GOAL_EVIDENCE_DIR/review-run.json" ]] || fail "review-run.json missing — run run-independent-review.sh"
      RUN_DOWNGRADE=$(python3 - << 'PY' "$GOAL_EVIDENCE_DIR/review-run.json"
import json, sys
run = json.load(open(sys.argv[1], encoding="utf-8"))
guard = run.get("channel_guard") or {}
if not guard:
    print("skip")
elif guard.get("has_candidates") and run.get("provider") == "deterministic":
    print("blocked")
else:
    print("ok")
PY
)
      if [[ "$RUN_DOWNGRADE" == "blocked" ]]; then
        fail "review provider downgrade blocked — review-run.json provider=deterministic but channel_guard.has_candidates=true; rerun goal-run-review-chain.sh"
      fi
      RUN_HASH=$(python3 -c "import json; print(json.load(open('$GOAL_EVIDENCE_DIR/review-run.json')).get('packet_hash',''))" 2>/dev/null || echo "")
      PKT_HASH=$(shasum -a 256 "$HANDOFF_DIR/review-packet.json" 2>/dev/null | cut -c1-16 || sha256sum "$HANDOFF_DIR/review-packet.json" 2>/dev/null | cut -c1-16 || echo "")
      if [[ -n "$RUN_HASH" && -n "$PKT_HASH" && "$RUN_HASH" != "$PKT_HASH" ]]; then
        fail "review-run packet_hash does not match review-packet.json"
      fi
      UNIFIED_RES=$(python3 -c "import json; print(json.load(open('$GOAL_EVIDENCE_DIR/review-unified.json')).get('result',''))" 2>/dev/null || echo "")
      if [[ "$UNIFIED_RES" == "review_undetermined" ]]; then
        fail "review separation_confidence low — use cursor-task/claude-native provider"
      fi
      MERGED=$(python3 - "$REPO_EVIDENCE_DIR/review.md" << 'PYMG'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"merged_result:\s*(\S+)", t)
print(m.group(1) if m else "")
PYMG
)
      if [[ -n "$MERGED" && "$MERGED" != "pass" ]]; then
        show_review_issue_board
        CUR_DH=$(diff_hash)
        check_noop_ratchet "review" "$CUR_DH" || exit 1
        fail "merged_result is not pass: $MERGED"
      fi
      CLEN=$(python3 -c "import json; d=json.load(open('$GOAL_EVIDENCE_DIR/review-unified.json')); print(len(d.get('checklist_goal',[])))" 2>/dev/null || echo 0)
      [[ -f "$GOAL_EVIDENCE_DIR/review-fix-input.json" ]] || fail "review-fix-input.json missing — run merge-review-issues.sh"
      python3 - "$GOAL_EVIDENCE_DIR/review-fix-input.json" << 'PYSCHEMA' || fail "review-fix-input.json schema invalid"
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
required = ["schema_version", "round", "merged_result", "action", "issues", "next_steps", "provenance"]
for k in required:
    if k not in d:
        raise SystemExit(f"missing field: {k}")
actions = {
    "proceed_complete",
    "fix_and_rerun_review",
    "mini_replan",
    "blocked_user_decision",
    "switch_to_cursor_task",
    "fix_channel",
}
if d["action"] not in actions:
    raise SystemExit(f"invalid action: {d['action']}")
if d["merged_result"] not in ("pass", "not_pass"):
    raise SystemExit("invalid merged_result")
if d["merged_result"] == "pass" and d["action"] != "proceed_complete":
    raise SystemExit("pass requires proceed_complete")
if d["merged_result"] == "not_pass" and d["action"] == "proceed_complete":
    raise SystemExit("not_pass cannot proceed_complete")
# Infra actions must not be treated as business fix_and_rerun_review.
if d.get("classification") == "infra_undetermined" and d["action"] == "fix_and_rerun_review":
    raise SystemExit("infra_undetermined cannot use fix_and_rerun_review")
# Hard round cap: exhausted business loops must not proceed_complete.
import os
try:
    max_rounds = int(os.environ.get("GOAL_REVIEW_MAX_ROUNDS", "10") or "10")
except ValueError:
    max_rounds = 10
round_n = int(d.get("round") or 0)
if d.get("rounds_exhausted") or (
    d.get("merged_result") == "not_pass"
    and round_n > max_rounds
    and d.get("action") in ("fix_and_rerun_review", "mini_replan")
):
    raise SystemExit(
        f"review fix rounds exhausted: round={round_n} max={max_rounds} "
        "(set action=blocked_user_decision; do not continue blind loops)"
    )
if d.get("rounds_exhausted") and d.get("action") != "blocked_user_decision":
    raise SystemExit("rounds_exhausted requires action=blocked_user_decision")
PYSCHEMA

      FIX_ACTION=$(python3 -c "import json; print(json.load(open('$GOAL_EVIDENCE_DIR/review-fix-input.json')).get('action',''))" 2>/dev/null || echo "")
      FIX_MERGED=$(python3 -c "import json; print(json.load(open('$GOAL_EVIDENCE_DIR/review-fix-input.json')).get('merged_result',''))" 2>/dev/null || echo "")
      FIX_ROUNDS_EXHAUSTED=$(python3 -c "import json; print(str(json.load(open('$GOAL_EVIDENCE_DIR/review-fix-input.json')).get('rounds_exhausted', False)).lower())" 2>/dev/null || echo "false")
      if [[ "$FIX_MERGED" != "$MERGED" && -n "$MERGED" && -n "$FIX_MERGED" ]]; then
        fail "review-fix-input merged_result mismatch with review.md"
      fi
      if [[ "$FIX_ROUNDS_EXHAUSTED" == "true" ]]; then
        write_state_blocked "review_rounds_exhausted"
        show_review_issue_board
        fail "review fix rounds exhausted — blocked_user_decision required"
      fi
      if [[ "$RESULT_VAL" == "pass" && "$FIX_ACTION" != "proceed_complete" ]]; then
        fail "review pass requires review-fix-input action=proceed_complete"
      fi
      if [[ "$RESULT_VAL" == "pass" && "$CLEN" -lt 1 ]]; then
        fail "review pass requires non-empty checklist_goal in review-unified.json"
      fi
      if [[ "$RESULT_VAL" != "pass" ]]; then
        show_review_issue_board
        CUR_DH=$(diff_hash)
        check_noop_ratchet "review" "$CUR_DH" || exit 1
        fail "review result is not pass: $RESULT_VAL"
      fi
      update_state_gate "review"
      sync_index_current_stage "$(stage_to_index_current review)"
    fi
    pass "review gate"
