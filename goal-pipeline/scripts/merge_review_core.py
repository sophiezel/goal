#!/usr/bin/env python3
"""merge_review_core — merge unified review issues and emit review-fix-input.json."""
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


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
    }
    return mapping.get(action, action)


def result_label_zh(result: str) -> str:
    if result == "pass":
        return "通过"
    if result == "review_undetermined":
        return "未决"
    return "未通过"


def issue_key(issue):
    return "%s|%s|%s" % (issue.get("channel"), issue.get("file", ""), issue.get("summary", "")[:80])


def compute_action(merged_result, flat_issues):
    if merged_result == "pass":
        return "proceed_complete"
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
    merged_result = "pass" if unified_result == "pass" and not blockers else "not_pass"
    if unified_result == "review_undetermined":
        merged_result = "not_pass"
    action = compute_action(merged_result, flat)

    issues_goal_raw = [i for i in issues_raw if i.get("channel", "goal") != "guazi-flow-review"]
    issues_gf_raw = [i for i in issues_raw if i.get("channel") == "guazi-flow-review"]
    result_goal = "pass" if not issues_goal_raw and unified_result == "pass" else ("not_pass" if issues_goal_raw else unified_result)
    gf_result = "pass" if not issues_gf_raw else "not_pass"

    prev = load_json(fix_input_path, {})
    prev_keys = {issue_key(i) for i in prev.get("issues", [])}
    cur_keys = {issue_key(i) for i in flat}
    resolved = [k for k in prev_keys if k not in cur_keys]
    round_n = int(prev.get("round", 0)) + 1 if prev else 1

    run_doc = load_json(os.path.join(goal_evidence, "review-run.json"), {})
    provenance = {
        "review_run_id": run_doc.get("run_id", ""),
        "packet_hash": run_doc.get("packet_hash", unified.get("packet_hash", "")),
        "gf_skill_attested": bool(unified.get("gf_skill_attested") or run_doc.get("gf_skill_attested")),
        "channels": run_doc.get("channels", ["goal", "guazi-flow-review"] if unified.get("gf_skill_attested") else ["goal"]),
    }

    fix_input = {
        "schema_version": 1,
        "round": round_n,
        "merged_result": merged_result,
        "action": action,
        "issues": flat,
        "resolved_since_last_round": resolved,
        "next_steps": next_steps_for_action(action),
        "provenance": provenance,
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
