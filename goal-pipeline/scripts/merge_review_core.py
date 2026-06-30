#!/usr/bin/env python3
"""merge_review_core — merge gf+goal issues and emit review-fix-input.json."""
import json, os, re, sys
from datetime import datetime, timezone

def load_json(path, default=None):
    if os.path.isfile(path):
        return json.load(open(path, encoding="utf-8"))
    return default if default is not None else {}

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
    sev = issue.get("severity", "medium")
    sev_norm = "blocker" if sev in ("blocker", "high") else ("warning" if sev == "warning" else "blocker")
    return {
        "id": iid, "channel": channel, "severity": sev_norm,
        "file": issue.get("file", ""), "line_range": issue.get("line_range", ""),
        "summary": (issue.get("summary") or issue.get("description") or issue.get("message") or str(issue))[:300],
        "suggestion": issue.get("suggestion", ""),
        "root_cause": issue.get("root_cause", "implement_error"),
    }

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
        return ["guazi-flow-plan mini-replan", "guazi-flow-implement", "gate --post implement",
                "runtime-smoke.sh", "gate --post smoke", "assemble-review-packet.sh",
                "run-independent-review.sh", "merge-review-issues.sh", "gate --post review"]
    if action == "blocked_user_decision":
        return ["present user options A/B/C/D"]
    return ["read evidence/review-fix-input.json", "fix within write_set", "gate --post implement if diff changed",
            "assemble-review-packet.sh", "run-independent-review.sh", "merge-review-issues.sh", "gate --post review"]

def main():
    task_dir, goal_json = sys.argv[1], sys.argv[2]
    root_cause_path = sys.argv[3] if len(sys.argv) > 3 else ""
    evidence = os.path.join(task_dir, "evidence")
    review_path = os.path.join(evidence, "review.md")
    gf_json_path = os.path.join(evidence, "review-gf.json")
    fix_input_path = os.path.join(evidence, "review-fix-input.json")

    goal = load_json(goal_json, {})
    issues_goal_raw = goal.get("issues", goal.get("issues_goal", []))
    result_goal = goal.get("result", "not_pass" if issues_goal_raw else "pass")

    gf_doc = load_json(gf_json_path, {})
    issues_gf_raw = gf_doc.get("issues", []) if gf_doc else []
    gf_result = gf_doc.get("result", "unknown") if gf_doc else "unknown"
    if not issues_gf_raw and os.path.isfile(review_path):
        text = open(review_path, encoding="utf-8").read()
        fm, _ = parse_frontmatter(text)
        gf_result = fm.get("result", gf_result)
        if "## 发现项" in text:
            block = text.split("## 发现项", 1)[1].split("##", 1)[0]
            for line in block.splitlines():
                if line.startswith("|") and not line.startswith("| ID") and not line.startswith("|----"):
                    parts = [c.strip() for c in line.strip("|").split("|")]
                    if len(parts) >= 3:
                        issues_gf_raw.append({"id": parts[0], "severity": parts[1], "summary": parts[2]})

    flat = [normalize_issue(i, "goal", n) for n, i in enumerate(issues_goal_raw, 1)]
    flat += [normalize_issue(i, "guazi-flow-review", n) for n, i in enumerate(issues_gf_raw, 1)]
    merged_result = "pass" if gf_result == "pass" and result_goal == "pass" and not flat else "not_pass"
    action = compute_action(merged_result, flat)

    prev = load_json(fix_input_path, {})
    prev_keys = {issue_key(i) for i in prev.get("issues", [])}
    cur_keys = {issue_key(i) for i in flat}
    resolved = [k for k in prev_keys if k not in cur_keys]
    round_n = int(prev.get("round", 0)) + 1 if prev else 1

    run_doc = load_json(os.path.join(evidence, "review-run.json"), {})
    provenance = {
        "review_run_id": run_doc.get("run_id", ""),
        "packet_hash": run_doc.get("packet_hash", goal.get("packet_hash", "")),
        "gf_skill_attested": bool(gf_doc.get("skill_attested") or run_doc.get("gf_skill_attested")),
        "channels": run_doc.get("channels", ["goal"]),
    }

    fix_input = {
        "schema_version": 1, "round": round_n, "merged_result": merged_result,
        "action": action, "issues": flat, "resolved_since_last_round": resolved,
        "next_steps": next_steps_for_action(action), "provenance": provenance,
    }
    with open(fix_input_path, "w", encoding="utf-8") as f:
        json.dump(fix_input, f, indent=2, ensure_ascii=False)

    with open(gf_json_path, "w", encoding="utf-8") as f:
        json.dump({
            "schema_version": 1, "skill": "guazi-flow-review",
            "skill_attested": provenance["gf_skill_attested"],
            "result": gf_result if gf_result != "unknown" else ("pass" if not issues_gf_raw else "not_pass"),
            "issues": issues_gf_raw, "issues_count": len(issues_gf_raw),
        }, f, indent=2, ensure_ascii=False)

    text = open(review_path, encoding="utf-8").read() if os.path.isfile(review_path) else ""
    if not text.strip():
        text = "---\nstage: review\nresult: pass\ngit_head: unknown\nreview_subject_hash: unknown\n---\n\n## 审查范围\nauto\n\n## 发现项\nnone\n"
    annex = "\n## Goal Pipeline Review\n\n_merged at %s_\n\n**goal_result**: %s\n**merged_result**: %s\n**action**: %s\n\n### issues_goal\n\n| ID | Severity | Summary | Root cause |\n|----|----------|---------|------------|\n" % (
        datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'), result_goal, merged_result, action)
    for iss in flat:
        if iss["channel"] == "goal":
            annex += "| %s | %s | %s | %s |\n" % (iss["id"], iss["severity"], iss["summary"][:200], iss.get("root_cause", ""))
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
        text = "---\n" + new_fm + "---" + text[body_m.end():]
    with open(review_path, "w", encoding="utf-8") as f:
        f.write(text)

    with open(os.path.join(evidence, "review-transcript.md"), "w", encoding="utf-8") as f:
        f.write("# Review transcript\n\n| Channel | Result | Issues |\n|---------|--------|--------|\n| guazi-flow-review | %s | %d |\n| goal | %s | %d |\n| merged | %s | action=%s |\n" % (
            gf_result, len(issues_gf_raw), result_goal, len(issues_goal_raw), merged_result, action))

    out = os.path.join(task_dir, "handoff", "merge-result.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"merged_result": merged_result, "action": action, "issues_gf_count": len(issues_gf_raw),
                   "issues_goal_count": len(issues_goal_raw)}, f, indent=2)
    print(json.dumps({"merged_result": merged_result, "action": action}))

if __name__ == "__main__":
    main()
