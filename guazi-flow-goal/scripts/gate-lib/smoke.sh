# gate-lib/smoke.sh — stage body for guazi-gate-stage.sh (sourced in case)
# Relies on parent functions/vars: fail/pass/INDEX/HANDOFF_DIR/PHASE/etc.
    if [[ "${GOAL_ALLOW_LEGACY_SMOKE_STAGE:-}" != "1" ]]; then
      echo "gate WARN: --stage smoke is deprecated (B1) — verify main track is gate --post quality only" >&2
      echo "gate: set GOAL_ALLOW_LEGACY_SMOKE_STAGE=1 for legacy handoff/smoke.json (non-default profile)" >&2
      fail "smoke stage blocked — use quality stage (runtime-smoke + quality-gate)"
    fi
    if [[ "$PHASE" == "pre" ]]; then
      [[ -f "$HANDOFF_DIR/implement.json" ]] || fail "implement handoff missing — run implement gate --post first"
    fi
    SMOKE_MD="$GOAL_EVIDENCE_DIR/runtime-smoke.md"
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
  "artifact_paths": [],
  "runtime_artifact_paths": ["evidence/runtime-smoke.md"]
}
JSON
      py_write_handoff smoke "$TMP" >/dev/null
      rm -f "$TMP"
      update_state_gate "smoke"
      sync_index_current_stage "$(stage_to_index_current smoke)"
    fi
    pass "smoke gate"
