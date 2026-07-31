#!/usr/bin/env python3
"""Render v0 Markdown pipeline timing report from evidence artifacts."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

_STAGE_ORDER = ("plan", "implement", "quality", "review", "complete")
_SLA_HINT = "40-50 min total (postmortem sla_hints.target_total_min)"


def _load_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def resolve_goal_evidence(task_dir: str, state_file: str, project_root: str) -> Path:
    script_dir = Path(__file__).resolve().parent
    resolver = script_dir / "resolve-artifact-paths.py"
    if resolver.is_file():
        args = [sys.executable, str(resolver), "--task-dir", task_dir, "--format", "json"]
        if state_file:
            args.extend(["--state-file", state_file])
        if project_root:
            args.extend(["--project-root", project_root])
        r = subprocess.run(args, capture_output=True, text=True, check=True)
        d = json.loads(r.stdout)
        return Path(d["goal_evidence_dir"])
    return Path(task_dir) / "evidence"


def _frontmatter(text: str) -> dict[str, str]:
    m = re.match(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return {}
    out: dict[str, str] = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def _retry_count(stage_doc: dict[str, Any]) -> int:
    events = stage_doc.get("events") or []
    starts = sum(1 for e in events if isinstance(e, dict) and e.get("event") == "start")
    return max(0, starts - 1)


def _stage_ms(stages: dict[str, Any], name: str) -> int | None:
    ent = stages.get(name) or {}
    if not isinstance(ent, dict):
        return None
    if ent.get("duration_ms") is not None:
        return int(ent["duration_ms"])
    return None


def _merge_quality_ms(stages: dict[str, Any]) -> int | None:
    q = _stage_ms(stages, "quality")
    s = _stage_ms(stages, "smoke")
    if q is not None and s is not None:
        return q + s
    return q if q is not None else s


def _low_value_flags(
    timing: dict[str, Any],
    uvo: dict[str, Any],
    smoke_fm: dict[str, str],
) -> list[str]:
    flags: list[str] = []
    stages = timing.get("stages") or {}
    impl_ms = _stage_ms(stages, "implement") or 0
    for step in uvo.get("steps") or []:
        if not isinstance(step, dict):
            continue
        sid = str(step.get("id") or "")
        out = str(step.get("output") or step.get("command") or "")
        if sid == "build" and impl_ms > 0 and ("cache hit" in out.lower() or "skipped" in out.lower()):
            flags.append(
                "R1: UVO build skipped/cache hit — implement wall clock may still include Agent time"
            )
            break
    for key in _STAGE_ORDER:
        ent = stages.get(key) or {}
        if not isinstance(ent, dict):
            continue
        events = ent.get("events") or []
        starts = [e for e in events if isinstance(e, dict) and e.get("event") == "start"]
        ends = [e for e in events if isinstance(e, dict) and e.get("event") == "end"]
        if len(starts) >= 2 and not ends:
            flags.append(f"R2: stage `{key}` has {len(starts)} start events without end")
    rev = stages.get("review") or {}
    if isinstance(rev, dict):
        attempt = (rev.get("substeps") or {}).get("attempt") or {}
        if isinstance(attempt, dict) and int(attempt.get("duration_ms") or 0) < 2000:
            flags.append("R3: review.substeps.attempt present with very small duration_ms (fast-fail round)")
    if uvo.get("overall") == "pass":
        flags.append("R4: (manual) cross-check contract-conformance / IQ if present — not auto-evaluated in v0")
    smoke_ms = smoke_fm.get("duration_ms")
    if smoke_ms and uvo.get("smoke_required") is False:
        try:
            if int(smoke_ms) > 60_000:
                flags.append("R5: runtime-smoke duration high but smoke_required=false")
        except ValueError:
            pass
    return flags


def render_report(
    *,
    task_id: str,
    git_short_head: str,
    goal_evidence: Path,
    repo_task: Path,
) -> str:
    timing_path = goal_evidence / "pipeline-timing.json"
    if not timing_path.is_file():
        timing_path = repo_task / "evidence" / "pipeline-timing.json"
    timing = _load_json(timing_path)
    tz = timing.get("timezone") or "UTC"
    stages = timing.get("stages") or {}

    uvo = _load_json(goal_evidence / "verification-oracle.json")
    if not uvo:
        uvo = _load_json(repo_task / "evidence" / "verification-oracle.json")

    review_run = _load_json(goal_evidence / "review-run.json")
    smoke_fm: dict[str, str] = {}
    for base in (goal_evidence, repo_task / "evidence"):
        smoke_md = base / "runtime-smoke.md"
        if smoke_md.is_file():
            smoke_fm = _frontmatter(smoke_md.read_text(encoding="utf-8"))
            break

    lines: list[str] = [
        f"# Pipeline timing — {task_id} ({git_short_head})",
        "",
        f"_timezone: {tz}_",
        "",
        "## Summary",
        "| Stage | Wall ms | SLA hint | Retries | Notes |",
        "|-------|---------|----------|---------|-------|",
    ]

    for stage in _STAGE_ORDER:
        ent = stages.get(stage) or {}
        if stage == "quality" and not ent:
            ent = stages.get("smoke") or {}
        ms = _merge_quality_ms(stages) if stage == "quality" else _stage_ms(stages, stage)
        ms_s = str(ms) if ms is not None else "N/A"
        retries = _retry_count(ent) if isinstance(ent, dict) else 0
        notes = ""
        if stage == "quality" and stages.get("smoke") and stages.get("quality"):
            notes = "merged smoke+quality keys"
        elif stage == "quality" and stages.get("smoke") and not stages.get("quality"):
            notes = "from legacy smoke stage key"
        lines.append(f"| {stage} | {ms_s} | {_SLA_HINT} | {retries} | {notes} |")

    lines.extend(["", "## UVO (implement gate)", "| Step | ms | Pass | Note |"])
    for step in uvo.get("steps") or []:
        if not isinstance(step, dict):
            continue
        sid = step.get("id", "")
        dur = step.get("duration_ms", "N/A")
        ok = step.get("ok", step.get("pass", ""))
        note = str(step.get("output") or step.get("command") or "")[:80]
        if "skipped" in note.lower() or "cache hit" in note.lower():
            note = (note or "skipped") + " — cache/skip"
        lines.append(f"| {sid} | {dur} | {ok} | {note} |")
    if not uvo.get("steps"):
        lines.append("| — | N/A | N/A | no verification-oracle.json steps |")
    uvo_total = uvo.get("duration_ms")
    if uvo_total is not None:
        lines.append("")
        lines.append(f"_UVO total duration_ms: {uvo_total}_")

    lines.extend(
        [
            "",
            "## Review provenance",
            f"- latency_ms: {review_run.get('latency_ms', 'N/A')}",
            f"- invocations: {review_run.get('invocation_count', 'N/A')}",
            f"- provider: {review_run.get('provider', 'N/A')}",
            "",
            "## Postmortem / SLA",
            f"- Footnote: {_SLA_HINT}",
            "- Run `pipeline-postmortem.py` for blocked runs (not invoked automatically by this report).",
            "",
            "## Low-value / high-cost flags",
        ]
    )
    flags = _low_value_flags(timing, uvo, smoke_fm)
    for flag in flags:
        lines.append(f"- [ ] {flag}")
    if not flags:
        lines.append("- [ ] (none flagged by v0 rules)")

    lines.append("")
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description="Generate v0 pipeline timing Markdown report")
    ap.add_argument("--task-dir", required=True)
    ap.add_argument("--state-file", default="")
    ap.add_argument("--project-root", default="")
    ap.add_argument("--task-id", default="")
    ap.add_argument("--git-short-head", default="unknown")
    ap.add_argument("--output", default="", help="Write report to file; default stdout")
    args = ap.parse_args()

    repo_task = Path(args.task_dir).resolve()
    task_id = args.task_id or repo_task.name
    goal_ev = resolve_goal_evidence(args.task_dir, args.state_file, args.project_root)
    md = render_report(
        task_id=task_id,
        git_short_head=args.git_short_head,
        goal_evidence=goal_ev,
        repo_task=repo_task,
    )
    if args.output:
        out = Path(args.output)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(md + "\n", encoding="utf-8")
        print(str(out))
    else:
        print(md)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
