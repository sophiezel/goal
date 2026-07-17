#!/usr/bin/env python3
"""efficiency_plane_check — dedup / fail-fast / timing invariants."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--task-dir", default="")
    ap.add_argument("--format", choices=("json", "text"), default="json")
    args = ap.parse_args()

    errors: list[dict] = []
    flags: dict[str, bool] = {}

    gate = (SCRIPT_DIR / "gate-guazi-flow-stage.sh").read_text(encoding="utf-8")
    flags["qg_passes_state_file"] = "QG_ARGS+=(--state-file" in gate or '--state-file "$STATE_FILE"' in gate
    flags["noop_failfast"] = "noop_fix" in gate and "DO NOT rerun" in gate
    flags["timing_recorder"] = (SCRIPT_DIR / "record-pipeline-timing.py").is_file()
    flags["postmortem"] = (SCRIPT_DIR / "pipeline-postmortem.py").is_file()
    flags["benchmark"] = (SCRIPT_DIR / "benchmark-pipeline-replay.sh").is_file()
    review_chain = (SCRIPT_DIR / "goal-run-review-chain.sh").read_text(encoding="utf-8")
    flags["review_zero_channel"] = "zero_usable_review_channels" in review_chain or "separation=degraded" in review_chain
    driver = (SCRIPT_DIR / "goal-stage-driver.sh").read_text(encoding="utf-8")
    flags["wo_bans_build_beta"] = "DO NOT run yarn build:beta" in driver or "禁止连跑全量 yarn build:beta" in driver
    uvo = (SCRIPT_DIR / "verification_oracle_core.py").read_text(encoding="utf-8")
    flags["uvo_parallel_typecheck_tests"] = "_run_parallel" in uvo and "maxWorkers" in uvo
    flags["uvo_build_cache_skip"] = "_prior_build_attested" in uvo
    stop = (SCRIPT_DIR / "goal-pipeline-stop-hook.sh").read_text(encoding="utf-8")
    flags["stop_hook_branch_filter"] = "effective_branch" in stop or "current_git_branch" in stop

    if args.task_dir:
        timing = Path(args.task_dir) / "evidence" / "pipeline-timing.json"
        if timing.is_file():
            try:
                doc = json.loads(timing.read_text(encoding="utf-8"))
                flags["timing_utc"] = doc.get("timezone") == "UTC"
            except json.JSONDecodeError:
                flags["timing_utc"] = False
            if not flags.get("timing_utc"):
                errors.append({"failure_code": "duplicate_verify", "summary": "pipeline-timing timezone not UTC"})

    if not flags["qg_passes_state_file"]:
        errors.append({"failure_code": "missing_state_file_context", "summary": "QG missing state-file wiring"})
    if not flags["noop_failfast"]:
        errors.append({"failure_code": "noop_fix", "summary": "noop fail-fast message missing"})
    if not flags["timing_recorder"]:
        errors.append({"failure_code": "duplicate_verify", "summary": "record-pipeline-timing.py missing"})
    if not flags["postmortem"]:
        errors.append({"failure_code": "duplicate_verify", "summary": "pipeline-postmortem.py missing"})
    if not flags["benchmark"]:
        errors.append({"failure_code": "duplicate_verify", "summary": "benchmark-pipeline-replay.sh missing"})
    if not flags["review_zero_channel"]:
        errors.append({"failure_code": "review_channel_timeout_storm", "summary": "review chain missing zero-channel failfast"})
    if not flags["wo_bans_build_beta"]:
        errors.append({"failure_code": "duplicate_verify", "summary": "work_order should ban local build:beta"})
    if not flags.get("uvo_parallel_typecheck_tests"):
        errors.append({"failure_code": "duplicate_verify", "summary": "UVO missing typecheck∥tests / maxWorkers parallel"})
    if not flags.get("uvo_build_cache_skip"):
        errors.append({"failure_code": "duplicate_verify", "summary": "UVO missing same-hash build cache skip"})
    if not flags.get("stop_hook_branch_filter"):
        errors.append({"failure_code": "duplicate_verify", "summary": "stop hook missing current-branch filter"})

    ok = not errors
    out = {"ok": ok, "plane": "efficiency", "flags": flags, "errors": errors}
    if args.format == "text":
        print(f"efficiency_plane_check ok={ok}")
    else:
        print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0 if ok else 2


if __name__ == "__main__":
    raise SystemExit(main())
