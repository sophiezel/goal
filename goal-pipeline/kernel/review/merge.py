#!/usr/bin/env python3
"""merge_review_core — merge unified review issues and emit review-fix-input.json."""
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

SCRIPT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "scripts")
_KERN_ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
if _KERN_ROOT not in sys.path:
    sys.path.insert(0, _KERN_ROOT)
from kernel.review.loop_policy import LoopPolicy  # noqa: E402


def load_json(path, default=None):
    if os.path.isfile(path):
        return json.load(open(path, encoding="utf-8"))
    return default if default is not None else {}


def resolve_paths(task_dir, state_file="", project_root=""):
    resolver = os.path.join(SCRIPT_DIR, "resolve-artifact-paths.py")
    args = [sys.executable, resolver, "--task-dir", task_dir, "--format", "json", "--ensure-state"]
    if state_file:
        args.extend(["--state-file", state_file])
    proj = project_root or os.environ.get("GOAL_PROJECT_ROOT", "")
    if proj:
        args.extend(["--project-root", proj])
    r = subprocess.run(args, capture_output=True, text=True, check=True)
    return json.loads(r.stdout)


def parse_frontmatter(text):
    m = re.match(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return {}, text
    fm = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            fm[k.strip()] = v.strip().strip('"').strip("'")
    return fm, text


def normalize_issue(issue, channel, idx):
    iid = issue.get("id") or ("GF%02d" % idx if channel == "guazi-flow-review" else "G%02d" % idx)
    sev = (issue.get("severity") or "medium").lower()
    # Only blocker/high escalate; minor/medium/info/warning stay non-blocking
    if sev in ("blocker", "high", "critical"):
        sev_norm = "blocker"
    elif sev in ("warning", "medium", "minor", "info", "low"):
        sev_norm = "warning"
    else:
        sev_norm = "warning"
    return {
        "id": iid,
        "channel": channel,
        "severity": sev_norm,
        "file": issue.get("file", ""),
        "line_range": issue.get("line_range", ""),
        "summary": (issue.get("summary") or issue.get("description") or issue.get("message") or str(issue))[:300],
        "suggestion": issue.get("suggestion", ""),
        "root_cause": issue.get("root_cause", "implement_error"),
    }


def severity_label_zh(sev: str) -> str:
    s = (sev or "").lower()
    if s in ("blocker", "high", "critical"):
        return "阻断"
    return "警告"


def action_label_zh(action: str) -> str:
    mapping = {
        "proceed_complete": "继续 complete",
        "fix_and_rerun_review": "修复后重跑 review",
        "mini_replan": "迷你 replan",
        "blocked_user_decision": "需用户决策",
        "blocked_stagnant": "修复停滞（info_gain 熔断）",
        "switch_to_cursor_task": "切换 Cursor Task 审核",
        "fix_channel": "修复审核通道/网络",
    }
    return mapping.get(action, action)


def result_label_zh(result: str) -> str:
    if result == "pass":
        return "通过"
    if result == "review_undetermined":
        return "未决"
    if result == "infra_undetermined":
        return "基础设施未决"
    return "未通过"


def issue_key(issue):
    return "%s|%s|%s" % (issue.get("channel"), issue.get("file", ""), issue.get("summary", "")[:80])


def _issue_is_infra(issue: dict) -> bool:
    try:
        from review_channel_probe import issue_is_infra

        return issue_is_infra(issue)
    except Exception:
        iid = str(issue.get("id") or "").upper()
        if iid.startswith("ADP-ERR") or iid in ("FB-EXHAUST", "CH-UNREACHABLE", "CH-PROBE"):
            return True
        root = str(issue.get("root_cause") or "").lower()
        return root in ("infra_channel", "infra", "review_channel", "network")


def issues_are_infra_only(flat_issues, unified_result: str) -> bool:
    """True when undetermined / not_pass is caused only by adapter/network (not business)."""
    if not flat_issues:
        return unified_result == "review_undetermined"
    non_infra = [i for i in flat_issues if not _issue_is_infra(i)]
    # Ignore pure verify CHK-* if present alongside infra? treat CHK as business.
    return len(non_infra) == 0 and (
        unified_result == "review_undetermined"
        or any(_issue_is_infra(i) for i in flat_issues)
    )


def compute_action(merged_result, flat_issues, unified_result=""):
    if merged_result == "pass":
        return "proceed_complete"
    if issues_are_infra_only(flat_issues, unified_result or merged_result):
        # Prefer cursor-task when channel unreachable; otherwise fix_channel.
        summaries = " ".join(str(i.get("summary") or "") for i in flat_issues).lower()
        ids = " ".join(str(i.get("id") or "") for i in flat_issues).upper()
        if "CH-UNREACHABLE" in ids or "unreachable" in summaries or "cursor task" in summaries:
            return "switch_to_cursor_task"
        return "fix_channel"
    blockers = [i for i in flat_issues if i.get("severity") == "blocker"]
    if not blockers:
        return "fix_and_rerun_review"
    causes = [i.get("root_cause", "implement_error") for i in blockers]
    if any(c == "spec_ambiguity" for c in causes):
        return "blocked_user_decision"
    if sum(1 for c in causes if c == "plan_gap") > sum(1 for c in causes if c == "implement_error"):
        return "mini_replan"
    return "fix_and_rerun_review"


def next_steps_for_action(action):
    if action == "proceed_complete":
        return ["gate --post review", "guazi-flow-complete", "gate --post complete"]
    if action == "switch_to_cursor_task":
        return [
            "export GOAL_REVIEW_CURSOR_TASK=1",
            "or invoke Cursor Task readonly review skill",
            "merge-review-issues.sh",
            "gate --post review",
            "DO NOT treat as write_set business bug",
        ]
    if action == "fix_channel":
        return [
            "check API keys / network / ollama (do not edit write_set for ADP-ERR)",
            "optional short probe: detect-review-channels --probe",
            "GOAL_REVIEW_CURSOR_TASK=1 as alternate L2 path",
            "re-run run-independent-review.sh after channel healthy",
        ]
    if action == "mini_replan":
        return [
            "guazi-flow-plan mini-replan",
            "guazi-flow-implement",
            "gate --post implement",
            "runtime-smoke.sh",
            "gate --post smoke",
            "assemble-review-packet.sh",
            "run-independent-review.sh",
            "merge-review-issues.sh",
            "gate --post review",
        ]
    if action == "blocked_user_decision":
        return ["present user options A/B/C/D"]
    if action == "blocked_stagnant":
        return [
            "read evidence/review-fix-input.json — info_gain < threshold for GOAL_REVIEW_STAGNANT_ROUNDS consecutive rounds",
            "present user options: (A) widen scope / mini-replan (B) manual review sign-off (C) abort",
            "DO NOT continue blind fix_and_rerun_review loops",
        ]
    return [
        "read evidence/review-fix-input.json",
        "fix within write_set",
        "gate --post implement if diff changed",
        "assemble-review-packet.sh",
        "run-independent-review.sh",
        "merge-review-issues.sh",
        "gate --post review",
    ]

def main():
    task_dir, unified_json = sys.argv[1], sys.argv[2]
    state_file = os.environ.get("GOAL_STATE_FILE", "")
    paths = resolve_paths(task_dir, state_file)
    repo_evidence = paths["goal_evidence_dir"] if paths["mode"] == "repo_full" else paths["repo_evidence_dir"]
    goal_evidence = paths["goal_evidence_dir"]
    handoff_dir = paths["handoff_dir"]
    review_path = os.path.join(repo_evidence, "review.md")
    fix_input_path = os.path.join(goal_evidence, "review-fix-input.json")

    unified = load_json(unified_json, {})
    issues_raw = unified.get("issues", [])
    unified_result = unified.get("result", "not_pass" if issues_raw else "pass")

    goal_idx = 0
    gf_idx = 0
    flat = []
    for iss in issues_raw:
        ch = iss.get("channel", "goal")
        if ch == "guazi-flow-review":
            gf_idx += 1
            flat.append(normalize_issue(iss, "guazi-flow-review", gf_idx))
        else:
            goal_idx += 1
            flat.append(normalize_issue(iss, "goal", goal_idx))

    blockers = [i for i in flat if i.get("severity") == "blocker"]
    infra_only = issues_are_infra_only(flat, unified_result)
    # Keep merged_result gate-compatible (pass|not_pass) but annotate infra_undetermined via action.
    merged_result = "pass" if unified_result == "pass" and not blockers else "not_pass"
    if unified_result == "review_undetermined":
        merged_result = "not_pass"
    action = compute_action(merged_result, flat, unified_result=unified_result)
    if infra_only and action in ("switch_to_cursor_task", "fix_channel"):
        # Stamp issues so agents don't treat ADP-ERR as write_set work.
        for iss in flat:
            if _issue_is_infra(iss):
                iss["root_cause"] = iss.get("root_cause") or "infra_channel"
                iss.setdefault("suggestion", action)

    issues_goal_raw = [i for i in issues_raw if i.get("channel", "goal") != "guazi-flow-review"]
    issues_gf_raw = [i for i in issues_raw if i.get("channel") == "guazi-flow-review"]
    result_goal = "pass" if not issues_goal_raw and unified_result == "pass" else ("not_pass" if issues_goal_raw else unified_result)
    gf_result = "pass" if not issues_gf_raw else "not_pass"

    prev = load_json(fix_input_path, {})
    prev_keys = {issue_key(i) for i in prev.get("issues", [])}
    cur_keys = {issue_key(i) for i in flat}
    resolved = [k for k in prev_keys if k not in cur_keys]
    round_n = int(prev.get("round", 0)) + 1 if prev else 1

    # Hard cap on fix rounds (docs promise "10 轮警告" — enforce as blocked).
    policy = LoopPolicy.from_env()
    max_rounds = policy.max_rounds
    rounds_exhausted = (
        merged_result != "pass"
        and round_n > max_rounds
        and action in ("fix_and_rerun_review", "mini_replan")
    )
    if rounds_exhausted:
        action = "blocked_user_decision"

    # info_gain 熔断 (v3 §8.3a): consecutive low info_gain → blocked_stagnant
    info_gain_threshold = policy.info_gain_min
    stagnant_rounds_limit = policy.stagnant_rounds_limit

    cur_blockers = sum(1 for i in flat if i.get("severity") == "blocker")
    prev_blockers = int(prev.get("blocker_count", 0)) if prev else 0
    if prev_blockers > 0:
        info_gain = round((prev_blockers - cur_blockers) / max(prev_blockers, 1), 4)
    else:
        # No previous blockers: gain is 1.0 if now clean, 0.0 if new blockers appeared
        info_gain = 1.0 if cur_blockers == 0 else 0.0
    prev_stagnant = int(prev.get("stagnant_rounds", 0)) if prev else 0
    if info_gain < info_gain_threshold:
        stagnant_rounds = prev_stagnant + 1
    else:
        stagnant_rounds = 0
    stagnant_blocked = (
        not infra_only
        and merged_result != "pass"
        and stagnant_rounds >= stagnant_rounds_limit
        and info_gain < info_gain_threshold
        and action in ("fix_and_rerun_review", "mini_replan")
    )
    if stagnant_blocked:
        action = "blocked_stagnant"

    run_doc = load_json(os.path.join(goal_evidence, "review-run.json"), {})
    provenance = {
        "review_run_id": run_doc.get("run_id", ""),
        "packet_hash": run_doc.get("packet_hash", unified.get("packet_hash", "")),
        "gf_skill_attested": bool(unified.get("gf_skill_attested") or run_doc.get("gf_skill_attested")),
        "channels": run_doc.get("channels", ["goal", "guazi-flow-review"] if unified.get("gf_skill_attested") else ["goal"]),
    }

    next_steps = next_steps_for_action(action)
    if rounds_exhausted:
        next_steps = [
            "review fix rounds exhausted (GOAL_REVIEW_MAX_ROUNDS=%d, round=%d)" % (max_rounds, round_n),
            "present user options A/B/C/D — do not continue blind fix loops",
            "optional: raise GOAL_REVIEW_MAX_ROUNDS only with explicit user approval",
        ]
    if stagnant_blocked:
        next_steps = next_steps_for_action("blocked_stagnant")

    fix_input = {
        "schema_version": 1,
        "round": round_n,
        "merged_result": merged_result,
        "action": action,
        "issues": flat,
        "resolved_since_last_round": resolved,
        "next_steps": next_steps,
        "provenance": provenance,
        "classification": "infra_undetermined" if infra_only else "business",
        "max_rounds": max_rounds,
        "rounds_exhausted": rounds_exhausted,
        "blocker_count": cur_blockers,
        "info_gain": info_gain,
        "info_gain_threshold": info_gain_threshold,
        "stagnant_rounds": stagnant_rounds,
        "stagnant_rounds_limit": stagnant_rounds_limit,
        "stagnant_blocked": stagnant_blocked,
    }
    with open(fix_input_path, "w", encoding="utf-8") as f:
        json.dump(fix_input, f, indent=2, ensure_ascii=False)

    text = open(review_path, encoding="utf-8").read() if os.path.isfile(review_path) else ""
    if not text.strip():
        text = (
            "---\nstage: review\nresult: pass\ngit_head: unknown\nreview_subject_hash: unknown\n---\n\n"
            "## 审查范围\nauto\n\n## 发现项\nnone\n"
        )
    annex = (
        "\n## Goal Pipeline Review\n\n_合并时间 %s_\n\n"
        "**goal 通道结果**: %s\n**合并结果**: %s\n**建议动作**: %s\n\n"
        "### goal 通道问题\n\n| ID | 严重程度 | 摘要 | 根因 |\n|----|----------|------|------|\n"
        % (
            datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            result_label_zh(str(result_goal)),
            result_label_zh(str(merged_result)),
            action_label_zh(str(action)),
        )
    )
    for iss in flat:
        if iss["channel"] == "goal":
            annex += "| %s | %s | %s | %s |\n" % (
                iss["id"],
                severity_label_zh(iss["severity"]),
                iss["summary"][:200],
                iss.get("root_cause", ""),
            )
    annex += "\n### guazi-flow 通道问题\n\n| ID | 严重程度 | 摘要 | 根因 |\n|----|----------|------|------|\n"
    for iss in flat:
        if iss["channel"] == "guazi-flow-review":
            annex += "| %s | %s | %s | %s |\n" % (
                iss["id"],
                severity_label_zh(iss["severity"]),
                iss["summary"][:200],
                iss.get("root_cause", ""),
            )

    if "## Goal Pipeline Review" in text:
        text = re.sub(r"\n## Goal Pipeline Review.*", annex, text, flags=re.DOTALL)
    else:
        text = text.rstrip() + annex

    body_m = re.match(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
    if body_m:
        new_fm = body_m.group(1)
        new_fm = re.sub(r"issues_gf_count:\s*\d+", "issues_gf_count: %d" % len(issues_gf_raw), new_fm)
        if "issues_gf_count:" not in new_fm:
            new_fm = new_fm.rstrip() + "\nissues_gf_count: %d\n" % len(issues_gf_raw)
        new_fm = re.sub(r"merged_result:\s*\S+", "merged_result: %s" % merged_result, new_fm)
        if "merged_result:" not in new_fm:
            new_fm = new_fm.rstrip() + "\nmerged_result: %s\n" % merged_result
        text = "---\n" + new_fm + "\n---\n" + text[body_m.end() :]

    with open(review_path, "w", encoding="utf-8") as f:
        f.write(text)

    with open(os.path.join(goal_evidence, "review-transcript.md"), "w", encoding="utf-8") as f:
        f.write(
            "# Review transcript\n\n| 通道 | 结果 | 问题数 |\n|------|------|--------|\n"
            "| guazi-flow-review | %s | %d |\n| goal | %s | %d |\n| 合并 | %s | action=%s |\n"
            % (
                result_label_zh(str(gf_result)),
                len(issues_gf_raw),
                result_label_zh(str(result_goal)),
                len(issues_goal_raw),
                result_label_zh(str(merged_result)),
                action_label_zh(str(action)),
            )
        )

    out = os.path.join(handoff_dir, "merge-result.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(
            {
                "merged_result": merged_result,
                "action": action,
                "issues_gf_count": len(issues_gf_raw),
                "issues_goal_count": len(issues_goal_raw),
            },
            f,
            indent=2,
        )
    print(json.dumps({"merged_result": merged_result, "action": action}))


if __name__ == "__main__":
    main()
